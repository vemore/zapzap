import 'package:flutter/foundation.dart';

import '../repositories/party_repository.dart';
import 'party_provider.dart';

/// The create-party form: the number of seats, the visibility, and the one
/// `POST /party` it ends with. The creator takes the first seat; the others
/// are free, for players who join or for bots the host adds in the lobby —
/// the form asks no human or bot per seat.
class CreatePartyProvider extends ChangeNotifier {
  CreatePartyProvider(this._repository);

  final PartyRepository _repository;

  int _playerCount = defaultPartyPlayers;
  String _visibility = 'public';
  bool _busy = false;
  Object? _error;
  bool _disposed = false;

  /// The seats of the party, 3 to 8 (`settings.playerCount`).
  int get playerCount => _playerCount;

  /// `public` or `private`.
  String get visibility => _visibility;

  bool get busy => _busy;
  Object? get error => _error;

  /// Sets the number of seats, clamped to 3-8.
  void setPlayerCount(int count) {
    final clamped = count.clamp(minPartyPlayers, maxPartyPlayers);
    if (clamped == _playerCount) return;
    _playerCount = clamped;
    _notify();
  }

  void setVisibility(String visibility) {
    if (_visibility == visibility) return;
    _visibility = visibility;
    _notify();
  }

  /// `POST /party` with [name] and the seats. Returns the new party's id, or
  /// `null` when the call failed ([error] says why).
  Future<String?> submit(String name) async {
    if (_busy) return null;
    _busy = true;
    _error = null;
    _notify();
    String? partyId;
    try {
      final result = await _repository.create(
        name: name.trim(),
        playerCount: _playerCount,
        visibility: _visibility,
      );
      partyId = result.party.id;
    } catch (error) {
      _error = error;
    }
    _busy = false;
    _notify();
    return partyId;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
