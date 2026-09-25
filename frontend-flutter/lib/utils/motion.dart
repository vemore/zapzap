import 'package:flutter/widgets.dart';

/// The board's motion (J9 of the UX study): how long each move takes, and
/// the one switch that turns them all off.
///
/// Every animation of the board reads its duration through [of], so a
/// system asking for reduced motion (`MediaQuery.disableAnimations`) gets
/// the end state at once and no frame is scheduled for it.
abstract final class Motion {
  /// A selected card rising out of the hand.
  static const lift = Duration(milliseconds: 150);

  /// A card taking or losing its amber edge and glow.
  static const select = Duration(milliseconds: 200);

  /// A card played gliding onto the felt.
  static const glide = Duration(milliseconds: 350);

  /// The "Nouveau" badge popping onto a card that arrived.
  static const badgeIn = Duration(milliseconds: 200);

  /// How long a card that arrived in the hand keeps its "Nouveau" badge.
  /// Information, not motion: it stays under reduced motion, drawn still.
  static const freshCard = Duration(seconds: 2);

  /// Whether the board animates at all.
  static bool enabled(BuildContext context) =>
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// [duration], or zero when the system asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      enabled(context) ? duration : Duration.zero;
}
