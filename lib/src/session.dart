import 'dart:async';

import 'package:flutter/services.dart';

import 'events.dart';
import 'exception.dart';
import 'masked.dart';
import 'options.dart';

/// A running share, from [GaiaDeskEmbed.start]. One at a time per app.
class EmbedSession {
  EmbedSession.internal(this.id, this._channel, {required List<Rect> appMasks, required void Function(EmbedSession) onEnded})
      : _appMasks = List.of(appMasks),
        _onEnded = onEnded {
    _controller = StreamController<EmbedEvent>.broadcast(onListen: _flush);
  }

  /// The plugin's handle for this session (not the GaiaDesk session id, which
  /// the [EmbedCode] event carries).
  final int id;

  final MethodChannel _channel;
  final void Function(EmbedSession) _onEnded;
  late final StreamController<EmbedEvent> _controller;
  final Completer<String> _ended = Completer<String>();

  /// Events that arrived before anyone listened (so `code` is never missed
  /// between `start` returning and the app's `listen`).
  final List<EmbedEvent> _early = [];
  bool _listened = false;
  bool _stopRequested = false;
  List<Rect> _appMasks;

  /// Every event, in order, on the main isolate. Events that arrive before the
  /// first listener are kept for it. Closes after [EmbedEnded].
  Stream<EmbedEvent> get events => _controller.stream;

  /// The end reason (`stopped`, `app_stopped`, `disconnected`, `expired`,
  /// `error`). Completes exactly once.
  Future<String> get ended => _ended.future;

  /// Whether [EmbedEnded] has arrived.
  bool get isEnded => _ended.isCompleted;

  /// End the session; an [EmbedEnded] with `app_stopped` follows. Safe to
  /// call more than once, and after the session has ended.
  Future<void> stop() async {
    if (isEnded || _stopRequested) return;
    _stopRequested = true;
    try {
      await _channel.invokeMethod<void>('stop', {'session': id});
    } on PlatformException {
      // Already gone on the native side: its `ended` has been (or will be) sent.
    }
  }

  /// Mask these rects, in logical pixels from the top-left of the Flutter view
  /// (`RenderBox.localToGlobal`). Replaces any earlier set; [GaiaDeskMasked]
  /// widgets are added. Does nothing once the session has ended.
  Future<void> setMaskedRects(List<Rect> rects) async {
    rectsToChannel(rects); // refuse a bad rect before keeping it
    _appMasks = List.of(rects);
    await _sendMasks();
  }

  /// Pause (or resume) guided input. A pause your customer chose on the
  /// indicator is theirs: only they can lift it, and `setPaused(false)` is
  /// ignored until they do (the native SDKs and library enforce this).
  Future<void> setPaused(bool paused) async {
    if (isEnded) return;
    try {
      await _channel.invokeMethod<void>('setPaused', {'session': id, 'paused': paused});
    } on PlatformException catch (e) {
      throw EmbedException.fromPlatform(e);
    }
  }

  Future<void> _sendMasks() async {
    if (isEnded) return;
    final masks = rectsToChannel([..._appMasks, ...MaskRegistry.instance.rects]);
    try {
      await _channel.invokeMethod<void>('setMaskedRects', {'session': id, 'masks': masks});
    } on PlatformException catch (e) {
      throw EmbedException.fromPlatform(e);
    }
  }

  /// A [GaiaDeskMasked] widget moved, appeared or went away.
  void masksChanged() {
    _sendMasks().catchError((Object _) {});
  }

  /// One event from the native side. Nothing follows [EmbedEnded].
  void deliver(EmbedEvent e) {
    if (isEnded) return;
    if (_listened) {
      _controller.add(e);
    } else {
      _early.add(e);
    }
    if (e is EmbedEnded) {
      _ended.complete(e.reason);
      _onEnded(this);
      if (_listened) _controller.close();
    }
  }

  void _flush() {
    if (_listened) return;
    _listened = true;
    for (final e in _early) {
      _controller.add(e);
    }
    _early.clear();
    if (isEnded) _controller.close();
  }
}
