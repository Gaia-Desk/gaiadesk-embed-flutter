// Obscured text fields (passwords) are masked without being wrapped in
// GaiaDeskMasked: they are not native views, so the native SDKs cannot find
// them. A focused obscured field is always masked (clamped into the view),
// which is what makes the native SDKs refuse guided typing into it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gaiadesk_embed/src/masked.dart' show MaskRegistry;

import 'fake_native.dart';

Widget _form({required bool obscure, double top = 100, FocusNode? focus, ScrollController? scroll}) {
  return MaterialApp(
    home: Scaffold(
      body: ListView(
        controller: scroll,
        children: [
          SizedBox(height: top),
          SizedBox(width: 300, child: TextField(key: const Key('user'), decoration: const InputDecoration(labelText: 'User'))),
          SizedBox(width: 300, child: TextField(key: const Key('pw'), focusNode: focus, obscureText: obscure)),
          const SizedBox(height: 3000),
        ],
      ),
    ),
  );
}

List<Rect> _sent(FakeNative native) {
  final masks = (native.named('setMaskedRects').last.arguments as Map)['masks'] as List;
  return [for (final m in masks.cast<Map>()) Rect.fromLTWH(m['x'] as double, m['y'] as double, m['w'] as double, m['h'] as double)];
}

List<Rect> _started(FakeNative native) {
  final masks = (native.named('start').single.arguments as Map)['masks'] as List;
  return [for (final m in masks.cast<Map>()) Rect.fromLTWH(m['x'] as double, m['y'] as double, m['w'] as double, m['h'] as double)];
}

Rect _textOf(WidgetTester tester, String key) {
  final r = tester.state<EditableTextState>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(EditableText))).renderEditable;
  return MatrixUtils.transformRect(r.getTransformTo(null), Offset.zero & r.size);
}

bool _covers(List<Rect> masks, Rect r) => masks.any((m) => m.intersect(r) == r);

void main() {
  late FakeNative native;

  setUp(() {
    native = FakeNative()..install();
  });
  tearDown(() => native.uninstall());

  testWidgets('an obscured field on screen is masked from the first frame; a plain one is not', (tester) async {
    await tester.pumpWidget(_form(obscure: true));
    await tester.runAsync(() => startWithConsent(options));
    final masks = _started(native);
    expect(_covers(masks, _textOf(tester, 'pw')), isTrue, reason: '$masks');
    expect(masks.any((m) => m.overlaps(_textOf(tester, 'user'))), isFalse, reason: '$masks');
  });

  testWidgets('obscuring a field during a session masks it; un-obscuring unmasks it', (tester) async {
    await tester.pumpWidget(_form(obscure: false));
    final s = (await tester.runAsync(() => startWithConsent(options)))!;
    expect(_started(native), isEmpty);
    await tester.pumpWidget(_form(obscure: true));
    await tester.runAsync(() => pumpEventQueue());
    expect(_covers(_sent(native), _textOf(tester, 'pw')), isTrue);
    await tester.pumpWidget(_form(obscure: false));
    await tester.pump();
    await tester.runAsync(() => pumpEventQueue());
    expect(_sent(native), isEmpty);
    await tester.runAsync(() => s.stop());
  });

  testWidgets('a focused obscured field scrolled out of view is still masked (clamped into the view)', (tester) async {
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_form(obscure: true, focus: focus, scroll: scroll));
    focus.requestFocus();
    await tester.pump();
    final s = (await tester.runAsync(() => startWithConsent(options)))!;
    // Scrolled far below: the field is off screen (and ListView may drop it).
    scroll.jumpTo(2500);
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() => pumpEventQueue());
    expect(focus.hasFocus, isTrue);
    final masks = _sent(native);
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(masks, isNotEmpty, reason: 'typing into the focused password must stay refused');
    expect(masks.every((m) => (Offset.zero & view).intersect(m) == m && m.width >= 1 && m.height >= 1), isTrue, reason: '$masks');
    // Focus leaves the obscured field: nothing is left masked.
    focus.unfocus();
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() => pumpEventQueue());
    expect(_sent(native), isEmpty);
    await tester.runAsync(() => s.stop());
  });

  test('clampInto keeps a rect inside the view, at least 1x1', () {
    const size = Size(400, 800);
    expect(MaskRegistry.clampInto(const Rect.fromLTWH(10, 20, 100, 40), size), const Rect.fromLTWH(10, 20, 100, 40));
    expect(MaskRegistry.clampInto(const Rect.fromLTWH(10, 2000, 100, 40), size), const Rect.fromLTRB(10, 799, 110, 800));
    expect(MaskRegistry.clampInto(const Rect.fromLTWH(-500, -500, 10, 10), size), const Rect.fromLTRB(0, 0, 1, 1));
  });
}
