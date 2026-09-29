import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../utils/app_theme.dart';
import '../victory_confetti.dart';
import 'round_end_phase.dart';

export 'countered_stamp.dart' show CounteredStampPhase;
export 'elimination_gauge.dart' show EliminatedFx, EliminationGaugePhase;
export 'held_bolt.dart' show HeldBoltPhase;
export 'round_end_phase.dart' show RoundEndPhase, RowLook;

/// The moments that turn a round, played over the round end as it opens,
/// for every player at the table: the ZapZap overlay (held or
/// counteracted), then the elimination, then — when the game is over and
/// won on this device — the confetti.
///
/// Each overlay starts when the one before has said what it had to (its
/// `nominal` time), their last sparks overlapping. The table under them
/// stays live: a touch anywhere reaches it and skips what is left, so the
/// button is never out of reach. The overlays aim at where the table's
/// widgets were when they started: a scroll (a wheel or a trackpad
/// included) or a resize skips them too. Built only when animations are on
/// (`GameRoundEnd` leaves it out under `MediaQuery.disableAnimations`).
class RoundEndEffects extends StatefulWidget {
  const RoundEndEffects({
    super.key,
    required this.phases,
    required this.celebrate,
    required this.child,
  });

  /// The overlays, in order; read once, as the round end opens.
  final List<RoundEndPhase> Function() phases;

  /// The confetti of a win, after the overlays.
  final bool celebrate;

  /// The round end itself.
  final Widget child;

  @override
  State<RoundEndEffects> createState() => _RoundEndEffectsState();
}

class _RoundEndEffectsState extends State<RoundEndEffects>
    with SingleTickerProviderStateMixin {
  late final RoundEndFxController _fx = RoundEndFxController(
    widget.phases(),
    vsync: this,
    origin: () {
      final box = context.findRenderObject();
      return box is RenderBox && box.hasSize ? box : null;
    },
    onFinished: () {
      if (mounted) setState(() => _confetti = widget.celebrate);
    },
  );
  late bool _confetti = widget.celebrate && _fx.isEmpty;

  @override
  void initState() {
    super.initState();
    // Measured once laid out: the overlays aim at the table's widgets.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fx.start();
    });
  }

  @override
  void dispose() {
    _fx.dispose();
    super.dispose();
  }

  Widget _shaken(Widget child) => FxShake(controller: _fx, child: child);

  /// A scroll the overlays did not ask for moves the table under them.
  bool _onScroll(ScrollUpdateNotification notification) {
    if (!_fx.revealing) _fx.skip();
    return false;
  }

  /// Sent during layout: the skip waits for the frame to end.
  bool _onResize(SizeChangedLayoutNotification notification) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fx.skip();
    });
    return false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _fx.skip(),
    child: ClipRect(
      child: Stack(
        children: [
          NotificationListener<ScrollUpdateNotification>(
            onNotification: _onScroll,
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: _onResize,
              child: RoundEndFx(
                controller: _fx,
                child: _shaken(
                  // Its own layer: a shake moves it, never repaints it.
                  RepaintBoundary(
                    child: SizeChangedLayoutNotifier(child: widget.child),
                  ),
                ),
              ),
            ),
          ),
          if (!_fx.finished)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: ListenableBuilder(
                    listenable: _fx,
                    builder: (context, _) => Stack(
                      fit: StackFit.expand,
                      children: [
                        for (final (phase, t) in _fx.playing)
                          phase.overlay(t, _shaken),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_confetti)
            const Positioned.fill(
              child: VictoryConfetti(key: Key('victoryAnimation')),
            ),
        ],
      ),
    ),
  );
}

