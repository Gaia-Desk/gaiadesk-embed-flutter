// A fake native side: answers the method channel and feeds the event channel.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gaiadesk_embed/gaiadesk_embed.dart';

class FakeNative {
  final List<MethodCall> calls = [];
  MockStreamHandlerEventSink? _sink;
  int _nextId = 1;

  /// Make the next `start` (or any method named here) fail like the SDK does.
  final Map<String, PlatformException> failures = {};
  bool consentAnswer = true;
  String buildInfo = '{"version":"0.1.0","codec":"h264","os":"ios","arch":"arm64","test_source":false}';

  List<MethodCall> named(String method) => calls.where((c) => c.method == method).toList();

  void install() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('gaiadesk_embed'), (call) async {
      calls.add(call);
      final failure = failures[call.method];
      if (failure != null) throw failure;
      switch (call.method) {
        case 'start':
          return _nextId++;
        case 'requestConsent':
          return consentAnswer;
        case 'buildInfo':
          return buildInfo;
        default:
          return null;
      }
    });
    m.setMockStreamHandler(
      const EventChannel('gaiadesk_embed/events'),
      MockStreamHandler.inline(onListen: (args, sink) {
        _sink = sink;
      }, onCancel: (_) {
        _sink = null;
      }),
    );
  }

  Future<void> uninstall() async {
    await GaiaDeskEmbed.resetForTesting();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('gaiadesk_embed'), null);
    m.setMockStreamHandler(const EventChannel('gaiadesk_embed/events'), null);
  }

  /// Send one event for [session] (a map or the library's JSON string), and
  /// let it arrive.
  Future<void> emit(int session, Object event) async {
    _sink!.success({'session': session, 'event': event});
    await pumpEventQueue();
  }
}

const options = EmbedOptions(embedToken: 'gdemb_test', company: 'Acme');
