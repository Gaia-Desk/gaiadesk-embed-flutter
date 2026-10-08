import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gaiadesk_embed/gaiadesk_embed.dart';

import 'fake_native.dart';

Widget _app({required double top, bool masked = true}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        Positioned(
          left: 20,
          top: top,
          width: 200,
          height: 50,
          child: masked ? const GaiaDeskMasked(child: SizedBox.expand()) : const SizedBox.expand(),
        ),
      ],
    ),
  );
}

void main() {
  late FakeNative native;

  setUp(() {
    native = FakeNative()..install();
  });
  tearDown(() => native.uninstall());

  testWidgets('a masked widget on screen is in the start masks, in logical pixels', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(top: 100));
    await tester.runAsync(() => GaiaDeskEmbed.start(
          const EmbedOptions(embedToken: 'gdemb_x', company: 'Acme', masks: [Rect.fromLTWH(0, 0, 10, 10)]),
          consentGranted: true,
        ));
    final masks = (native.named('start').single.arguments as Map)['masks'];
    expect(masks, [
      {'x': 0.0, 'y': 0.0, 'w': 10.0, 'h': 10.0},
      {'x': 20.0, 'y': 100.0, 'w': 200.0, 'h': 50.0},
    ]);
  });

  testWidgets('moving or removing it updates the running session, keeping the app masks', (tester) async {
    await tester.pumpWidget(_app(top: 100));
    final s = (await tester.runAsync(() => GaiaDeskEmbed.start(options, consentGranted: true)))!;
    await tester.runAsync(() => s.setMaskedRects(const [Rect.fromLTWH(1, 1, 1, 1)]));
    native.calls.clear();

    await tester.pumpWidget(_app(top: 300));
    await tester.runAsync(() => pumpEventQueue());
    expect(native.named('setMaskedRects').last.arguments, {
      'session': s.id,
      'masks': [
        {'x': 1.0, 'y': 1.0, 'w': 1.0, 'h': 1.0},
        {'x': 20.0, 'y': 300.0, 'w': 200.0, 'h': 50.0},
      ],
    });

    final before = native.named('setMaskedRects').length;
    await tester.pumpWidget(_app(top: 300)); // nothing moved: nothing sent
    await tester.runAsync(() => pumpEventQueue());
    expect(native.named('setMaskedRects'), hasLength(before));

    await tester.pumpWidget(_app(top: 300, masked: false));
    await tester.pump();
    await tester.runAsync(() => pumpEventQueue());
    expect(native.named('setMaskedRects').last.arguments, {
      'session': s.id,
      'masks': [
        {'x': 1.0, 'y': 1.0, 'w': 1.0, 'h': 1.0},
      ],
    });
  });
}
