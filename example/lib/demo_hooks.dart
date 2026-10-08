// Test hooks for the example, read from the process environment (on the iOS
// Simulator: `SIMCTL_CHILD_<name>` in `xcrun simctl launch`'s environment), so
// one build serves every run. The same names as the native iOS examples:
//
//   GAIADESK_EMBED_TOKEN / GAIADESK_SERVER  as the --dart-define's (these win)
//   GAIADESK_DEMO_AUTOSTART=1               press Get help at launch
//   GAIADESK_DEMO_TEST_CONSENT=1            answer the consent dialog "Share" (tests only)
//   GAIADESK_DEMO_GUIDED=1                  allow guided input
//   GAIADESK_DEMO_CAPTURE=snapshot          iOS: capture by snapshot (the Simulator has no ReplayKit)
//   GAIADESK_DEMO_CMD=1                     run stop|pause|resume written to <app tmp>/gaiadesk-demo-cmd
//
// With any GAIADESK_DEMO_* set, the app prints one JSON object per line
// (`gaiadesk_demo {...}`): `{"type":"demo", "frame", "card", "blue", "buy"}`
// (rects as [x, y, w, h] in logical pixels), every embed event as the
// library's JSON, `{"bought": n}`, `{"start_error": code}`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:gaiadesk_embed/gaiadesk_embed.dart';

Map<String, String> get _env {
  try {
    return Platform.environment;
  } catch (_) {
    return const {};
  }
}

String? demoEnv(String name) {
  final v = _env[name];
  return v == null || v.isEmpty ? null : v;
}

bool demoFlag(String name) => demoEnv(name) == '1';

/// Whether the test hooks are on (any GAIADESK_DEMO_* in the environment).
final bool demoTesting = _env.keys.any((k) => k.startsWith('GAIADESK_DEMO_'));

void demoEmit(Map<String, Object?> o) {
  if (demoTesting) stdout.writeln('gaiadesk_demo ${jsonEncode(o)}');
}

/// An embed event as the library's JSON shape.
Map<String, Object?> demoEventJson(EmbedEvent e) => switch (e) {
      EmbedState(:final state) => {'type': 'state', 'state': state},
      EmbedCode(:final code, :final sessionId, :final mode) => {'type': 'code', 'code': code, 'session_id': sessionId, 'mode': mode},
      EmbedJoined(:final agent) => {'type': 'joined', 'agent': agent},
      EmbedLeft() => {'type': 'left'},
      EmbedControl(:final allowed) => {'type': 'control', 'allowed': allowed},
      EmbedAction(:final action, :final applied, :final reason) => {'type': 'action', 'action': action, 'applied': applied, 'reason': reason},
      EmbedErrorEvent(:final code, :final message) => {'type': 'error', 'code': code, 'message': message},
      EmbedEnded(:final reason) => {'type': 'ended', 'reason': reason},
    };

/// `[x, y, w, h]` of a keyed widget in the Flutter view (logical pixels).
List<double> demoBox(GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return const [0, 0, 0, 0];
  final o = box.localToGlobal(Offset.zero);
  return [o.dx, o.dy, box.size.width, box.size.height];
}

/// GAIADESK_DEMO_CMD=1: poll `<tmp>/gaiadesk-demo-cmd` (the Simulator asks
/// before it opens a URL), run what it says and remove it.
Timer? watchDemoCommands(void Function(String cmd) run) {
  if (!demoFlag('GAIADESK_DEMO_CMD')) return null;
  final file = File('${Directory.systemTemp.path}/gaiadesk-demo-cmd');
  try {
    file.deleteSync();
  } catch (_) {}
  return Timer.periodic(const Duration(milliseconds: 300), (_) {
    String cmd;
    try {
      cmd = file.readAsStringSync().trim();
      file.deleteSync();
    } catch (_) {
      return;
    }
    demoEmit({'type': 'demo_cmd', 'cmd': cmd});
    run(cmd);
  });
}
