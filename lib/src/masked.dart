import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'embed.dart';

/// Paint [child] out of everything shared with support (card numbers,
/// balances, passwords).
///
/// Its rect is measured after every frame, in logical pixels from the top-left
/// of the Flutter view, and kept current on the running session; a widget on
/// screen when [GaiaDeskEmbed.start] is called is masked from the very first
/// frame. While it moves (scrolling, animation) its mask is widened to where
/// it was and where it is heading, and shrinks back once it stops; a widget
/// that jumps is still covered one frame late, so for content that moves
/// abruptly mask its area or a larger ancestor. Over-masking is safe.
class GaiaDeskMasked extends SingleChildRenderObjectWidget {
  const GaiaDeskMasked({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGaiaDeskMasked();
}

class RenderGaiaDeskMasked extends RenderProxyBox {
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    MaskRegistry.instance.add(this);
  }

  @override
  void detach() {
    MaskRegistry.instance.remove(this);
    super.detach();
  }

  /// This box's bounds in the Flutter view, logical pixels; null when it is
  /// not laid out.
  Rect? get globalRect {
    if (!attached || !hasSize) return null;
    return MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);
  }
}

/// The [GaiaDeskMasked] boxes on screen, measured after each frame. Tells the
/// running session when their rects change.
///
/// A mask reaches the native side after the frame that moved its widget, so a
/// box that moved is reported conservatively: the union of where it was, where
/// it is and where it will be if it keeps its velocity for one more frame.
/// Once it is still for a frame, the exact rect is reported again (a frame is
/// scheduled for that, so a widget that stops is not over-masked forever).
class MaskRegistry {
  MaskRegistry._();

  static final MaskRegistry instance = MaskRegistry._();

  final Set<RenderGaiaDeskMasked> _boxes = {};

  /// Each box's exact rect as of the last frame.
  final Map<RenderGaiaDeskMasked, Rect> _prev = {};
  List<Rect> _last = const [];
  bool _hooked = false;
  bool _notifyQueued = false;

  /// The rects as of the last frame (widened while their widgets move).
  List<Rect> get rects => List.unmodifiable(_last);

  /// Measure now (at `start`, so masks already on screen cover frame one).
  List<Rect> measure() {
    _prev
      ..clear()
      ..addAll(_exact());
    _last = _prev.values.toList();
    return rects;
  }

  void add(RenderGaiaDeskMasked box) {
    _boxes.add(box);
    if (!_hooked) {
      _hooked = true;
      // Runs after layout and paint in every frame (registered after the
      // renderer's own callback).
      SchedulerBinding.instance.addPersistentFrameCallback((_) => _afterFrame());
    }
  }

  void remove(RenderGaiaDeskMasked box) {
    _boxes.remove(box);
    _prev.remove(box);
    SchedulerBinding.instance.scheduleFrame();
  }

  Map<RenderGaiaDeskMasked, Rect> _exact() => {
        for (final b in _boxes)
          if (b.globalRect case final r? when !r.isEmpty) b: r,
      };

  /// [now] widened to cover [was] and one more frame at the same velocity.
  static Rect widen(Rect was, Rect now) {
    final ahead = now.shift(now.center - was.center);
    return was.expandToInclude(now).expandToInclude(ahead);
  }

  void _afterFrame() {
    final exact = _exact();
    var moving = false;
    final now = <Rect>[];
    for (final MapEntry(key: box, value: r) in exact.entries) {
      final was = _prev[box];
      if (was != null && was != r) {
        moving = true;
        now.add(widen(was, r));
      } else {
        now.add(r);
      }
    }
    _prev
      ..clear()
      ..addAll(exact);
    // Shrink back to the exact rects on the next frame.
    if (moving) SchedulerBinding.instance.scheduleFrame();
    if (_same(now, _last)) return;
    _last = now;
    if (_notifyQueued) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      GaiaDeskEmbed.current?.masksChanged();
    });
  }

  static bool _same(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
