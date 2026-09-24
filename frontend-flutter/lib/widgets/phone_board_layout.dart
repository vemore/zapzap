import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The four sections of the board on a phone, top to bottom.
enum PhoneBoardSlot { players, felt, hand, actions }

/// How the board shares a phone's height between its sections.
///
/// The players, the hand and the moves each take what their content needs:
/// the moves against the bottom, the players up to [playersShare] of what is
/// left, the hand as much as leaves the felt [feltFloor] of it — each but
/// the moves a scroll view that scrolls past that. The felt fills everything
/// between the players and the hand, so no empty band ever lies between the
/// felt and the hand; its own content scrolls inside its edge when it needs
/// more.
///
/// While this player draws ([feltFirst]) the hand, which cannot be played
/// then, keeps at most [drawHandShare] of the height and scrolls, and the
/// felt, where the draw is played, gets the rest. The hand is then one row
/// of small cards (`GameHand.compact`), which that share holds whole at
/// 360x740: #64's two rows of big cards showed only a strip of rank.
class PhoneBoardLayout extends MultiChildLayoutDelegate {
  PhoneBoardLayout({required this.feltFirst});

  final bool feltFirst;

  /// The space between two sections.
  static const gap = 6.0;

  /// The players' largest share of the height.
  static const playersShare = 3 / 11;

  /// The least share of the height the hand leaves the felt.
  static const feltFloor = 0.2;

  /// The hand's largest share while the felt is served first.
  static const drawHandShare = 0.2;

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
    final hand = layoutChild(
      PhoneBoardSlot.hand,
      upTo(
        feltFirst
            ? space * drawHandShare
            : math.max(0, space * (1 - feltFloor) - players),
      ),
    ).height;
    final felt = math.max(0.0, space - players - hand);
    layoutChild(
      PhoneBoardSlot.felt,
      BoxConstraints.tightFor(width: width, height: felt),
    );

    positionChild(PhoneBoardSlot.players, Offset.zero);
    positionChild(PhoneBoardSlot.felt, Offset(0, players + gap));
    positionChild(PhoneBoardSlot.hand, Offset(0, players + felt + 2 * gap));
    positionChild(PhoneBoardSlot.actions, Offset(0, size.height - actions));
  }

  @override
  bool shouldRelayout(PhoneBoardLayout oldDelegate) =>
      oldDelegate.feltFirst != feltFirst;
}
