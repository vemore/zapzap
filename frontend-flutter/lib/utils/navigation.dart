import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Back navigation that keeps the Android system Back button working.
///
/// Screens reached from another one are `push`ed, so the system Back pops
/// back to it; `go` would replace the whole stack and the next Back would
/// leave the app. A screen's own back button therefore pops too, and only
/// when nothing is below it — a deep link, a reload of the PWA — does it
/// `go` to [fallback].
extension BackNavigation on BuildContext {
  void popOrGo(String fallback) {
    if (canPop()) {
      pop();
    } else {
      go(fallback);
    }
  }

  /// [popOrGo], replacing the screen left in the browser's history too: a
  /// pop is reported to the browser as a new entry, so its Back would
  /// return to the screen left. For a screen that must not be come back to
  /// that way — the game, over or left.
  void leaveFor(String fallback) {
    Router.neglect(this, () => popOrGo(fallback));
  }

  /// Replaces the screen on show with [location], in the browser's history
  /// too: the address bar shows [location], and the browser's Back skips the
  /// replaced screen as the system Back does. A plain `pushReplacement` would
  /// add a history entry, and the browser's Back would return to it.
  void replaceWith(String location) {
    Router.neglect(this, () => pushReplacement(location));
  }
}
