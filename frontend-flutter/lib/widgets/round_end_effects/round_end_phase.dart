import 'package:flutter/widgets.dart';

/// The widgets of the round end an overlay aims at, found by these keys:
/// the ZapZap banner and its icon, the table, and per player the row, its
/// round column and its score bar.
class FxKeys {
  final banner = GlobalKey(debugLabel: 'fxBanner');
  final bannerIcon = GlobalKey(debugLabel: 'fxBannerIcon');
  final table = GlobalKey(debugLabel: 'fxTable');
  final _rows = <int, GlobalKey>{};
  final _roundCells = <int, GlobalKey>{};
  final _bars = <int, GlobalKey>{};

  GlobalKey row(int playerIndex) =>
      _rows.putIfAbsent(playerIndex, () => GlobalKey(debugLabel: 'fxRow'));
  GlobalKey roundCell(int playerIndex) => _roundCells.putIfAbsent(
    playerIndex,
    () => GlobalKey(debugLabel: 'fxRoundCell'),
  );
  GlobalKey bar(int playerIndex) =>
      _bars.putIfAbsent(playerIndex, () => GlobalKey(debugLabel: 'fxBar'));
}

/// Where the keyed widgets lie, in the overlay's coordinates.
class FxMeasure {
  FxMeasure(this.origin, this.keys, {this.canScroll = true});

  final RenderBox origin;
  final FxKeys keys;

  /// Whether [reveal] may scroll; once it did, it may not again.
  final bool canScroll;

  Size get size => origin.size;

  /// [key]'s box, or null when it is not laid out.
  Rect? rect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: origin);
    return topLeft & box.size;
  }

  /// Scrolls [key]'s widget into the middle of its scroll view when part of
  /// it lies outside; true when it did, and the geometry is stale until the
  /// next frame.
  bool reveal(GlobalKey key) {
    final context = key.currentContext;
    final target = rect(key);
    if (!canScroll || context == null || target == null) return false;
    final scrollable = Scrollable.maybeOf(context);
    final viewport = scrollable?.context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return false;
    final view =
        viewport.localToGlobal(Offset.zero, ancestor: origin) & viewport.size;
    if (view.top <= target.top && target.bottom <= view.bottom) return false;
    Scrollable.ensureVisible(context, alignment: 0.5);
    return true;
  }
}

/// What the overlays do to the ZapZap banner: squash or pulse it, light
/// its edge.
class BannerLook {
  double scaleX = 1;
  double scaleY = 1;

  /// The amber edge and glow of a charged banner, 0 to 1.
  double glow = 0;
}

/// What the overlays do to one player's row.
class RowLook {
  Offset shake = Offset.zero;
  double tilt = 0;

  /// The red wash of a row that was hit, 0 to 1.
  double flash = 0;

  /// The round column popping and turning red.
  double roundScale = 1;
  double roundRed = 0;

  /// The Eliminated badge: 0 hidden, then popping to 1.
  double badgeScale = 1;
}

/// One overlay of the round end, on its own clock `t` in milliseconds from
/// its start. Every method takes any `t`, before its start and after its
/// end included, and answers from it alone.
abstract class RoundEndPhase {
  /// The key its overlay carries while it plays.
  Key get key;

  /// When the next overlay may start: the figure of the entry.
  double get nominal;

  /// When its last spark is gone.
  double get length;

  /// The rows it moves.
  Set<int> get rows => const {};

  /// The rows whose total it counts up itself.
  Set<int> get totals => const {};

  /// Finds its targets. False when it scrolled the table to show them, and
  /// wants to be measured again once that frame is laid out.
  bool measure(FxMeasure measure);

  /// Whether [measure] found what it draws on.
  bool get ready;

  /// The shake of the whole round end.
  Offset shake(double t) => Offset.zero;
  double tilt(double t) => 0;

  void banner(double t, BannerLook look) {}

  void row(int playerIndex, double t, RowLook look) {}

  /// The total shown on a row of [totals].
  int total(int playerIndex, double t) => 0;

  /// The overlay at [t]: [layer] the part that shakes with the table (the
  /// veil, words, stamps), its sparks and bolts on top, still.
  Widget overlay(double t, Widget Function(Widget layer) shaken);
}
