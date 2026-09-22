import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/game_state.dart';
import '../utils/app_theme.dart';
import 'playing_card.dart';

/// The felt: what just happened, the cards laid down this turn, and the
/// discard pile — tappable in the draw phase. The port of
/// `frontend/src/components/Game/TableArea.jsx`.
class GameTableArea extends StatefulWidget {
  const GameTableArea({
    super.key,
    required this.cardsPlayed,
    required this.lastCardsPlayed,
    required this.playerName,
    this.lastAction,
    this.onDiscardTap,
    this.selectedDiscardCard,
    this.cardWidth = 45,
  });

  final List<int> cardsPlayed;

  /// The previous player's cards: the discard pile.
  final List<int> lastCardsPlayed;

  /// The name of a seat, for the action message.
  final String Function(int playerIndex) playerName;

  final LastAction? lastAction;

  /// Given only when a draw is owed: the pile is dead otherwise.
  final ValueChanged<int>? onDiscardTap;
  final int? selectedDiscardCard;
  final double cardWidth;

  /// How long the "Reshuffled!" banner stays, as React
  /// (`TableArea.jsx:222`).
  static const reshuffleDuration = Duration(milliseconds: 2500);

  static Key discardKey(int cardId) => ValueKey('discardCard-$cardId');

  @override
  State<GameTableArea> createState() => _GameTableAreaState();
}

class _GameTableAreaState extends State<GameTableArea> {
  Timer? _reshuffleTimer;
  bool _showReshuffle = false;
  Object? _shownAction;

  @override
  void initState() {
    super.initState();
    _followReshuffle();
  }

  @override
  void didUpdateWidget(GameTableArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _followReshuffle();
  }

  @override
  void dispose() {
    _reshuffleTimer?.cancel();
    super.dispose();
  }

  /// A *new* draw that reshuffled the deck raises the banner for 2.5 s.
  void _followReshuffle() {
    final action = widget.lastAction;
    final stamp = action == null
        ? null
        : '${action.type}/${action.playerIndex}/${action.timestamp}';
    if (stamp == _shownAction) return;
    _shownAction = stamp;
    if (action == null || !action.deckReshuffled) return;
    _reshuffleTimer?.cancel();
    setState(() => _showReshuffle = true);
    _reshuffleTimer = Timer(GameTableArea.reshuffleDuration, () {
      if (mounted) setState(() => _showReshuffle = false);
    });
  }

  String? _message(AppLocalizations l10n) {
    final action = widget.lastAction;
    if (action == null) return null;
    final name = widget.playerName(action.playerIndex);
    return switch (action.type) {
      'play' => l10n.gameActionPlayed(
        name,
        action.cardIds.isEmpty
            ? widget.cardsPlayed.length
            : action.cardIds.length,
      ),
      'draw' when action.source == 'played' => l10n.gameActionTookDiscard(name),
      'draw' when action.deckReshuffled => l10n.gameActionDrewReshuffled(name),
      'draw' => l10n.gameActionDrewDeck(name),
      'selectHandSize' => l10n.gameActionSelectedHandSize(
        name,
        action.handSize ?? 0,
      ),
      'zapzap' => l10n.gameActionCalledZapZap(name),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = _message(l10n);
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.table, AppColors.tableLight],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.tableLight),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    message,
                    key: const Key('tableMessage'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF86EFAC),
                    ),
                  ),
                ),
              if (widget.cardsPlayed.isNotEmpty) ...[
                _label(l10n.gameTablePlayedLabel),
                _cards(
                  widget.cardsPlayed,
                  (id) => PlayingCard(
                    cardId: id,
                    width: widget.cardWidth,
                    disabled: true,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              _label(l10n.gameTableDiscardLabel(widget.lastCardsPlayed.length)),
              if (widget.lastCardsPlayed.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    l10n.gameTableEmpty,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate400,
                    ),
                  ),
                )
              else
                _cards(
                  widget.lastCardsPlayed,
                  (id) => PlayingCard(
                    key: GameTableArea.discardKey(id),
                    cardId: id,
                    width: widget.cardWidth,
                    selected: widget.selectedDiscardCard == id,
                    disabled: widget.onDiscardTap == null,
                    onTap: widget.onDiscardTap == null
                        ? null
                        : () => widget.onDiscardTap!(id),
                  ),
                ),
            ],
          ),
        ),
        if (_showReshuffle)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  key: const Key('reshuffleBanner'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.amber500,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.gameReshuffled,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.slate900,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, color: AppColors.slate400),
    ),
  );

  /// A `Wrap`, not a `Row`: a long pile folds onto a second line instead of
  /// overflowing a phone.
  Widget _cards(List<int> cards, Widget Function(int cardId) build) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 4,
    runSpacing: 4,
    children: [for (final id in cards) build(id)],
  );
}
