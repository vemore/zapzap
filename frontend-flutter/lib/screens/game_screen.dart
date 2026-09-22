import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/game_state.dart';
import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../providers/sse_provider.dart';
import '../repositories/game_repository.dart';
import '../router.dart';
import '../utils/app_theme.dart';
import '../widgets/game_action_buttons.dart';
import '../widgets/game_error_text.dart';
import '../widgets/game_hand.dart';
import '../widgets/game_hand_size_selector.dart';
import '../widgets/game_player_table.dart';
import '../widgets/game_table_area.dart';
import '../widgets/zapzap_app_bar.dart';

/// The board (`frontend/src/components/Game/GameBoard.jsx`): the players,
/// the felt, this player's hand and the moves, driven by the event stream.
///
/// Three modes, from `gameState.currentAction`: the starting player picks
/// the hand size, the round is played, the round is over. A refused move
/// shows its reason in a snack bar and the board stays — the React board
/// replaces itself with an error page instead.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.partyId});

  final String partyId;

  /// Below this width the board is a single column that fills the height;
  /// above it, the players sit beside the felt.
  static const wideBreakpoint = 800.0;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameProvider _game;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _game = GameProvider(
      context.read<GameRepository>(),
      partyId: widget.partyId,
      events: context.read<SseProvider>().events,
      currentUserId: context.read<AuthProvider>().user?.id,
    );
    _game.addListener(_onChanged);
    _game.load();
  }

  @override
  void dispose() {
    _game.removeListener(_onChanged);
    _game.dispose();
    super.dispose();
  }

  /// A refused move is shown once, as a snack bar over the board; the party
  /// being deleted is the one thing that leaves the screen.
  void _onChanged() {
    if (!mounted) return;
    final error = _game.consumeActionError();
    if (error != null) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            key: const Key('gameActionError'),
            content: Text(gameErrorText(l10n, error)),
            backgroundColor: AppColors.error,
          ),
        );
    }
    if (_game.outcome == GameOutcome.closed && !_left) {
      _left = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.parties);
      });
    }
  }

  String _nameOf(int playerIndex) =>
      _game.nameOf(playerIndex) ??
      AppLocalizations.of(context).gamePlayerFallback(playerIndex + 1);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _game,
      builder: (context, _) => Scaffold(
        appBar: ZapZapAppBar(
          title: _game.snapshot?.party.name ?? l10n.gameTitle,
          leading: IconButton(
            key: const Key('back-to-lobby'),
            tooltip: l10n.gameBackToLobby,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(AppRoutes.partyPath(widget.partyId)),
          ),
        ),
        body: SafeArea(child: _body(context, l10n)),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (_game.loading) {
      return Center(
        child: CircularProgressIndicator(semanticsLabel: l10n.gameLoading),
      );
    }
    if (_game.error != null) {
      return _message(
        context,
        Icons.error_outline,
        l10n.gameLoadFailedTitle,
        gameErrorText(l10n, _game.error!),
        onRetry: _game.load,
      );
    }
    if (!_game.isStarted) {
      return _message(
        context,
        Icons.hourglass_empty,
        l10n.gameNotStartedTitle,
        l10n.gameNotStartedBody,
      );
    }
    return switch (_game.currentAction) {
      GameAction.selectHandSize => _handSize(l10n),
      GameAction.finished => _roundOver(context, l10n),
      _ => LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= GameScreen.wideBreakpoint
            ? _wideBoard()
            : _phoneBoard(),
      ),
    };
  }

  Widget _message(
    BuildContext context,
    IconData icon,
    String title,
    String body, {
    VoidCallback? onRetry,
  }) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(body, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (onRetry != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton(
                  key: const Key('retry-game'),
                  onPressed: onRetry,
                  child: Text(l10n.retryButton),
                ),
              ),
            OutlinedButton(
              key: const Key('back-to-lobby-body'),
              onPressed: () => context.go(AppRoutes.partyPath(widget.partyId)),
              child: Text(l10n.gameBackToLobby),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handSize(AppLocalizations l10n) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.gameRoundLabel(_game.round?.roundNumber ?? 1)),
            const SizedBox(height: 12),
            GameHandSizeSelector(
              isMyTurn: _game.isMyTurn,
              currentPlayerName: _nameOf(_game.currentTurn),
              maxSize: _game.handSizeMax,
              initialSize: _game.defaultHandSize,
              isGoldenScore: _game.isGoldenScore,
              busy: _game.busy,
              onSelect: _game.selectHandSize,
            ),
          ],
        ),
      ),
    ),
  );

  List<GameSeat> _seats() => [
    for (final player in _game.orderedPlayers)
      GameSeat(
        playerIndex: player.playerIndex,
        name: player.username,
        score: _game.scoreOf(player.playerIndex),
        cardCount: _game.cardCountOf(player.playerIndex),
        isMe: player.playerIndex == _game.myPlayerIndex,
        isCurrentTurn:
            player.playerIndex == _game.currentTurn &&
            !_game.isEliminated(player.playerIndex),
        isEliminated: _game.isEliminated(player.playerIndex),
      ),
  ];

  Widget _playerTable() => GamePlayerTable(seats: _seats());

  Widget _tableArea({double cardWidth = 45}) => GameTableArea(
    cardsPlayed: _game.cardsPlayed,
    lastCardsPlayed: _game.lastCardsPlayed,
    lastAction: _game.lastAction,
    playerName: _nameOf,
    cardWidth: cardWidth,
    selectedDiscardCard: _game.selectedDiscardCard,
    onDiscardTap: _game.canSelectDiscard ? _game.selectDiscardCard : null,
  );

  Widget _hand() {
    final values = _game.handValues;
    return GameHand(
      cards: _game.myHand,
      selectedCards: _game.selectedCards,
      eligibilityValue: values.eligibility,
      penaltyValue: values.penalty,
      zapZapEligible: _game.zapZapEligible,
      deckSize: _game.deckSize,
      disabled: !_game.isMyTurn || _game.currentAction != GameAction.play,
      onCardTap: _game.toggleCard,
      onClearSelection: _game.clearSelection,
      onDrawFromDeck: _game.canDraw && !_game.willTakeFromDiscard
          ? _game.draw
          : null,
    );
  }

  Widget _actions() => GameActionButtons(
    isMyTurn: _game.isMyTurn,
    currentAction: _game.currentAction,
    currentPlayerName: _nameOf(_game.currentTurn),
    selectedCount: _game.selectedCards.length,
    invalidPlay: _game.invalidPlay,
    takeFromDiscard: _game.willTakeFromDiscard,
    onPlay: _game.canPlay ? _game.play : null,
    onDraw: _game.canDraw ? _game.draw : null,
    onZapZap: _game.canZapZap ? _game.zapZap : null,
  );

  /// A phone: one column that fills the height. Each section is `Flexible`
  /// over its own scroll view, so a large system font shrinks a section
  /// rather than overflowing the column.
  Widget _phoneBoard() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // A section that needs less than its share leaves the slack behind;
      // spreading it keeps the moves against the bottom of the screen.
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(flex: 3, child: _scroll(_playerTable())),
        const SizedBox(height: 6),
        Expanded(flex: 4, child: _scroll(_tableArea())),
        const SizedBox(height: 6),
        Flexible(flex: 4, child: _scroll(_hand())),
        const SizedBox(height: 6),
        _actions(),
      ],
    ),
  );

  /// A wide screen: the players beside the felt, the hand and the moves
  /// under them.
  Widget _wideBoard() => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 320, child: _scroll(_playerTable())),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _scroll(_tableArea(cardWidth: 60))),
              const SizedBox(height: 12),
              Flexible(child: _scroll(_hand())),
              const SizedBox(height: 12),
              _actions(),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _scroll(Widget child) => SingleChildScrollView(
    child: Align(alignment: Alignment.topCenter, child: child),
  );

  // ---------------------------------------------------------------------
  // The end of a round, deliberately minimal: the scores, who called and
  // the way on. The round-end pull request replaces `_roundOver` with the
  // real screen (every hand revealed, the animation, the end of the game);
  // everything it needs is already in `GameState` — `allHands`,
  // `handPoints`, `roundScores`, `zapZapCaller`, `lowestHandPlayerIndex`,
  // `wasCounterActed`, `counterActedByPlayerIndex`, `winner` — and
  // `GameProvider.nextRound` is the button it keeps.
  // ---------------------------------------------------------------------
  Widget _roundOver(BuildContext context, AppLocalizations l10n) {
    final state = _game.game!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            key: const Key('roundOver'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _game.isGameFinished
                    ? l10n.gameOverTitle
                    : l10n.gameRoundOverTitle,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (state.zapZapCaller != null)
                Text(
                  l10n.gameRoundOverCaller(_nameOf(state.zapZapCaller!)),
                  textAlign: TextAlign.center,
                ),
              if (state.wasCounterActed)
                Text(
                  l10n.gameRoundOverCounteracted(
                    _nameOf(
                      state.counterActedByPlayerIndex ??
                          state.lowestHandPlayerIndex ??
                          0,
                    ),
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              if (_game.isGameFinished && state.winner != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.gameOverWinner(
                      state.winner!.username ??
                          _nameOf(state.winner!.playerIndex),
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.amber400,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              for (final player in _game.orderedPlayers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          player.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Scaled down rather than wrapped: the two scores stay
                      // on the name's line at any text size.
                      Expanded(
                        flex: 4,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.gameRoundScoreLabel(
                                  state.roundScores?[player.playerIndex] ?? 0,
                                ),
                                style: const TextStyle(
                                  color: AppColors.slate400,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                l10n.gameTotalScoreLabel(
                                  _game.scoreOf(player.playerIndex),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              if (_game.isGameFinished)
                OutlinedButton(
                  key: const Key('back-to-parties'),
                  onPressed: () => context.go(AppRoutes.parties),
                  child: Text(l10n.lobbyBack),
                )
              else
                FilledButton(
                  key: const Key('next-round'),
                  onPressed: _game.busy ? null : _game.nextRound,
                  child: Text(l10n.gameNextRoundButton),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
