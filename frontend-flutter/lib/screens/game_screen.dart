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
import '../utils/rules.dart';
import '../widgets/game_action_buttons.dart';
import '../widgets/game_error_text.dart';
import '../widgets/game_hand.dart';
import '../widgets/game_hand_size_selector.dart';
import '../widgets/game_player_table.dart';
import '../widgets/game_round_end.dart';
import '../widgets/game_table_area.dart';
import '../widgets/game_zapzap_sheet.dart';
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
          // Not the lobby: a party that is playing bounces straight back
          // here (`party_provider.dart`, `PartyLobbyProvider.load`), which
          // remounts the whole board and leaves no way out.
          leading: IconButton(
            key: const Key('game-back'),
            tooltip: l10n.lobbyBack,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(AppRoutes.parties),
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
        // `partyStarted` refetches on its own; the button covers an event
        // this client missed while its channel was down.
        onRetry: _game.load,
      );
    }
    final content = switch (_game.currentAction) {
      GameAction.selectHandSize => _handSize(l10n),
      GameAction.finished => _roundOver(context, l10n),
      _ => LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= GameScreen.wideBreakpoint
            ? _wideBoard()
            : _phoneBoard(),
      ),
    };
    if (_game.refreshError == null) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _staleBanner(l10n),
        Expanded(child: content),
      ],
    );
  }

  /// The last refresh failed but the table is still drawn: say it may be
  /// out of date rather than take it away, and offer another go.
  Widget _staleBanner(AppLocalizations l10n) => Container(
    key: const Key('gameStaleBanner'),
    padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
    color: AppColors.amber600.withValues(alpha: 0.25),
    child: Row(
      children: [
        const Icon(Icons.sync_problem, size: 16, color: AppColors.amber400),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l10n.gameRefreshFailed,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        TextButton(
          key: const Key('retry-refresh'),
          onPressed: _game.busy ? null : () => _game.load(showSpinner: false),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(l10n.retryButton),
        ),
      ],
    ),
  );

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
              key: const Key('game-back-body'),
              onPressed: () => context.go(AppRoutes.parties),
              child: Text(l10n.lobbyBack),
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

  /// Where this player's turn stands, for the felt.
  TableStep get _tableStep {
    if (!_game.isMyTurn) return TableStep.waiting;
    return switch (_game.currentAction) {
      GameAction.play => TableStep.play,
      GameAction.draw => TableStep.draw,
      _ => TableStep.waiting,
    };
  }

  Widget _tableArea({double cardWidth = 45}) => GameTableArea(
    cardsPlayed: _game.cardsPlayed,
    lastCardsPlayed: _game.lastCardsPlayed,
    lastAction: _game.lastAction,
    playerName: _nameOf,
    cardWidth: cardWidth,
    step: _tableStep,
    deckSize: _game.deckSize,
    selectedDiscardCard: _game.selectedDiscardCard,
    takeCard: _game.willTakeFromDiscard ? _game.selectedDiscardCard : null,
    onDiscardTap: _game.canSelectDiscard ? _game.selectDiscardCard : null,
    onDeckTap: _game.canDraw ? () => _game.draw(fromDeck: true) : null,
  );

  Widget _hand() {
    final values = _game.handValues;
    return GameHand(
      cards: _game.myHand,
      selectedCards: _game.selectedCards,
      eligibilityValue: values.eligibility,
      penaltyValue: values.penalty,
      disabled: !_game.isMyTurn || _game.currentAction != GameAction.play,
      onCardTap: _game.toggleCard,
      onClearSelection: _game.hasSelection ? _game.clearSelection : null,
    );
  }

  Widget _actions() {
    final values = _game.handValues;
    return GameActionButtons(
      isMyTurn: _game.isMyTurn,
      currentAction: _game.currentAction,
      currentPlayerName: _nameOf(_game.currentTurn),
      selectedCards: _game.selectedCards,
      invalidPlay: _game.invalidPlay,
      takeCard: _game.willTakeFromDiscard ? _game.selectedDiscardCard : null,
      zapZapRisk: ZapZapRisk(
        handValue: values.eligibility,
        scoredValue: values.penalty,
        activePlayers: _game.activePlayerCount,
        eligible: _game.zapZapEligible,
        holdsJoker: hasJoker(_game.myHand),
        isGoldenScore: _game.isGoldenScore,
      ),
      onPlay: _game.canPlay ? _game.play : null,
      onDraw: _game.canDraw ? _game.draw : null,
      onZapZap: _game.canZapZap ? _game.zapZap : null,
    );
  }

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
  // The end of a round, and the end of the game: everything comes from
  // `GameState` — `allHands`, `handPoints`, `roundScores`, `zapZapCaller`,
  // `lowestHandPlayerIndex`, `wasCounterActed`, `counterActedByPlayerIndex`,
  // `gameFinished`, `winner` — never from the answer of a move, because the
  // two backends disagree on what `zapzap` returns ([[FrontendFlutter]]).
  // ---------------------------------------------------------------------

  /// What [playerIndex] scored this round, as `GameBoard.jsx:374-400`
  /// reads it: the backend's own figure, else 0 for the lowest hand and the
  /// hand's points for everybody else.
  int _roundScoreOf(GameState state, int playerIndex) =>
      state.roundScores?[playerIndex] ??
      (playerIndex == state.lowestHandPlayerIndex
          ? 0
          : state.handPoints?[playerIndex] ?? 0);

  /// The players in the order the round scored them, lowest first; ties keep
  /// turn order, which `List.sort` alone does not promise.
  List<RoundEndPlayer> _roundEndPlayers(GameState state) {
    final ordered = _game.orderedPlayers;
    final rows = [
      for (var seat = 0; seat < ordered.length; seat++)
        (
          seat: seat,
          player: () {
            final index = ordered[seat].playerIndex;
            final total = _game.scoreOf(index);
            // Both sources: Node fills `eliminatedPlayers`, and
            // `GAME_RULES.md` puts anybody above 100 points out.
            final out = _game.isEliminated(index) || total > 100;
            return RoundEndPlayer(
              playerIndex: index,
              name: ordered[seat].username,
              hand: state.allHands?[index] ?? const [],
              roundScore: _roundScoreOf(state, index),
              totalScore: total,
              isEliminated: out,
              // A player who is out does not hold the lowest hand, whatever
              // the backend says: it points at a seat with no cards left
              // once the game is over (checked locally, 2026-09-23).
              isLowestHand: !out && index == state.lowestHandPlayerIndex,
              isZapZapCaller: index == state.zapZapCaller,
              isMe: index == _game.myPlayerIndex,
            );
          }(),
        ),
    ];
    rows.sort((a, b) {
      final byScore = a.player.roundScore.compareTo(b.player.roundScore);
      return byScore != 0 ? byScore : a.seat.compareTo(b.seat);
    });
    return [for (final row in rows) row.player];
  }

  /// Who picks the hand size of the next round: the seat after this
  /// round's starting player, skipping whoever is out (`GAME_RULES.md`,
  /// "Subsequent Rounds"; `NextRound.js` rotates the same way).
  int? _nextChooser(List<RoundEndPlayer> players) {
    final seats = [for (final player in players) player.playerIndex]..sort();
    final out = {
      for (final player in players)
        if (player.isEliminated) player.playerIndex,
    };
    final from = seats.indexOf(_game.startingPlayer);
    for (var step = 1; step <= seats.length; step++) {
      final seat = seats[(from + step) % seats.length];
      if (!out.contains(seat)) return seat;
    }
    return null;
  }

  /// The hand value [playerIndex] held, a Joker counting 0: what a ZapZap
  /// is decided on.
  int? _zapZapValueOf(GameState state, int? playerIndex) {
    final hand = playerIndex == null ? null : state.allHands?[playerIndex];
    return hand == null ? null : handValue(hand);
  }

  Widget _roundOver(BuildContext context, AppLocalizations l10n) {
    final state = _game.game!;
    final players = _roundEndPlayers(state);
    final caller = state.zapZapCaller;
    final winner = state.winner;
    // Who was still in the game when the round was played: their total
    // before it was 100 or less. This is the `active_players` of the
    // counteract penalty (`GAME_RULES.md`).
    final active = players
        .where((player) => player.totalScore - player.roundScore <= 100)
        .length;
    final next = _nextChooser(players);

    return GameRoundEnd(
      roundNumber: _game.round?.roundNumber ?? 1,
      players: players,
      zapZapCallerName: caller == null ? null : _nameOf(caller),
      wasCounterActed: state.wasCounterActed,
      counterActedByName: state.counterActedByPlayerIndex == null
          ? null
          : _nameOf(state.counterActedByPlayerIndex!),
      callerHandValue: caller == null ? null : state.handPoints?[caller],
      callerRoundScore: caller == null ? null : _roundScoreOf(state, caller),
      activePlayerCount: active,
      callerZapZapValue: _zapZapValueOf(state, caller),
      counterActorZapZapValue: _zapZapValueOf(
        state,
        state.counterActedByPlayerIndex,
      ),
      nextChooserName: next == null ? null : _nameOf(next),
      nextChooserIsMe: next != null && next == _game.myPlayerIndex,
      gameFinished: _game.isGameFinished,
      winnerName: winner == null
          ? null
          : winner.username ?? _nameOf(winner.playerIndex),
      winnerScore: winner?.score,
      busy: _game.busy,
      onNextRound: _game.nextRound,
      onBackToParties: () => context.go(AppRoutes.parties),
    );
  }
}
