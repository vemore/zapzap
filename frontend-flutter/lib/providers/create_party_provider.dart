import 'package:flutter/foundation.dart';

import '../models/bot.dart';
import '../repositories/party_repository.dart';
import 'party_provider.dart';

/// The bot difficulties a party can seat, in the order the selector shows
/// them — the ones the React client offers (`CreateParty.jsx:252-269`).
/// `ml` and `drl` exist in the backend but are not offered here.
const List<String> botDifficulties = [
  'easy',
  'medium',
  'hard',
  'hard_vince',
  'llm',
  'thibot',
];

/// One seat of the party being created, other than the creator's own.
@immutable
class PlayerSlot {
  const PlayerSlot({this.difficulty, this.botId});

  /// An open seat, waiting for a human.
  static const human = PlayerSlot();

  /// The bot difficulty asked for, `null` for a human seat.
  final String? difficulty;

  /// The bot account that will fill the seat, `null` for a human seat.
  final String? botId;

  bool get isBot => botId != null;
}

/// The create-party form: the seats, the bots that can fill them, and the
/// one `POST /party` it ends with (`CreateParty.jsx`).
///
/// A bot account can only sit once at a table, so choosing a difficulty for
/// a seat takes the **first bot of that difficulty no other seat holds**;
/// when there is none left the seat stays human, exactly as React does
/// (`CreateParty.jsx:47-74`).
class CreatePartyProvider extends ChangeNotifier {
  CreatePartyProvider(this._repository);

  final PartyRepository _repository;

  List<Bot> _bots = const [];
  int _playerCount = defaultPartyPlayers;
  String _visibility = 'public';
  List<PlayerSlot> _slots = List.filled(
    defaultPartyPlayers - 1,
    PlayerSlot.human,
  );
  bool _busy = false;
  Object? _error;
  bool _disposed = false;

  /// Every bot account the backend offers; empty when `GET /bots` failed,
  /// which only means no bot can be seated (React ignores it too).
  List<Bot> get bots => _bots;

  /// The seats of the party, 3 to 8 (`settings.playerCount`).
  int get playerCount => _playerCount;

  /// `public` or `private`.
  String get visibility => _visibility;

  /// The configurable seats: every one but the creator's, which is seat 0
  /// and always human.
  List<PlayerSlot> get slots => List.unmodifiable(_slots);

  bool get busy => _busy;
  Object? get error => _error;

  int get botCount => _slots.where((slot) => slot.isBot).length;

  /// The creator included.
  int get humanCount => _playerCount - botCount;

  /// Loads the bot accounts. A failure is swallowed: the form still works,
  /// without bots.
  Future<void> loadBots() async {
    try {
      _bots = await _repository.bots();
    } catch (error) {
      _bots = const [];
      debugPrint('Bots not loaded: $error');
    }
    _notify();
  }

  /// Sets the number of seats (clamped to 3-8). The seats already
  /// configured are kept; new ones start human.
  void setPlayerCount(int count) {
    final clamped = count.clamp(minPartyPlayers, maxPartyPlayers);
    if (clamped == _playerCount) return;
    _playerCount = clamped;
    final slots = List<PlayerSlot>.from(_slots);
    if (slots.length > clamped - 1) {
      slots.removeRange(clamped - 1, slots.length);
    } else {
      slots.addAll(List.filled(clamped - 1 - slots.length, PlayerSlot.human));
    }
    _slots = slots;
    _notify();
  }

  void setVisibility(String visibility) {
    if (_visibility == visibility) return;
    _visibility = visibility;
    _notify();
  }

  /// Frees seat [index]'s bot, if it had one.
  void setSlotHuman(int index) {
    if (!_slots[index].isBot) return;
    _slots = [..._slots]..[index] = PlayerSlot.human;
    _notify();
  }

  /// Seats the first free bot of [difficulty] at [index]; with none free
  /// the seat stays (or becomes) human.
  void setSlotBot(int index, String difficulty) {
    final taken = _takenBotIds(exceptSlot: index);
    Bot? free;
    for (final bot in _bots) {
      if (bot.difficulty == difficulty && !taken.contains(bot.id)) {
        free = bot;
        break;
      }
    }
    _slots = [..._slots]
      ..[index] = free == null
          ? PlayerSlot.human
          : PlayerSlot(difficulty: difficulty, botId: free.id);
    _notify();
  }

  /// How many bots of [difficulty] seat [index] could take — its own bot
  /// included, so the option it already shows never looks unavailable.
  int availableBots(int index, String difficulty) {
    final taken = _takenBotIds(exceptSlot: index);
    return _bots
        .where((bot) => bot.difficulty == difficulty && !taken.contains(bot.id))
        .length;
  }

  Set<String> _takenBotIds({required int exceptSlot}) => {
    for (var i = 0; i < _slots.length; i++)
      if (i != exceptSlot && _slots[i].botId != null) _slots[i].botId!,
  };

  /// `POST /party` with [name] and the configured seats. Returns the new
  /// party's id, or `null` when the call failed ([error] says why).
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
        botIds: [
          for (final slot in _slots)
            if (slot.botId != null) slot.botId!,
        ],
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
