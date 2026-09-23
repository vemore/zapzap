import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The four sections of the board on a phone, top to bottom.
enum PhoneBoardSlot { players, felt, hand, actions }

/// How the board shares a phone's height between its sections.
///
/// Each section but the moves is a scroll view laid out with a loose height:
/// it takes what its content needs, up to the height it is given, and
/// scrolls past that. The moves take what they need, against the bottom.
/// The players get up to 3/11 of what is left, the hand up to 4/11, and the
/// felt everything the other two do not use — a `Column` of `Flexible`s
/// would leave that unused share as an empty band and cut the felt.
///
/// While this player draws ([feltFirst]) the felt is served before the
/// hand: the draw is played on the felt, and the hand, which cannot be
/// played then, keeps at least [handFloor] of the height and scrolls.
/// Whatever the sections leave lies between the felt and the hand.
class PhoneBoardLayout extends MultiChildLayoutDelegate {
  PhoneBoardLayout({required this.feltFirst});

  final bool feltFirst;

  /// The space between two sections.
  static const gap = 6.0;

  /// The players' and the hand's largest shares of the height.
  static const playersShare = 3 / 11;
  static const handShare = 4 / 11;

  /// The least of the height the hand keeps while the felt is served first.
  static const handFloor = 0.2;

  @override
  void performLayout(Size size) {
    final width = size.width;
    BoxConstraints upTo(double height) =>
        BoxConstraints(minWidth: width, maxWidth: width, maxHeight: height);

    final actions = layoutChild(
      PhoneBoardSlot.actions,
      upTo(size.height),
    ).height;
    final space = math.max(0.0, size.height - actions - 3 * gap);

    final players = layoutChild(
      PhoneBoardSlot.players,
      upTo(space * playersShare),
    ).height;
    final double felt;
    final double hand;
    if (feltFirst) {
      final handKeeps = math.min(space * handShare, space * handFloor);
      felt = layoutChild(
        PhoneBoardSlot.felt,
        upTo(math.max(0, space - players - handKeeps)),
      ).height;
      hand = layoutChild(
        PhoneBoardSlot.hand,
        upTo(math.max(0, math.min(space * handShare, space - players - felt))),
      ).height;
    } else {
      hand = layoutChild(PhoneBoardSlot.hand, upTo(space * handShare)).height;
      felt = layoutChild(
        PhoneBoardSlot.felt,
        upTo(math.max(0, space - players - hand)),
      ).height;
    }

    positionChild(PhoneBoardSlot.players, Offset.zero);
    positionChild(PhoneBoardSlot.felt, Offset(0, players + gap));
    positionChild(
      PhoneBoardSlot.hand,
      Offset(0, size.height - actions - gap - hand),
    );
    positionChild(PhoneBoardSlot.actions, Offset(0, size.height - actions));
  }

  @override
  bool shouldRelayout(PhoneBoardLayout oldDelegate) =>
      oldDelegate.feltFirst != feltFirst;
}
