import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/app_theme.dart';
import 'fx_core.dart';
import 'round_end_phase.dart';

/// A player the round put out: their total went past 100.
class EliminatedFx {
  const EliminatedFx({
    required this.playerIndex,
    required this.name,
    required this.previousTotal,
    required this.total,
  });

  final int playerIndex;
  final String name;
  final int previousTotal;
  final int total;
}

/// An elimination — "Surchauffe", option C of the proposals (`elimGauge`,
/// 2.2 s): the row is spotlit; its score bar grows into a large gauge above
/// it that climbs from the old total to the new one, and sparks and shakes
/// as it passes the 100 mark; a red "ÉLIMINÉ ×" tape slams across the row,
/// the gauge shrinks back into the bar, the tape leaves and the Eliminated
/// badge pops. Several players out share the one pass: the gauge climbs
/// for each in turn, and each row gets its tape.
class EliminationGaugePhase extends RoundEndPhase {
  EliminationGaugePhase({
    required this.players,
    required this.tapeLabel,
    required this.textDirection,
  }) : assert(players.isNotEmpty) {
    for (final (i, player) in players.indexed) {
      _rowShakes[player.playerIndex] = Shake(301 + i, 3, 240, delay: 1300);
      final (start, span) = _window(i);
      final from = player.previousTotal, to = player.total;
      // When the climb reaches 100: the inverse of its easing.
      final target = to == from ? 1.0 : (100 - from) / (to - from);
      var lo = 0.0, hi = 1.0;
      for (var k = 0; k < 30; k++) {
        final mid = (lo + hi) / 2;
        if (inOut3(mid) < target) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      _crossings.add(start + span * hi);
      _gaugeShakes.add(Shake(311 + i, 5, 420, delay: start + span * hi));
    }
  }

  static const animationKey = Key('eliminationAnimation');

  /// In the order of the table, top first.
  final List<EliminatedFx> players;

  /// "ÉLIMINÉ", in the player's language.
  final String tapeLabel;
  final TextDirection textDirection;

  @override
  Key get key => animationKey;

  @override
  double get nominal => 2200;

  @override
  double get length => 2400;

  @override
  Set<int> get rows => {for (final p in players) p.playerIndex};

  @override
  Set<int> get totals => rows;

  static const _climbFrom = 300.0;
  static const _climb = 720.0;
  static const _tapeIn = 1080.0;
  static const _gaugeOut = 1300.0;
  static const _reveal = 2000.0;
  static const _gaugeHeight = 86.0;

  final _rowShakes = <int, Shake>{};
  final _crossings = <double>[];
  final _gaugeShakes = <Shake>[];

  /// The scale of the gauge: 100 sits at 100/115 of it, as in the
  /// proposal, unless a total goes further.
  late final double _max = math.max(
    115.0,
    players.map((p) => p.total).reduce(math.max) + 5.0,
  );

  List<Rect>? _rows;
  late Rect _gauge;
  late bool _above;
  late double _drop;
  late List<Sparks> _sparks;
  late List<Flash> _flashes;

  @override
  bool get ready => _rows != null;

  @override
  bool measure(FxMeasure measure) {
    final keys = measure.keys;
    if (measure.reveal(keys.row(players.first.playerIndex))) return false;
    final rows = <Rect>[];
    final bars = <Rect>[];
    for (final p in players) {
      final row = measure.rect(keys.row(p.playerIndex));
      final bar = measure.rect(keys.bar(p.playerIndex));
      if (row == null || bar == null) return true;
      rows.add(row);
      bars.add(bar);
    }
    final size = measure.size;
    final first = rows.first;
    _above = first.top - 100 >= 8;
    final top = _above ? first.top - 100 : first.bottom + 14;
    _gauge = Rect.fromLTWH(16, top, size.width - 32, _gaugeHeight);
    _drop = _above
        ? bars.first.top - _gauge.bottom
        : bars.first.bottom - _gauge.top;
    final limit = _limit();
    _sparks = [
      for (var i = 0; i < players.length; i++)
        Sparks(
          seed: 321 + i,
          at: limit,
          count: 48,
          speed: (2, 6),
          angle: (-math.pi * 0.95, -math.pi * 0.05),
          colours: FxPalette.fire,
          gravity: 0.16,
        ),
    ];
    _flashes = [
      for (var i = 0; i < players.length; i++)
        Flash(
          at: limit,
          radius: 90,
          life: 320,
          peak: 0.8,
          colour: const Color(0xFFFDBA74),
        ),
    ];
    _rows = rows;
    return true;
  }

  /// The 100 mark on the gauge's track.
  Offset _limit() => Offset(
    _gauge.left + 12 + (_gauge.width - 24) * 100 / _max,
    _gauge.top + 10 + 32 + 8 + 7,
  );

  /// When [i]'s total climbs, and for how long.
  (double, double) _window(int i) {
    final span = _climb / players.length;
    return (_climbFrom + span * i, span);
  }

  double _value(int i, double t) {
    final (start, span) = _window(i);
    return kf(t, start, span, [
      players[i].previousTotal.toDouble(),
      players[i].total.toDouble(),
    ], ease: inOut3);
  }

  @override
  void row(int playerIndex, double t, RowLook look) {
    final shake = _rowShakes[playerIndex];
    if (shake == null) return;
    look
      ..shake += shake.offset(t)
      ..tilt += shake.angle(t)
      ..badgeScale = t < _reveal
          ? 0
          : kf(
              t,
              _reveal,
              380,
              const [0, 1.35, 1],
              offsets: const [0, 0.6, 1],
              ease: FxCurves.easeOut.transform,
            );
  }

  @override
  int total(int playerIndex, double t) {
    final i = players.indexWhere((p) => p.playerIndex == playerIndex);
    return _value(i, t).round();
  }

  @override
  Widget overlay(double t, Widget Function(Widget layer) shaken) {
    final rows = _rows!;
    return Stack(
      key: animationKey,
      fit: StackFit.expand,
      children: [
        shaken(
          Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: FxPainter(
                  (canvas, size) => paintSpot(
                    canvas,
                    size,
                    rows,
                    0.62 * fadeInOut(t, from: 0, until: _reveal, fadeIn: 240),
                  ),
                ),
              ),
              if (t < _gaugeOut + 260) _gaugeCard(t),
              if (t >= _tapeIn && t < _reveal + 320)
                for (final row in rows) _tape(t, row),
            ],
          ),
        ),
        CustomPaint(
          painter: FxPainter((canvas, size) {
            for (var i = 0; i < players.length; i++) {
              _flashes[i].paint(canvas, size, t - _crossings[i]);
              _sparks[i].paint(canvas, t - _crossings[i]);
            }
          }),
        ),
      ],
    );
  }

  /// The gauge: out of the bar, the climb, back into the bar.
  Widget _gaugeCard(double t) {
    final i = t < _climbFrom
        ? 0
        : ((t - _climbFrom) / (_climb / players.length)).floor().clamp(
            0,
            players.length - 1,
          );
    final value = _value(i, t);
    final hot = value >= 95, out = value >= 100;
    final double grown;
    if (t < _gaugeOut) {
      grown = kf(t, 0, 300, const [0, 1], ease: FxCurves.grow.transform);
    } else {
      grown = kf(t, _gaugeOut, 260, const [
        1,
        0,
      ], ease: FxCurves.easeIn.transform);
    }
    final shake = _gaugeShakes[i];
    final pulse = running(t, _crossings[i], 400)
        ? kf(
            t,
            _crossings[i],
            400,
            const [1, 1.7, 1],
            offsets: const [0, 0.3, 1],
          )
        : 1.0;

    return Positioned.fromRect(
      rect: _gauge,
      child: Opacity(
        opacity: grown.clamp(0.0, 1.0),
        child: Transform(
          alignment: _above ? Alignment.bottomCenter : Alignment.topCenter,
          transform:
              Matrix4.translationValues(
                  shake.offset(t).dx,
                  _drop * (1 - grown) + shake.offset(t).dy,
                  0,
                )
                ..rotateZ(shake.angle(t))
                ..scaleByDouble(0.5 + 0.5 * grown, 0.15 + 0.85 * grown, 1, 1),
          child: _GaugeCard(
            name: players[i].name,
            value: value,
            max: _max,
            hot: hot,
            out: out,
            limitPulse: pulse,
          ),
        ),
      ),
    );
  }

  /// A red tape slammed across [row], its words scrolling.
  Widget _tape(double t, Rect row) {
    final width = row.width * 1.2;
    final double shift;
    final double opacity;
    if (t < _reveal) {
      shift = kf(
        t,
        _tapeIn,
        300,
        const [-1.1, 0.03, 0],
        offsets: const [0, 0.7, 1],
        ease: FxCurves.tape.transform,
      );
      opacity = 1;
    } else {
      final ease = FxCurves.easeIn.transform;
      shift = kf(t, _reveal, 320, const [0, 0.06], ease: ease);
      opacity = kf(t, _reveal, 320, const [1, 0], ease: ease);
    }
    final scroll = kf(t, _tapeIn, 2200, const [0, -0.25]);
    final rtl = textDirection == TextDirection.rtl;
    return Positioned(
      left: row.left - row.width * 0.1,
      width: width,
      top: row.center.dy - 13,
      height: 26,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(shift * width, 0, 0)
            ..rotateZ(-7 * math.pi / 180),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.slate900,
                  AppColors.slate900,
                  Color(0xFFDC2626),
                  Color(0xFFDC2626),
                  AppColors.slate900,
                  AppColors.slate900,
                ],
                stops: [0, 3 / 26, 3 / 26, 23 / 26, 23 / 26, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x8C000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                maxWidth: double.infinity,
                child: FractionalTranslation(
                  translation: Offset(rtl ? -scroll : scroll, 0),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: Text(
                      '$tapeLabel × ' * 10,
                      maxLines: 1,
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The large gauge: the name and the total over a track towards the 100
/// mark, amber, then burning past 95.
class _GaugeCard extends StatelessWidget {
  const _GaugeCard({
    required this.name,
    required this.value,
    required this.max,
    required this.hot,
    required this.out,
    required this.limitPulse,
  });

  final String name;
  final double value;
  final double max;
  final bool hot;
  final bool out;
  final double limitPulse;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xF00F172A),
      border: Border.all(color: AppColors.slate700),
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x99000000),
          blurRadius: 30,
          offset: Offset(0, 14),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.slate100,
                    ),
                  ),
                ),
                Text(
                  '${value.round()}',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 30,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: out ? AppColors.error : AppColors.slate100,
                    shadows: out
                        ? const [
                            Shadow(color: Color(0xCCEF4444), blurRadius: 14),
                          ]
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 14,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final limit = width * 100 / max;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.slate700,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: width * (value / max).clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          gradient: hot
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFF97316),
                                    Color(0xFFEF4444),
                                    Color(0xFFFECACA),
                                  ],
                                  stops: [0, 0.6, 1],
                                )
                              : const LinearGradient(
                                  colors: [
                                    AppColors.amber600,
                                    AppColors.amber400,
                                  ],
                                ),
                          boxShadow: hot
                              ? const [
                                  BoxShadow(
                                    color: Color(0xE6EF4444),
                                    blurRadius: 14,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                    Positioned(
                      left: limit - 1,
                      top: -6,
                      bottom: -6,
                      width: 2,
                      child: Transform.scale(
                        scaleX: 1,
                        scaleY: limitPulse,
                        child: const ColoredBox(color: AppColors.slate100),
                      ),
                    ),
                    Positioned(
                      left: limit - 20,
                      width: 40,
                      top: 21,
                      child: const Text(
                        '100',
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1,
                          color: AppColors.slate100,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
