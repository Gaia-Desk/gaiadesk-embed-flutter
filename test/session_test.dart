import 'dart:async';

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
  tearDown(() => native.uninstall());

  test('events arrive in order, routed to their session', () async {
    final s = await GaiaDeskEmbed.start(options, consentGranted: true);
    final got = <EmbedEvent>[];
    s.events.listen(got.add);
    await native.emit(s.id, {'type': 'state', 'state': 'waiting'});
    await native.emit(s.id, '{"type":"code","code":"123456789","session_id":"ss_1","mode":"view"}');
    await native.emit(s.id + 1, {'type': 'joined', 'agent': 'someone-else'}); // not this session
    await native.emit(s.id, {'type': 'unknown_future_kind'});
    await native.emit(s.id, {'type': 'joined', 'agent': 'ada@acme.test'});
    expect(got, const [
      EmbedState('waiting'),
      EmbedCode(code: '123456789', sessionId: 'ss_1', mode: 'view'),
      EmbedJoined('ada@acme.test'),
    ]);
  });

  test('events before the first listener are kept for it', () async {
    final s = await GaiaDeskEmbed.start(options, consentGranted: true);
    await native.emit(s.id, {'type': 'code', 'code': '1', 'session_id': 's', 'mode': 'view'});
    final first = await s.events.first;
    expect(first, const EmbedCode(code: '1', sessionId: 's', mode: 'view'));
  });

  test('ended completes once, closes events, and nothing follows it', () async {
    final s = await GaiaDeskEmbed.start(options, consentGranted: true);
    final got = <EmbedEvent>[];
    final done = Completer<void>();
    s.events.listen(got.add, onDone: done.complete);
    expect(GaiaDeskEmbed.current, same(s));
    await native.emit(s.id, {'type': 'ended', 'reason': 'stopped'});
    await native.emit(s.id, {'type': 'ended', 'reason': 'error'});
    await native.emit(s.id, {'type': 'left'});
    expect(await s.ended, 'stopped');
    await done.future;
    expect(got, const [EmbedEnded('stopped')]);
    expect(s.isEnded, isTrue);
    expect(GaiaDeskEmbed.current, isNull);
  });

  test('a session that ended before anyone listened replays then closes', () async {
    final s = await GaiaDeskEmbed.start(options, consentGranted: true);
    await native.emit(s.id, {'type': 'error', 'code': 'capture_failed', 'message': 'x'});
    await native.emit(s.id, {'type': 'ended', 'reason': 'error'});
    expect(await s.events.toList(), const [EmbedErrorEvent(code: 'capture_failed', message: 'x'), EmbedEnded('error')]);
  });

  test('stop is idempotent and stops after the end', () async {
    final s = await GaiaDeskEmbed.start(options, consentGranted: true);
    await Future.wait([s.stop(), s.stop()]);
    await s.stop();
    expect(native.named('stop').map((c) => c.arguments), [
      {'session': s.id},
    ]);
    await native.emit(s.id, {'type': 'ended', 'reason': 'app_stopped'});
    expect(await s.ended, 'app_stopped');
    await s.stop();
    expect(native.named('stop'), hasLength(1));
  });

  test('stop swallows a native refusal (the session is already gone)', () async {
    final s = await GaiaDeskEmbed.start(options, consentGranted: true);
    native.failures['stop'] = PlatformException(code: 'gone');
    await s.stop();
  });

  test('setMaskedRects sends logical rects; refuses bad ones; no-op after the end', () async {
    final s = await GaiaDeskEmbed.start(options, consentGranted: true);
    await s.setMaskedRects(const [Rect.fromLTWH(1, 2, 3, 4)]);
    expect(native.named('setMaskedRects').single.arguments, {
      'session': s.id,
      'masks': [
        {'x': 1.0, 'y': 2.0, 'w': 3.0, 'h': 4.0},
      ],
    });
    await expectLater(
      s.setMaskedRects(const [Rect.fromLTRB(5, 5, 1, 1)]),
      throwsA(isA<EmbedException>().having((e) => e.code, 'code', 'bad_rects')),
    );
    native.failures['setMaskedRects'] = PlatformException(code: 'bad_rects', message: 'library refused');
    await expectLater(s.setMaskedRects(const []), throwsA(const EmbedException('bad_rects', 'library refused')));
    native.failures.clear();
    await native.emit(s.id, {'type': 'ended', 'reason': 'stopped'});
    await s.setMaskedRects(const [Rect.fromLTWH(0, 0, 1, 1)]);
    expect(native.named('setMaskedRects'), hasLength(2));
  });

  test('setPaused', () async {
    final s = await GaiaDeskEmbed.start(options, consentGranted: true);
    await s.setPaused(true);
    await s.setPaused(false);
    expect(native.named('setPaused').map((c) => c.arguments), [
      {'session': s.id, 'paused': true},
      {'session': s.id, 'paused': false},
    ]);
  });

  test('a second session gets its own events', () async {
    final a = await GaiaDeskEmbed.start(options, consentGranted: true);
    await native.emit(a.id, {'type': 'ended', 'reason': 'app_stopped'});
    final b = await GaiaDeskEmbed.start(options, consentGranted: true);
    expect(b.id, isNot(a.id));
    expect(GaiaDeskEmbed.current, same(b));
    await native.emit(b.id, {'type': 'state', 'state': 'connected'});
    expect(await b.events.first, const EmbedState('connected'));
    expect(await a.ended, 'app_stopped');
  });
}
