import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/bot.dart';
import '../models/party.dart';
import '../models/sse_event.dart';
import '../repositories/party_repository.dart';
import '../services/api_exception.dart';

export '../models/party.dart' show defaultPartyPlayers;

/// The party error codes the lobby reacts to, on top of [ApiErrorCode].
abstract final class PartyErrorCode {
  /// `POST /party/:id/join` when the caller already has a seat: React opens
  /// the lobby anyway (`PartyList.jsx:37-39`), and so does this client.
  static const alreadyInParty = 'ALREADY_IN_PARTY';
  static const partyStarted = 'PARTY_STARTED';
  static const partyAlreadyPlaying = 'PARTY_ALREADY_PLAYING';
  static const partyPlaying = 'PARTY_PLAYING';
  static const notOwner = 'NOT_OWNER';
  static const notAuthorized = 'NOT_AUTHORIZED';

  /// Leave (and start, on Rust) by someone without a seat: another client
  /// already took them out.
  static const notInParty = 'NOT_IN_PARTY';

  /// `POST /party/:id/fill-and-start` found fewer free bots than free seats:
  /// nothing was seated.
  static const notEnoughBots = 'NOT_ENOUGH_BOTS';
}

/// A rummy hand is dealt to 3 players at least and 8 at most
/// (`GAME_RULES.md`); the backend refuses anything else.
const int minPartyPlayers = 3;
const int maxPartyPlayers = 8;

/// A party name is 3 to 50 characters once trimmed, as the backend requires.
const int partyNameMinLength = 3;
const int partyNameMaxLength = 50;

/// The public party list (`GET /party`), what the parties screen shows.
///
/// The event stream keeps it current: a party created, filled, emptied,
/// started, finished or deleted by someone else reloads the list without a
/// spinner, [refreshDelay] after the last such event, so a burst of bot
/// joins is one `GET /party`; so does a move that passes the turn in a game
/// of mine ([turnActions]), which may make it my turn. React has no stream
/// there and waits for a reload.
class PartyListProvider extends ChangeNotifier {
  PartyListProvider(
    this._repository, {
    Stream<SseEvent>? events,
    this.refreshDelay = const Duration(seconds: 1),
  }) {
    _subscription = events?.listen(_onEvent);
  }

  final PartyRepository _repository;

  /// How long the list waits after an event, for the next one of a burst.
  final Duration refreshDelay;

  /// The actions that change a row: its seats, its status, or its being
  /// there at all. `playerReplaced` (the turn clock) and `playerForfeited`
  /// (an account deleted mid-game) give a human's seat to a bot: the row's
  /// `isMember` changes for that human, whose list is still in memory when
  /// the game screen pops back to it.
  static const refreshingActions = {
    'partyCreated',
    'playerJoined',
    'playerLeft',
    'playerReplaced',
    'playerForfeited',
    'partyStarted',
    'partyDeleted',
    'gameFinished',
  };

  /// The moves after which the turn may be someone else's: a draw ends a
  /// turn, a zapzap ends the round — and, the game's last, the game: the
  /// backend sends no `gameFinished` then —, and a new round starts on any
  /// seat. They reload the list only for a running game of mine, the row
  /// whose [PartySummary.isMyTurn] they may change; other moves, and moves
  /// of anyone else's game, reload nothing.
  static const turnActions = {'draw', 'zapzap', 'roundStarted'};

  StreamSubscription<SseEvent>? _subscription;
  Timer? _refresh;

  List<PartySummary> _parties = const [];
  bool _loading = true;
  Object? _error;
  bool _disposed = false;

  /// The newest [load]; an answer to an older one is dropped.
  int _loadGeneration = 0;

  List<PartySummary> get parties => _parties;

  /// The parties the caller is in, the "My games" section: a game waiting
  /// for the caller's move first ([PartySummary.isMyTurn]), then the other
  /// running games, then the lobbies, then the finished ones, each in the
  /// backend's order.
  List<PartySummary> get myParties {
    int rank(PartySummary party) => switch (party.status) {
      PartyStatus.playing when party.isMyTurn => 0,
      PartyStatus.playing => 1,
      PartyStatus.finished => 3,
      _ => 2,
    };
    final mine = _parties.where((party) => party.isMember).toList();
    // `List.sort` is not stable: sort on (rank, index).
    final index = {for (final (i, party) in mine.indexed) party.id: i};
    return mine..sort(
      (a, b) =>
          rank(a) != rank(b) ? rank(a) - rank(b) : index[a.id]! - index[b.id]!,
    );
  }

