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
/// frame. Over-masking is safe; a mask follows a moving widget one frame
/// later, so keep sensitive widgets still while shared, or mask their area.
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
class MaskRegistry {
  MaskRegistry._();

  static final MaskRegistry instance = MaskRegistry._();

  final Set<RenderGaiaDeskMasked> _boxes = {};
  List<Rect> _last = const [];
  bool _hooked = false;
  bool _notifyQueued = false;

  /// The rects as of the last frame.
  List<Rect> get rects => List.unmodifiable(_last);

  /// Measure now (at `start`, so masks already on screen cover frame one).
  List<Rect> measure() {
    _last = _measure();
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
    SchedulerBinding.instance.scheduleFrame();
  }

  List<Rect> _measure() => [
        for (final b in _boxes)
          if (b.globalRect case final r? when !r.isEmpty) r,
      ];

  void _afterFrame() {
    final now = _measure();
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
