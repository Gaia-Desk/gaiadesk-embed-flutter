import 'package:flutter_test/flutter_test.dart';
import 'package:gaiadesk_embed/gaiadesk_embed.dart';

void main() {
  group('EmbedEvent.parse', () {
    test('every kind, from the library JSON', () {
      expect(EmbedEvent.parse('{"type":"state","state":"waiting"}'), const EmbedState('waiting'));
      expect(
        EmbedEvent.parse('{"type":"code","code":"123456789","session_id":"ss_1","mode":"cobrowse","expires_at":"x"}'),
        const EmbedCode(code: '123456789', sessionId: 'ss_1', mode: 'cobrowse'),
      );
      expect(EmbedEvent.parse('{"type":"joined","agent":"ada@acme.test"}'), const EmbedJoined('ada@acme.test'));
      expect(EmbedEvent.parse('{"type":"joined","agent":null}'), const EmbedJoined(null));
      expect(EmbedEvent.parse('{"type":"left"}'), const EmbedLeft());
      expect(EmbedEvent.parse('{"type":"control","allowed":false}'), const EmbedControl(allowed: false));
      expect(EmbedEvent.parse('{"type":"control","allowed":true}'), const EmbedControl(allowed: true));
      expect(
        EmbedEvent.parse('{"type":"action","action":"click","applied":false,"reason":"hint_shown"}'),
        const EmbedAction(action: 'click', applied: false, reason: 'hint_shown'),
      );
      expect(
        EmbedEvent.parse('{"type":"action","action":"type","applied":true}'),
        const EmbedAction(action: 'type', applied: true),
      );
      expect(
        EmbedEvent.parse('{"type":"error","code":"capture_failed","message":"no"}'),
        const EmbedErrorEvent(code: 'capture_failed', message: 'no'),
      );
      expect(EmbedEvent.parse('{"type":"ended","reason":"stopped"}'), const EmbedEnded('stopped'));
    });

    test('maps from the native plugins parse the same', () {
      expect(
        EmbedEvent.parse({'type': 'code', 'code': '1', 'session_id': 's', 'mode': 'view'}),
        const EmbedCode(code: '1', sessionId: 's', mode: 'view'),
      );
      expect(EmbedEvent.parse({'type': 'ended', 'reason': 'app_stopped'}), const EmbedEnded('app_stopped'));
    });

    test('missing fields take safe defaults', () {
      expect(EmbedEvent.parse('{"type":"code"}'), const EmbedCode(code: '', sessionId: '', mode: 'view'));
      expect(EmbedEvent.parse('{"type":"control"}'), const EmbedControl(allowed: false));
      expect(EmbedEvent.parse('{"type":"control","allowed":"yes"}'), const EmbedControl(allowed: false));
      expect(EmbedEvent.parse('{"type":"ended"}'), const EmbedEnded(''));
    });

    test('unknown or malformed is dropped', () {
      expect(EmbedEvent.parse('{"type":"future_kind"}'), isNull);
      expect(EmbedEvent.parse('{"type":"state"}'), isNull);
      expect(EmbedEvent.parse('not json'), isNull);
      expect(EmbedEvent.parse('[1,2]'), isNull);
      expect(EmbedEvent.parse(42), isNull);
      expect(EmbedEvent.parse(null), isNull);
    });
  });
}
