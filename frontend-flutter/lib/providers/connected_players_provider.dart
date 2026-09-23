import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/json.dart';
import '../models/party.dart';
import '../models/sse_event.dart';
import '../repositories/party_repository.dart';

/// Who is online, for the app bar (`ConnectedPlayers.jsx`).
///
/// `GET /players/connected` gives the first list (at most 5) and the event
/// stream keeps it up to date: `userConnected` puts the newcomer first,
/// `userDisconnected` drops them, `userStatusChanged` moves them between
/// the lobby, a party and a game.
///
/// One for the whole signed-in session (`appProviders`), so switching
/// screens does not reload it.
class ConnectedPlayersProvider extends ChangeNotifier {
  ConnectedPlayersProvider(
    this._repository, {
    required Stream<SseEvent> events,
  }) {
    _subscription = events.listen(_onEvent);
  }

  /// The backend keeps the five most recent (`ConnectedPlayers.jsx:60`).
  static const int maxPlayers = 5;

  final PartyRepository _repository;
  late final StreamSubscription<SseEvent> _subscription;

  List<ConnectedPlayer> _players = const [];
  bool _loaded = false;
  bool _signedIn = false;
  bool _disposed = false;

  List<ConnectedPlayer> get players => _players;

  /// `false` until the first answer (or presence event): the app bar shows
  /// no count yet, rather than a "0" that would mean nobody is online.
  bool get loaded => _loaded;

  /// Called by `appProviders` on every session change: loads the list once
  /// signed in, empties it on sign-out.
  void follow(bool signedIn) {
    if (_signedIn == signedIn) return;
    _signedIn = signedIn;
    if (signedIn) {
      load();
    } else {
      _players = const [];
      _loaded = false;
      _notify();
    }
  }

  /// Reloads the list. A failure only leaves the list as it was: nothing in
  /// the app bar is worth an error message (React logs and moves on).
  Future<void> load() async {
    try {
      // The backend is meant to send five at most; hold it to that here
      // too, as `userConnected` does, so the count never depends on which
      // path filled the list.
      _players = (await _repository.connectedPlayers())
          .take(maxPlayers)
          .toList();
      _loaded = true;
    } catch (error) {
      debugPrint('Connected players not loaded: $error');
    }
    _notify();
  }

  void _onEvent(SseEvent event) {
    if (!event.isPresence) return;
    final userId = event.userId;
    if (userId == null) return;
    switch (event.type) {
      case 'userConnected':
        _players = [
          ConnectedPlayer(
            userId: userId,
            username: Json.string(event.data, 'username'),
            status: 'lobby',
            connectedAt: event.timestamp,
          ),
          ..._players.where((player) => player.userId != userId),
        ].take(maxPlayers).toList();
      case 'userDisconnected':
        _players = _players.where((player) => player.userId != userId).toList();
      case 'userStatusChanged':
        _players = [
          for (final player in _players)
            if (player.userId == userId)
              ConnectedPlayer(
                userId: player.userId,
                username: player.username,
                status: Json.string(event.data, 'status', player.status),
                partyId: event.partyId,
                connectedAt: player.connectedAt,
              )
            else
              player,
        ];
      default:
        return;
    }
    _loaded = true;
    _notify();
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
