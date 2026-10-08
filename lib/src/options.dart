import 'package:flutter/widgets.dart';

import 'exception.dart';

/// What is shared. Android only: iOS always shares the app alone.
enum EmbedCapture {
  /// Your app's own window (the default): no permission, no system dialog.
  app,

  /// The whole screen, through MediaProjection: Android asks the user too,
  /// and your app must declare the foreground-service permissions (README).
  screen,
}

/// How iOS captures the app. Both capture only this app.
enum IosCaptureMethod {
  /// ReplayKit in-app capture: exactly what the app shows, including video and
  /// Metal content (so Flutter). iOS asks the user to allow recording of the
  /// app the first time. Not available in the iOS Simulator.
  replayKit,

  /// A snapshot of the app's windows, no system prompt. Works in the
  /// Simulator.
  snapshot,
}

/// How to start a session.
@immutable
class EmbedOptions {
  const EmbedOptions({
    required this.embedToken,
    required this.company,
    this.server,
    this.guided = false,
    this.fps = 15,
    this.masks = const [],
    this.capture = EmbedCapture.app,
    this.captureMethod = IosCaptureMethod.replayKit,
  });

  /// `gdemb_…`, from your backend (`POST /v1/support/sessions`).
  final String embedToken;

  /// Shown on the consent dialog and the indicator.
  final String company;

  /// The GaiaDesk server; default `https://gaiadesk.net`.
  final String? server;

  /// Allow guided input (the session must be `cobrowse` too).
  final bool guided;

  /// 1 to 30.
  final int fps;

  /// Regions painted out from the very first frame, in logical pixels from
  /// the top-left of the Flutter view (what `RenderBox.localToGlobal` gives).
  /// [GaiaDeskMasked] widgets on screen are added for you.
  final List<Rect> masks;

  /// Android only; [EmbedCapture.screen] is refused on iOS.
  final EmbedCapture capture;

  /// iOS only; ignored on Android.
  final IosCaptureMethod captureMethod;

  /// The method channel's `start` arguments, after the checks the native
  /// library would make anyway (so a mistake fails the same way everywhere).
  /// [extraMasks] are the [GaiaDeskMasked] widgets' rects.
  Map<String, Object?> toChannelArguments({
    required String consent,
    required TargetPlatform platform,
    List<Rect> extraMasks = const [],
  }) {
    if (embedToken.trim().isEmpty) {
      throw const EmbedException('bad_token', 'embedToken is empty: pass the gdemb_… token from your backend');
    }
    if (company.trim().isEmpty) {
      throw const EmbedException('bad_config', 'company is empty: it is shown to your user on the consent dialog and indicator');
    }
    if (fps < 1 || fps > 30) {
      throw EmbedException('bad_config', 'fps must be 1 to 30 (got $fps)');
    }
    if (platform == TargetPlatform.iOS && capture == EmbedCapture.screen) {
      throw const EmbedException('bad_config', 'capture: screen is Android only; iOS shares the app alone');
    }
    final s = server;
    if (s != null) {
      final u = Uri.tryParse(s);
      if (u == null || !(u.isScheme('https') || u.isScheme('http')) || u.host.isEmpty) {
        throw EmbedException('bad_server', 'server must be an http(s) URL (got "$s")');
      }
    }
    return {
      'embedToken': embedToken,
      'company': company,
      'server': server,
      'guided': guided,
      'fps': fps,
      'masks': rectsToChannel([...masks, ...extraMasks]),
      'capture': capture.name,
      'captureMethod': captureMethod.name,
      'consent': consent,
    };
  }
}

/// Logical-pixel rects as the channel carries them (`{x, y, w, h}`); the
/// native side converts (iOS: points, the same numbers; Android: × density).
/// Refuses (`bad_rects`) a rect that is not finite or has a negative size.
List<Map<String, double>> rectsToChannel(List<Rect> rects) {
  final out = <Map<String, double>>[];
  for (final r in rects) {
    if (!r.isFinite || r.width < 0 || r.height < 0) {
      throw EmbedException('bad_rects', 'mask rects must be finite with a non-negative size (got $r)');
    }
    out.add({'x': r.left, 'y': r.top, 'w': r.width, 'h': r.height});
  }
  return out;
}