  /// The parties the caller is not in, the "Open games" section, in the
  /// backend's order.
  List<PartySummary> get openParties =>
      _parties.where((party) => !party.isMember).toList();

  /// `true` until the first answer, and again while a spinner-showing load
  /// runs; a pull-to-refresh does not set it.
  bool get loading => _loading;

  /// The last failure, for the screen to turn into a message; `null` once a
  /// load or an action succeeded.
  Object? get error => _error;

  /// Reloads the list. [showSpinner] false is the pull-to-refresh or an
  /// event, which keeps the current rows meanwhile.
  ///
  /// A pull and an event, or two events a debounce apart, can answer out of
  /// order: only the newest load is kept ([_loadGeneration], as in
  /// [PartyLobbyProvider.load]); an older answer, good or bad, is dropped.
  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner && !_loading) {
      _loading = true;
      _notify();
    }
    final generation = ++_loadGeneration;
    try {
      final parties = (await _repository.list()).items;
      if (generation != _loadGeneration) return;
      _parties = parties;
      _error = null;
    } catch (error) {
      if (generation != _loadGeneration) return;
      _error = error;
    }
    _loading = false;
    _notify();
  }

  void _onEvent(SseEvent event) {
    if (_disposed) return;
    final action = event.action;
    final refreshes =
        refreshingActions.contains(action) ||
        (turnActions.contains(action) && _isMyRunningGame(event.partyId));
    if (!refreshes) return;
    _refresh?.cancel();
    _refresh = Timer(refreshDelay, () => load(showSpinner: false));
  }

  bool _isMyRunningGame(String? partyId) => _parties.any(
    (party) =>
        party.id == partyId &&
        party.isMember &&
        party.status == PartyStatus.playing,
  );

  /// Joins [partyId]. `true` when its lobby may be opened — a seat was
  /// taken, or the caller already had one; `false` leaves the refusal in
  /// [error].
  Future<bool> join(String partyId) async {
    try {
      await _repository.join(partyId);
      _error = null;
      _notify();
      return true;
    } catch (error) {
      if (error is ApiException &&
          error.code == PartyErrorCode.alreadyInParty) {
        _error = null;
        _notify();
        return true;
      }
      _error = error;
      _notify();
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refresh?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}

/// What ends the lobby: the screen watches [PartyLobbyProvider.outcome] and
/// navigates.
enum LobbyOutcome {
  /// The game started (this client or another): go to the game.
  started,

  /// The party was deleted, or this client left it: go back to the list.
  closed,
}

/// One party's lobby (`GET /party/:id`), refreshed by the event stream.
///
/// Every client gets every broadcast, so events are kept only when their
/// `partyId` is this party's: `playerJoined` and `playerLeft` reload the
/// seats, `partyStarted` and `partyDeleted` set [outcome] and the screen
/// navigates (`PartyLobby.jsx:21-37`).
///
/// The host fills free seats with bots: one at a time ([addBot], the first
/// bot of a difficulty not seated yet), or all at once as the party starts
/// ([fillAndStart]). Only when asked: nothing fills or starts by itself.
class PartyLobbyProvider extends ChangeNotifier {
  PartyLobbyProvider(
    this._repository, {
    required this.partyId,
    required Stream<SseEvent> events,
    this.currentUserId,
  }) {
    _subscription = events.listen(_onEvent);
  }

  final String partyId;
  final PartyRepository _repository;

  /// Who is signed in: the "only human" rule compares it with the seats.
  final String? currentUserId;

  late final StreamSubscription<SseEvent> _subscription;

  PartyDetails? _details;
  List<Bot> _bots = const [];
  bool _loading = true;
  Object? _error;
  LobbyOutcome? _outcome;
  bool _busy = false;
  bool _disposed = false;

  /// The newest [load]; an answer to an older one is dropped.
  int _loadGeneration = 0;

  PartyDetails? get details => _details;
  bool get loading => _loading;
  Object? get error => _error;

  /// Set once: the screen navigates away and stops listening.
  LobbyOutcome? get outcome => _outcome;

  /// An action (start, leave, delete) is running: the buttons are disabled.
  bool get busy => _busy;

  List<PartyPlayer> get players => _details?.players ?? const [];
  int get playerCount => players.length;

  /// Every bot account the backend offers (`GET /bots`, [loadBots]); empty
  /// when it failed, which only means no bot can be added one by one.
  List<Bot> get bots => _bots;

  int get maxPlayers =>
      _details?.party.settings.playerCount ?? defaultPartyPlayers;

  /// The caller owns the party: `isOwner` of `GET /party/:id`.
  bool get isOwner => _details?.isOwner ?? false;

  /// The caller is the only human at the table (every other seat is a bot):
  /// they may delete the party even without owning it
  /// (`PartyLobby.jsx:140-144`).
  bool get isOnlyHuman {
    final humans = players.where((player) => !player.isBot).toList();
    return humans.length == 1 &&
        currentUserId != null &&
        humans.single.userId == currentUserId;
  }

  bool get canStart =>
      isOwner && playerCount >= minPartyPlayers && !_busy && _details != null;

  bool get canDelete => _details != null && (isOwner || isOnlyHuman);

  /// Seats nobody holds yet.
  int get freeSeats {
    final free = maxPlayers - playerCount;
    return free > 0 ? free : 0;
  }

  /// The host may seat bots: in a waiting party with a free seat.
  bool get canAddBots =>
      isOwner && _details?.party.status == PartyStatus.waiting && freeSeats > 0;

  /// How many bots of [difficulty] are not seated at this table.
  int availableBots(String difficulty) {
    final seated = {for (final player in players) player.userId};
    return _bots
        .where(
          (bot) => bot.difficulty == difficulty && !seated.contains(bot.id),
        )
        .length;
  }

  /// How many players are still missing before the game can start, 0 once
  /// there are enough.
  int get missingPlayers {
    final missing = minPartyPlayers - playerCount;
    return missing > 0 ? missing : 0;
  }

  /// (Re)loads the party. [showSpinner] false is a refresh driven by an
  /// event or by a pull: the current seats stay on screen meanwhile.
  ///
  /// Two players joining a moment apart start two loads, which can answer
  /// out of order. Only the newest one is kept ([_loadGeneration], as in
  /// `GameProvider.load`); an older answer, good or bad, is dropped.
  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner && !_loading) {
      _loading = true;
      _notify();
    }
    final generation = ++_loadGeneration;
    try {
      final details = await _repository.details(partyId);
      if (generation != _loadGeneration) return;
      _details = details;
      _error = null;
      // The game may have started while this client was away, or between
      // the event and the answer.
      if (details.party.status == PartyStatus.playing) {
        _outcome = LobbyOutcome.started;
      }
    } catch (error) {
      if (generation != _loadGeneration) return;
      if (error is ApiException && error.code == ApiErrorCode.partyNotFound) {
        _details = null;
      }
      _error = error;
    }
    _loading = false;
    _notify();
  }

  /// Loads the bot accounts [addBot] picks from. A failure is swallowed.
  Future<void> loadBots() async {
    try {
      _bots = await _repository.bots();
    } catch (error) {
      _bots = const [];
      debugPrint('Bots not loaded: $error');
    }
    _notify();
  }

  /// Owner only: seats the first bot of [difficulty] not at the table yet on
  /// the lowest free seat, then shows it without waiting for the event.
  Future<void> addBot(String difficulty) => _act(() async {
    final seated = {for (final player in players) player.userId};
    final bot = _bots
        .where(
          (bot) => bot.difficulty == difficulty && !seated.contains(bot.id),
        )
        .firstOrNull;
    if (bot == null) return;
    await _repository.addBot(partyId, bot.id);
    await load(showSpinner: false);
  });

  /// Owner only: every free seat gets a bot of [difficulty] (one of
  /// [fillDifficulties]; the backend takes the next levels when it runs
  /// out), then the party starts — one call, so a refusal seats nobody.
  Future<void> fillAndStart(String difficulty) => _act(() async {
    await _repository.fillAndStart(partyId, difficulty);
    _outcome = LobbyOutcome.started;
  });

  /// Owner only, 3 players at least. The event stream tells the others.
  Future<void> start() => _act(() async {
    await _repository.start(partyId);
    _outcome = LobbyOutcome.started;
  });

  Future<void> leave() => _act(() async {
    await _repository.leave(partyId);
    _outcome = LobbyOutcome.closed;
  });

  Future<void> delete() => _act(() async {
    await _repository.delete(partyId);
    _outcome = LobbyOutcome.closed;
  });

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      await action();
    } catch (error) {
      _error = error;
    }
    _busy = false;
    _notify();
  }

  void _onEvent(SseEvent event) {
    if (event.partyId != partyId || _outcome != null) return;
    switch (event.action) {
      case 'playerJoined':
      case 'playerLeft':
        load(showSpinner: false);
      case 'partyStarted':
        _outcome = LobbyOutcome.started;
        _notify();
      case 'partyDeleted':
        _outcome = LobbyOutcome.closed;
        _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}
