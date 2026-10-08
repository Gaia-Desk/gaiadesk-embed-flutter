import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gaiadesk_embed/gaiadesk_embed.dart';

import 'fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUp(() {
    native = FakeNative()..install();
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await native.uninstall();
  });

  Matcher refusal(String code) => isA<EmbedException>().having((e) => e.code, 'code', code);

  group('consent', () {
    test('start refuses without consent and never reaches native', () async {
      await expectLater(GaiaDeskEmbed.start(options, consentGranted: false), throwsA(refusal('consent_required')));
      expect(native.calls, isEmpty);
    });

    test('a non-bool consent through a dynamic call is refused too', () async {
      final Function start = GaiaDeskEmbed.start;
      Future<void> call(Object? v) async => await Function.apply(start, [options], {#consentGranted: v});
      await expectLater(call('yes'), throwsA(isA<TypeError>()));
      expect(native.calls, isEmpty);
    });

    test('requestConsent passes company, guided and capture; returns the answer', () async {
      native.consentAnswer = false;
      expect(await GaiaDeskEmbed.requestConsent('Acme', guided: true, capture: EmbedCapture.screen), isFalse);
      expect(native.named('requestConsent').single.arguments, {'company': 'Acme', 'guided': true, 'capture': 'screen'});
      native.consentAnswer = true;
      expect(await GaiaDeskEmbed.requestConsent('Acme'), isTrue);
      expect(native.named('requestConsent').last.arguments, {'company': 'Acme', 'guided': false, 'capture': 'app'});
    });

    test('the native refusal comes back as EmbedException', () async {
      native.failures['start'] = PlatformException(code: 'consent_required', message: 'the library says no');
      await expectLater(
        GaiaDeskEmbed.start(options, consentGranted: true),
        throwsA(const EmbedException('consent_required', 'the library says no')),
      );
    });
  });

  group('options to channel arguments', () {
    test('defaults', () async {
      await GaiaDeskEmbed.start(options, consentGranted: true);
      expect(native.named('start').single.arguments, {
        'embedToken': 'gdemb_test',
        'company': 'Acme',
        'server': null,
        'guided': false,
        'fps': 15,
        'masks': <Object>[],
        'capture': 'app',
        'captureMethod': 'replayKit',
        'consentGranted': true,
      });
    });

    test('everything set, masks as logical {x, y, w, h}', () async {
      await GaiaDeskEmbed.start(
        const EmbedOptions(
          embedToken: 'gdemb_x',
          company: 'Acme Bank',
          server: 'https://support.acme.test',
          guided: true,
          fps: 30,
          masks: [Rect.fromLTWH(10, 20, 300, 40), Rect.fromLTWH(0, 0, 0, 0)],
          capture: EmbedCapture.screen,
          captureMethod: IosCaptureMethod.snapshot,
        ),
        consentGranted: true,
      );
      final a = native.named('start').single.arguments as Map;
      expect(a['server'], 'https://support.acme.test');
      expect(a['guided'], true);
      expect(a['fps'], 30);
      expect(a['capture'], 'screen');
      expect(a['captureMethod'], 'snapshot');
      expect(a['masks'], [
        {'x': 10.0, 'y': 20.0, 'w': 300.0, 'h': 40.0},
        {'x': 0.0, 'y': 0.0, 'w': 0.0, 'h': 0.0},
      ]);
    });

    test('screen capture is refused on iOS, allowed on Android', () async {
      const screen = EmbedOptions(embedToken: 'gdemb_x', company: 'Acme', capture: EmbedCapture.screen);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await expectLater(GaiaDeskEmbed.start(screen, consentGranted: true), throwsA(refusal('bad_config')));
      expect(native.calls, isEmpty);
      // iOS takes the capture method.
      await GaiaDeskEmbed.start(const EmbedOptions(embedToken: 'gdemb_x', company: 'Acme', captureMethod: IosCaptureMethod.snapshot), consentGranted: true);
      expect((native.named('start').single.arguments as Map)['captureMethod'], 'snapshot');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await GaiaDeskEmbed.start(screen, consentGranted: true);
      expect((native.named('start').last.arguments as Map)['capture'], 'screen');
    });

    test('other platforms are refused', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await expectLater(GaiaDeskEmbed.start(options, consentGranted: true), throwsA(refusal('unsupported_platform')));
      expect(native.calls, isEmpty);
    });

    test('bad options are refused before native', () async {
      Future<void> start(EmbedOptions o) => GaiaDeskEmbed.start(o, consentGranted: true);
      await expectLater(start(const EmbedOptions(embedToken: ' ', company: 'Acme')), throwsA(refusal('bad_token')));
      await expectLater(start(const EmbedOptions(embedToken: 'gdemb_x', company: '')), throwsA(refusal('bad_config')));
      await expectLater(start(const EmbedOptions(embedToken: 'gdemb_x', company: 'A', fps: 0)), throwsA(refusal('bad_config')));
      await expectLater(start(const EmbedOptions(embedToken: 'gdemb_x', company: 'A', fps: 31)), throwsA(refusal('bad_config')));
      await expectLater(start(const EmbedOptions(embedToken: 'gdemb_x', company: 'A', server: 'ftp://x')), throwsA(refusal('bad_server')));
      await expectLater(start(const EmbedOptions(embedToken: 'gdemb_x', company: 'A', server: 'not a url')), throwsA(refusal('bad_server')));
      await expectLater(
        start(const EmbedOptions(embedToken: 'gdemb_x', company: 'A', masks: [Rect.fromLTRB(10, 10, 0, 20)])),
        throwsA(refusal('bad_rects')),
      );
      await expectLater(
        start(const EmbedOptions(embedToken: 'gdemb_x', company: 'A', masks: [Rect.fromLTWH(0, 0, double.infinity, 1)])),
        throwsA(refusal('bad_rects')),
      );
      expect(native.calls, isEmpty);
    });
  });

  test('buildInfo parses the library JSON', () async {
    final info = await GaiaDeskEmbed.buildInfo();
    expect(info.version, '0.1.0');
    expect(info.codec, 'h264');
    expect(info.os, 'ios');
    expect(info.arch, 'arm64');
    expect(info.testSource, isFalse);
    expect(info.raw['codec'], 'h264');
  });
}
