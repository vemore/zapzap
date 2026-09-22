import 'dart:convert';

/// A decoded JSON object.
typedef JsonMap = Map<String, dynamic>;

/// Lenient readers for the JSON the two backends send.
///
/// The Node backend (production) and the Rust backend (the target) agree on
/// field names but not always on types: an id is an integer on one side and a
/// string on the other, a timestamp is Unix seconds, Unix milliseconds or an
/// RFC 3339 string, a hand is a list or a JSON-encoded string. Every model
/// reads through these helpers so it parses both.
abstract final class Json {
  /// The object at [key], or `null` when missing or not an object.
  static JsonMap? map(JsonMap json, String key) {
    final value = json[key];
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  /// The list of objects at [key], each parsed by [parse]; empty when missing.
  static List<T> list<T>(JsonMap json, String key, T Function(JsonMap) parse) {
    final value = json[key];
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map) parse(item.cast<String, dynamic>()),
    ];
  }

  static String string(JsonMap json, String key, [String fallback = '']) =>
      stringOrNull(json, key) ?? fallback;

  /// A string, also accepting a number (Rust sends some ids as strings,
  /// Node as integers).
  static String? stringOrNull(JsonMap json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }

  static int integer(JsonMap json, String key, [int fallback = 0]) =>
      intOrNull(json[key]) ?? fallback;

  /// An integer from a number or a numeric string.
  static int? intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double number(JsonMap json, String key, [double fallback = 0]) {
    final value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool boolean(JsonMap json, String key, [bool fallback = false]) {
    final value = json[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    return fallback;
  }

  static bool? boolOrNull(JsonMap json, String key) {
    final value = json[key];
    return value is bool ? value : null;
  }

  /// A list of integers (card ids, player indexes). Also accepts a
  /// JSON-encoded string (`"[17,28,1]"`, the Node history's `handCards`) and
  /// a list of objects carrying `playerIndex` (the Node `nextRound`'s
  /// `eliminatedPlayers`).
  static List<int> ints(Object? value) {
    if (value is String) {
      try {
        return ints(jsonDecode(value));
      } on FormatException {
        return const [];
      }
    }
    if (value is! List) return const [];
    final result = <int>[];
    for (final item in value) {
      final number = item is Map
          ? intOrNull(item['playerIndex'])
          : intOrNull(item);
      if (number != null) result.add(number);
    }
    return result;
  }

  /// A map keyed by player index. JSON object keys are strings (`{"0": 28}`);
  /// the Rust `zapzap` and `nextRound` send a list of
  /// `{playerIndex, score}` instead, accepted too.
  static Map<int, int> intMap(Object? value) {
    final result = <int, int>{};
    if (value is Map) {
      value.forEach((key, v) {
        final index = intOrNull(key);
        final number = intOrNull(v);
        if (index != null && number != null) result[index] = number;
      });
    } else if (value is List) {
      for (final item in value) {
        if (item is! Map) continue;
        final index = intOrNull(item['playerIndex']);
        final score = intOrNull(item['score']);
        if (index != null && score != null) result[index] = score;
      }
    }
    return result;
  }

  /// `intMap`, but `null` when the field is missing or `null`.
  static Map<int, int>? intMapOrNull(Object? value) =>
      value == null ? null : intMap(value);

  /// A map of player index to a list of card ids (`allHands`).
  static Map<int, List<int>>? handsOrNull(Object? value) {
    if (value is! Map) return null;
    final result = <int, List<int>>{};
    value.forEach((key, v) {
      final index = intOrNull(key);
      if (index != null) result[index] = ints(v);
    });
    return result;
  }

  /// A timestamp, in UTC.
  ///
  /// Accepts Unix seconds (most Node fields), Unix milliseconds (a number
  /// `>= 1e10`: `lastAction.timestamp`, `connectedAt`), a numeric string, or
  /// an RFC 3339 string (some Rust fields). `null` when missing or unreadable.
  static DateTime? timestamp(JsonMap json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) {
      final number = num.tryParse(value);
      if (number == null) return DateTime.tryParse(value)?.toUtc();
      return _fromEpoch(number);
    }
    if (value is num) return _fromEpoch(value);
    return null;
  }

  static DateTime _fromEpoch(num value) {
    final millis = value < 1e10 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis.round(), isUtc: true);
  }
}

/// One page of a listing, with whatever paging data the backend sent:
/// Node sends `pagination {limit, offset, hasMore}` or `{total, limit,
/// offset}`, Rust sometimes only a top-level `total`.
class Page<T> {
  const Page({
    required this.items,
    this.total,
    this.limit,
    this.offset,
    this.hasMore,
  });

  factory Page.fromJson(
    JsonMap json,
    String itemsKey,
    T Function(JsonMap) parse,
  ) {
    final paging = Json.map(json, 'pagination') ?? json;
    return Page(
      items: Json.list(json, itemsKey, parse),
      total: Json.intOrNull(paging['total'] ?? json['total']),
      limit: Json.intOrNull(paging['limit']),
      offset: Json.intOrNull(paging['offset']),
      hasMore: paging['hasMore'] is bool ? paging['hasMore'] as bool : null,
    );
  }

  final List<T> items;
  final int? total;
  final int? limit;
  final int? offset;
  final bool? hasMore;
}
