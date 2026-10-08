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

/// What is masked on screen, measured after each frame: the [GaiaDeskMasked]
/// boxes, every obscured text field (`TextField(obscureText: true)`, any
/// [EditableText] with `obscureText`), and the field that has focus when it
/// is obscured. Tells the running session when the rects change.
///
/// A mask reaches the native side after the frame that moved its widget, so a
/// box that moved is reported conservatively: the union of where it was, where
/// it is and where it will be if it keeps its velocity for one more frame.
/// Once it is still for a frame, the exact rect is reported again (a frame is
/// scheduled for that, so a widget that stops is not over-masked forever).
///
/// Obscured fields are not native views on either platform, so the native
/// SDKs cannot find them: they are found here, by walking the render tree for
/// [RenderEditable]s with `obscureText`. While an obscured field has focus its
/// rect is always reported, clamped into the view (at least 1×1) even when it
/// has scrolled away: the native SDKs refuse guided typing into a focused
/// view that a mask covers (`masked`), and on Android the focused view is the
/// whole Flutter view.
class MaskRegistry {
  MaskRegistry._();

  static final MaskRegistry instance = MaskRegistry._();

  final Set<RenderGaiaDeskMasked> _boxes = {};

  /// Each masked thing's exact rect as of the last frame (a box, a field, or
  /// [_focusKey] for the focused obscured field).
  final Map<Object, Rect> _prev = {};
  static final Object _focusKey = Object();
  List<Rect> _last = const [];
  bool _hooked = false;
  bool _notifyQueued = false;

  /// The rects as of the last frame (widened while their widgets move).
  List<Rect> get rects => List.unmodifiable(_last);

  /// Measure now (at `start`, so masks already on screen cover frame one).
  List<Rect> measure() {
    _hook();
    _prev
      ..clear()
      ..addAll(_exact());
    _last = _prev.values.toList();
    return rects;
  }

  void add(RenderGaiaDeskMasked box) {
    _boxes.add(box);
    _hook();
  }

  void remove(RenderGaiaDeskMasked box) {
    _boxes.remove(box);
    _prev.remove(box);
    SchedulerBinding.instance.scheduleFrame();
  }

  void _hook() {
    if (_hooked) return;
    _hooked = true;
    // Runs after layout and paint in every frame (registered after the
    // renderer's own callback).
    SchedulerBinding.instance.addPersistentFrameCallback((_) => _afterFrame());
    // Focus moving into or out of an obscured field changes the masks even
    // when nothing repaints.
    FocusManager.instance.addListener(SchedulerBinding.instance.scheduleFrame);
  }

  Map<Object, Rect> _exact() {
    final out = <Object, Rect>{
      for (final b in _boxes)
        if (b.globalRect case final r? when !r.isEmpty) b: r,
    };
    for (final view in RendererBinding.instance.renderViews) {
      _obscured(view, out);
    }
    final focused = focusedObscuredRect();
    if (focused != null) out[_focusKey] = focused;
    return out;
  }

  /// Every attached, laid-out [RenderEditable] with `obscureText` under [o].
  static void _obscured(RenderObject o, Map<Object, Rect> out) {
    if (o is RenderEditable && o.obscureText && o.attached && o.hasSize) {
      final r = MatrixUtils.transformRect(o.getTransformTo(null), Offset.zero & o.size);
      if (r.isFinite && !r.isEmpty) out[o] = r;
    }
    o.visitChildren((c) => _obscured(c, out));
  }

  /// The focused field's rect, clamped into its view, when it is obscured;
  /// null otherwise.
  static Rect? focusedObscuredRect() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return null;
    final field = context.widget is EditableText ? context.widget as EditableText : context.findAncestorWidgetOfExactType<EditableText>();
    if (field == null || !field.obscureText) return null;
    final view = View.maybeOf(context);
    final size = view == null ? null : view.physicalSize / view.devicePixelRatio;
    final box = context.findRenderObject();
    Rect? r;
    if (box is RenderBox && box.attached && box.hasSize) {
      r = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    }
    if (size == null || size.isEmpty) return r ?? const Rect.fromLTWH(0, 0, 1, 1);
    r ??= Offset.zero & size;
    return clampInto(r, size);
  }

  /// [r] moved into `Offset.zero & size`, at least 1×1 (a field scrolled away
  /// still covers the view's edge nearest to it). Pure.
  static Rect clampInto(Rect r, Size size) {
    final left = r.left.clamp(0.0, size.width - 1).toDouble();
    final top = r.top.clamp(0.0, size.height - 1).toDouble();
    final right = r.right.clamp(left + 1, size.width).toDouble();
    final bottom = r.bottom.clamp(top + 1, size.height).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// [now] widened to cover [was] and one more frame at the same velocity.
  static Rect widen(Rect was, Rect now) {
    final ahead = now.shift(now.center - was.center);
    return was.expandToInclude(now).expandToInclude(ahead);
  }

  void _afterFrame() {
    final exact = _exact();
    var moving = false;
    final now = <Rect>[];
    for (final MapEntry(key: key, value: r) in exact.entries) {
      final was = _prev[key];
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
