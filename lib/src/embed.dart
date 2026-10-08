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

  /// Start sharing. [consentGranted] must be your user's answer to a consent
  /// dialog ([requestConsent], or your own): anything but `true` is refused
  /// here (`consent_required`), and the native library refuses it again.
  /// Throws [EmbedException].
  static Future<EmbedSession> start(EmbedOptions options, {required bool consentGranted}) async {
    // Literally `true` (a dynamic call can pass anything).
    if (!identical(consentGranted as Object?, true)) {
      throw const EmbedException('consent_required', 'ask your user first (GaiaDeskEmbed.requestConsent) and pass their answer as consentGranted');
    }
    final platform = defaultTargetPlatform;
    if (kIsWeb || (platform != TargetPlatform.iOS && platform != TargetPlatform.android)) {
      throw const EmbedException('unsupported_platform', 'gaiadesk_embed runs on iOS and Android');
    }
    final args = options.toChannelArguments(
      consentGranted: true,
      platform: platform,
      extraMasks: MaskRegistry.instance.measure(),
    );
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
    for (final e in _early.remove(id) ?? const <EmbedEvent>[]) {
      session.deliver(e);
    }
    return session;
  }

  /// Ask the user, with the native SDK's dialog (UIAlertController on iOS,
  /// AlertDialog on Android). Pass the answer to [start]. [capture] changes
  /// the wording on Android only.
  static Future<bool> requestConsent(String company, {bool guided = false, EmbedCapture capture = EmbedCapture.app}) async {
    try {
      final ok = await _methods.invokeMethod<bool>('requestConsent', {
        'company': company,
        'guided': guided,
        'capture': capture.name,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      throw EmbedException.fromPlatform(e);
    }
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
