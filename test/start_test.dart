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
    test('requestConsent passes company, guided and capture; null when declined', () async {
      native.consentAnswer = false;
      expect(await GaiaDeskEmbed.requestConsent('Acme', guided: true, capture: EmbedCapture.screen), isNull);
      expect(native.named('requestConsent').single.arguments, {'company': 'Acme', 'guided': true, 'capture': 'screen'});
      native.consentAnswer = true;
      final c = await GaiaDeskEmbed.requestConsent('Acme');
      expect(c, isNotNull);
      expect((c!.company, c.guided, c.capture), ('Acme', false, EmbedCapture.app));
      expect(native.named('requestConsent').last.arguments, {'company': 'Acme', 'guided': false, 'capture': 'app'});
    });

    test('recordConsent records with the native library; start passes its handle', () async {
      final c = await GaiaDeskEmbed.recordConsent('Acme', guided: true);
      expect(native.named('recordConsent').single.arguments, {'company': 'Acme', 'guided': true, 'capture': 'app'});
      await GaiaDeskEmbed.start(options, consent: c);
      expect((native.named('start').single.arguments as Map)['consent'], c.ref);
    });

    test('a consent starts one session only', () async {
      final c = await consentFor(options);
      final s = await GaiaDeskEmbed.start(options, consent: c);
      await s.stop();
      await expectLater(GaiaDeskEmbed.start(options, consent: c), throwsA(refusal('consent_required')));
      expect(native.named('start'), hasLength(1));
    });

    test('a consent must match the session: company, guided, capture', () async {
      final acme = await GaiaDeskEmbed.recordConsent('Acme');
      await expectLater(
        GaiaDeskEmbed.start(const EmbedOptions(embedToken: 'gdemb_x', company: 'Evil Corp'), consent: acme),
        throwsA(refusal('consent_required')),
      );
      await expectLater(
        GaiaDeskEmbed.start(const EmbedOptions(embedToken: 'gdemb_x', company: 'Acme', guided: true), consent: acme),
        throwsA(refusal('consent_required')),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await expectLater(
        GaiaDeskEmbed.start(const EmbedOptions(embedToken: 'gdemb_x', company: 'Acme', capture: EmbedCapture.screen), consent: acme),
        throwsA(refusal('consent_required')),
      );
      expect(native.named('start'), isEmpty);
      // Refusals before the native call do not spend it.
      await GaiaDeskEmbed.start(options, consent: acme);
      expect(native.named('start'), hasLength(1));
      // Guided consent covers a view-only session.
      final guided = await GaiaDeskEmbed.recordConsent('Acme', guided: true);
      await GaiaDeskEmbed.start(options, consent: guided);
    });

    test('bad options do not spend the consent', () async {
      final c = await consentFor(options);
      await expectLater(
        GaiaDeskEmbed.start(const EmbedOptions(embedToken: ' ', company: 'Acme'), consent: c),
        throwsA(refusal('bad_token')),
      );
      await GaiaDeskEmbed.start(options, consent: c);
    });

    test('the native refusal comes back as EmbedException', () async {
      native.failures['start'] = PlatformException(code: 'consent_required', message: 'the library says no');
      await expectLater(
        startWithConsent(options),
        throwsA(const EmbedException('consent_required', 'the library says no')),
      );
    });
  });

  group('options to channel arguments', () {
    test('defaults', () async {
      await startWithConsent(options);
      expect(native.named('start').single.arguments, {
        'embedToken': 'gdemb_test',
        'company': 'Acme',
        'server': null,
        'guided': false,
        'fps': 15,
        'masks': <Object>[],
        'capture': 'app',
        'captureMethod': 'replayKit',
        'consent': 'c1',
      });
    });

    test('everything set, masks as logical {x, y, w, h}', () async {
      await startWithConsent(
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
      await expectLater(startWithConsent(screen), throwsA(refusal('bad_config')));
      expect(native.named('start'), isEmpty);
      // iOS takes the capture method.
      await startWithConsent(const EmbedOptions(embedToken: 'gdemb_x', company: 'Acme', captureMethod: IosCaptureMethod.snapshot));
      expect((native.named('start').single.arguments as Map)['captureMethod'], 'snapshot');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await startWithConsent(screen);
      expect((native.named('start').last.arguments as Map)['capture'], 'screen');
    });

    test('other platforms are refused', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await expectLater(startWithConsent(options), throwsA(refusal('unsupported_platform')));
      expect(native.named('start'), isEmpty);
    });

    test('bad options are refused before native', () async {
      Future<void> start(EmbedOptions o) => startWithConsent(o);
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
      expect(native.named('start'), isEmpty);
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
