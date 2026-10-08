import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'events.dart';
import 'exception.dart';
import 'masked.dart';
import 'options.dart';
import 'session.dart';

/// What the bundled native library is.
@immutable
class EmbedBuildInfo {
  const EmbedBuildInfo({required this.version, required this.codec, required this.os, required this.arch, required this.testSource, required this.raw});

  /// The native library's JSON (`{version, codec, os, arch, test_source}`).
  factory EmbedBuildInfo.fromJson(String json) {
    final decoded = jsonDecode(json);
    final o = decoded is Map ? Map<String, Object?>.from(decoded) : <String, Object?>{};
    String s(String k) => o[k] is String ? o[k] as String : '';
    return EmbedBuildInfo(
      version: s('version'),
      codec: s('codec'),
      os: s('os'),
      arch: s('arch'),
      testSource: o['test_source'] == true,
      raw: o,
    );
  }

  final String version;
  final String codec;
  final String os;
  final String arch;

  /// A test build (frames from a test source, not the app).
  final bool testSource;

  /// Everything the library reported.
  final Map<String, Object?> raw;
}

/// Your user's YES to sharing (from [GaiaDeskEmbed.requestConsent] or
/// [GaiaDeskEmbed.recordConsent]), bound to what they were asked. Opaque:
/// the native side holds the library's single-use consent; [GaiaDeskEmbed.start]
/// takes it once.
@immutable
final class EmbedConsent {
  const EmbedConsent._(this.ref, {required this.company, required this.guided, required this.capture});

  /// The native plugin's handle for it (not the library's token). Not for
  /// apps: pass the whole value to [GaiaDeskEmbed.start].
  final String ref;

  /// Who the user agreed to share with.
  final String company;

  /// Whether they were asked about guided input.
  final bool guided;

  /// What they agreed to share (Android).
  final EmbedCapture capture;

  @override
  String toString() => 'EmbedConsent($company, guided: $guided, capture: ${capture.name})';
}

/// Start, and ask for consent. See the package README.
abstract final class GaiaDeskEmbed {
  static const MethodChannel _methods = MethodChannel('gaiadesk_embed');
  static const EventChannel _events = EventChannel('gaiadesk_embed/events');

  static StreamSubscription<Object?>? _sub;
  static final Map<int, EmbedSession> _sessions = {};
  static final Map<int, List<EmbedEvent>> _early = {};
  static int _highestId = 0;
  static EmbedSession? _current;

  /// The session running in this app, if any.
  static EmbedSession? get current => _current;

  /// Start sharing. [consent] is your user's YES to a consent dialog:
  /// [requestConsent] (the SDK's), or [recordConsent] right after your own.
  /// It is single-use, expires after 10 minutes, and must match the session
  /// (the same company and capture, and guided only if the user was asked
  /// about guiding): refused here (`consent_required`), and again by the
  /// native library, which issued it. Throws [EmbedException].
  static Future<EmbedSession> start(EmbedOptions options, {required EmbedConsent consent}) async {
    if (consent.company != options.company) {
      throw const EmbedException('consent_required', 'the consent was given for another company: ask again with this session\'s company');
    }
    if (options.guided && !consent.guided) {
      throw const EmbedException('consent_required', 'a guided session needs consent that asked about guiding (requestConsent(company, guided: true))');
    }
    if (consent.capture != options.capture) {
      throw const EmbedException('consent_required', 'the consent was given for another capture: ask again with this session\'s capture');
    }
    final platform = defaultTargetPlatform;
    if (kIsWeb || (platform != TargetPlatform.iOS && platform != TargetPlatform.android)) {
      throw const EmbedException('unsupported_platform', 'gaiadesk_embed runs on iOS and Android');
    }
    final args = options.toChannelArguments(
      consent: consent.ref,
      platform: platform,
      extraMasks: MaskRegistry.instance.measure(),
    );
    // Spent here, after every other check: single use, as in the library.
    if (!_unusedConsents.remove(consent.ref)) {
      throw const EmbedException('consent_required', 'this consent was already used: ask your user again');
    }
    _listen();
    final int? id;
    try {
      id = await _methods.invokeMethod<int>('start', args);
    } on PlatformException catch (e) {
      throw EmbedException.fromPlatform(e);
    }
    if (id == null) throw const EmbedException('unknown', 'the native plugin returned no session');
    if (id > _highestId) _highestId = id;
    final session = EmbedSession.internal(id, _methods, appMasks: options.masks, onEnded: _ended);
    _sessions[id] = session;
    _current = session;
    // Always said once: it also tells the native SDKs that this app reports
    // secret focus itself (on Android it replaces the "focused view under a
    // mask" rule, which sees the whole Flutter view as one field).
    session.secretFocusChanged(MaskRegistry.instance.secretFocusNow());
    for (final e in _early.remove(id) ?? const <EmbedEvent>[]) {
      session.deliver(e);
    }
    return session;
  }