/// The clock of the overlays, and what they do to the round end's own
/// widgets at each tick: the shake of the whole, the banner, each row and
/// the totals the overlays count up themselves.
class RoundEndFxController extends ChangeNotifier {
  RoundEndFxController(
    List<RoundEndPhase> phases, {
    required TickerProvider vsync,
    required this.origin,
    required this.onFinished,
  }) {
    var start = 0.0, end = 0.0;
    for (final phase in phases) {
      _timeline.add((phase: phase, start: start));
      end = math.max(end, start + phase.length);
      start += phase.nominal;
    }
    _length = end;
    _clock = AnimationController(
      vsync: vsync,
      duration: Duration(milliseconds: math.max(1, end.ceil())),
    )..addListener(_tick);
    _clock.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  final keys = FxKeys();

  /// The overlay's box, which the targets are measured against.
  final RenderBox? Function() origin;

  /// Called once, when the overlays are over or skipped.
  final VoidCallback onFinished;
  final _timeline = <({RoundEndPhase phase, double start})>[];
  late final double _length;
  late final AnimationController _clock;
  final _waiting = <RoundEndPhase>{};

  /// An overlay is scrolling the table to its rows: that scroll does not
  /// skip it.
  bool get revealing => _revealing;
  bool _revealing = false;

  bool get isEmpty => _timeline.isEmpty;

  /// Every overlay is over, or was skipped.
  bool get finished => _finished;
  bool _finished = false;

  /// Milliseconds since the first overlay started.
  double get t => _clock.value * _length;

  void start() {
    if (_timeline.isEmpty) {
      _finish();
    } else {
      _tick();
      _clock.forward();
    }
  }

  /// A touch: straight to the end state.
  void skip() => _finish();

  void _finish() {
    if (_finished) return;
    _finished = true;
    _clock.stop();
    notifyListeners();
    onFinished();
  }

  void _tick() {
    for (final (:phase, :start) in _timeline) {
      if (t >= start && !phase.ready && !_waiting.contains(phase)) {
        _measure(phase, canScroll: true);
      }
    }
    notifyListeners();
  }

  void _measure(RoundEndPhase phase, {required bool canScroll}) {
    final origin = this.origin();
    if (origin == null) return;
    _revealing = true;
    final measured = phase.measure(
      FxMeasure(origin, keys, canScroll: canScroll),
    );
    _revealing = false;
    if (measured) return;
    // It scrolled the table to its rows: measured again once laid out.
    _waiting.add(phase);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _waiting.remove(phase);
      if (!_finished) _measure(phase, canScroll: false);
    });
  }

  /// The overlays on screen, with their own clocks.
  Iterable<(RoundEndPhase, double)> get playing sync* {
    if (_finished) return;
    for (final (:phase, :start) in _timeline) {
      final local = t - start;
      if (phase.ready && local >= 0 && local < phase.length) {
        yield (phase, local);
      }
    }
  }

  Offset get shake {
    if (_finished) return Offset.zero;
    var offset = Offset.zero;
    for (final (:phase, :start) in _timeline) {
      offset += phase.shake(t - start);
    }
    return offset;
  }

  double get tilt {
    if (_finished) return 0;
    var angle = 0.0;
    for (final (:phase, :start) in _timeline) {
      angle += phase.tilt(t - start);
    }
    return angle;
  }

  BannerLook get banner {
    final look = BannerLook();
    if (_finished) return look;
    for (final (:phase, :start) in _timeline) {
      phase.banner(t - start, look);
    }
    return look;
  }

  /// Whether an overlay moves [playerIndex]'s row.
  bool touchesRow(int playerIndex) =>
      _timeline.any((e) => e.phase.rows.contains(playerIndex));

  RowLook row(int playerIndex) {
    final look = RowLook();
    if (_finished) return look;
    for (final (:phase, :start) in _timeline) {
      if (phase.rows.contains(playerIndex)) {
        phase.row(playerIndex, t - start, look);
      }
    }
    return look;
  }

  /// The total an overlay shows on [playerIndex]'s row, or null when the
  /// row counts it up alone (or every overlay is over).
  int? totalOf(int playerIndex) {
    if (_finished) return null;
    for (final (:phase, :start) in _timeline) {
      if (phase.totals.contains(playerIndex)) {
        return phase.total(playerIndex, t - start);
      }
    }
    return null;
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }
}

/// Hands the overlays' controller to the round end's widgets.
class RoundEndFx extends InheritedWidget {
  const RoundEndFx({super.key, required this.controller, required super.child});

  final RoundEndFxController controller;

  static RoundEndFxController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoundEndFx>()?.controller;

  @override
  bool updateShouldNotify(RoundEndFx oldWidget) =>
      oldWidget.controller != controller;
}

/// Shakes [child] with the overlays (`s.shake` of the whole screen): a
/// transform set on its render object at each tick, identity — nothing
/// pushed, nothing rebuilt — while no overlay shakes.
class FxShake extends SingleChildRenderObjectWidget {
  const FxShake({super.key, required this.controller, super.child});

  final RoundEndFxController controller;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderFxShake(controller);

  @override
  void updateRenderObject(BuildContext context, RenderFxShake renderObject) =>
      renderObject.controller = controller;
}

/// The render object of [FxShake].
class RenderFxShake extends RenderTransform {
  RenderFxShake(this._controller)
    : super(transform: Matrix4.identity(), alignment: Alignment.center);

  RoundEndFxController _controller;

  set controller(RoundEndFxController value) {
    if (value == _controller) return;
    if (attached) _controller.removeListener(_update);
    _controller = value;
    if (attached) {
      _controller.addListener(_update);
      _update();
    }
  }

  void _update() {
    final shake = _controller.shake, tilt = _controller.tilt;
    transform = shake == Offset.zero && tilt == 0
        ? Matrix4.identity()
        : (Matrix4.translationValues(shake.dx, shake.dy, 0)..rotateZ(tilt));
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_update);
    _update();
  }

  @override
  void detach() {
    _controller.removeListener(_update);
    super.detach();
  }
}

enum _Target { banner, bannerIcon, table }

/// A widget of the round end the overlays aim at; itself alone when no
/// overlay plays.
class FxTarget extends StatelessWidget {
  /// The ZapZap banner: squashed, pulsed and lit by the overlays.
  const FxTarget.banner({super.key, required this.child})
    : _target = _Target.banner;
  const FxTarget.bannerIcon({super.key, required this.child})
    : _target = _Target.bannerIcon;
  const FxTarget.table({super.key, required this.child})
    : _target = _Target.table;

  final _Target _target;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fx = RoundEndFx.maybeOf(context);
    if (fx == null) return child;
    return switch (_target) {
      _Target.bannerIcon => KeyedSubtree(key: fx.keys.bannerIcon, child: child),
      _Target.table => KeyedSubtree(key: fx.keys.table, child: child),
      _Target.banner => KeyedSubtree(
        key: fx.keys.banner,
        child: ListenableBuilder(
          listenable: fx,
          builder: (context, child) {
            final look = fx.banner;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(look.scaleX, look.scaleY, 1),
              child: CustomPaint(painter: _Charge(look.glow), child: child),
            );
          },
          child: child,
        ),
      ),
    };
  }
}

/// A charged banner's edge (`.zz.charged`): a light amber line round it
/// and a glow outside it — outside only, as a CSS box shadow, so that it
/// does not show through the banner's tinted background.
class _Charge extends CustomPainter {
  _Charge(this.glow);

  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (glow <= 0) return;
    final box = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect((Offset.zero & size).inflate(48))
          ..addRRect(box),
      )
      ..drawRRect(
        box,
        Paint()
          ..color = AppColors.amber400.withValues(alpha: 0.55 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
      )
      ..drawRRect(
        box.inflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.amber200.withValues(alpha: 0.9 * glow),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_Charge old) => old.glow != glow;
}