  /// Ask the user, with the native SDK's dialog (UIAlertController on iOS,
  /// AlertDialog on Android). Their YES, for [start]; null when they declined.
  /// [capture] changes the wording on Android only.
  static Future<EmbedConsent?> requestConsent(String company, {bool guided = false, EmbedCapture capture = EmbedCapture.app}) async {
    try {
      final ref = await _methods.invokeMethod<String>('requestConsent', {
        'company': company,
        'guided': guided,
        'capture': capture.name,
      });
      return ref == null ? null : _consent(ref, company, guided, capture);
    } on PlatformException catch (e) {
      throw EmbedException.fromPlatform(e);
    }
  }

  /// Your own consent dialog said YES: call this right then, with what it
  /// asked (the company named, whether it said the agent may guide, what is
  /// shared). Never call it without asking. The native library records the
  /// answer; the result is what [start] takes.
  static Future<EmbedConsent> recordConsent(String company, {bool guided = false, EmbedCapture capture = EmbedCapture.app}) async {
    try {
      final ref = await _methods.invokeMethod<String>('recordConsent', {
        'company': company,
        'guided': guided,
        'capture': capture.name,
      });
      if (ref == null) throw const EmbedException('unknown', 'the native plugin recorded no consent');
      return _consent(ref, company, guided, capture);
    } on PlatformException catch (e) {
      throw EmbedException.fromPlatform(e);
    }
  }

  static final Set<String> _unusedConsents = {};

  static EmbedConsent _consent(String ref, String company, bool guided, EmbedCapture capture) {
    _unusedConsents.add(ref);
    return EmbedConsent._(ref, company: company, guided: guided, capture: capture);
  }

  /// What the bundled native library is.
  static Future<EmbedBuildInfo> buildInfo() async {
    try {
      final json = await _methods.invokeMethod<String>('buildInfo');
      return EmbedBuildInfo.fromJson(json ?? '{}');
    } on PlatformException catch (e) {
      throw EmbedException.fromPlatform(e);
    }
  }

  /// Forget every session and the event subscription. Tests only.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _sub?.cancel();
    _sub = null;
    _sessions.clear();
    _early.clear();
    _highestId = 0;
    _current = null;
    _unusedConsents.clear();
  }

  static void _listen() {
    _sub ??= _events.receiveBroadcastStream().listen(_onMessage, onError: (Object _) {});
  }

  /// `{session: int, event: <the library's JSON string, or a map of it>}`.
  static void _onMessage(Object? message) {
    if (message is! Map) return;
    final id = message['session'];
    if (id is! int) return;
    final event = EmbedEvent.parse(message['event']);
    if (event == null) return;
    final session = _sessions[id];
    if (session != null) {
      session.deliver(event);
    } else if (id > _highestId) {
      // Sent before `start` returned: kept for it (bounded).
      final early = _early.putIfAbsent(id, () => []);
      if (early.length < 64) early.add(event);
    }
  }

  static void _ended(EmbedSession session) {
    _sessions.remove(session.id);
    if (identical(_current, session)) _current = null;
  }
}
