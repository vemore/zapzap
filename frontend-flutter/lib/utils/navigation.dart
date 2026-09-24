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
  /// Pops the screen on show, or `go`es to [fallback] when nothing is below
  /// it, replacing the screen left in the browser's history too: go_router
  /// reports a pop, like a `go`, as a new browser entry, so without
  /// `Router.neglect` the browser's Back would return to the screen left.
  void popOrGo(String fallback) {
    Router.neglect(this, () {
      if (canPop()) {
        pop();
      } else {
        go(fallback);
      }
    });
  }

  /// Replaces the screen on show with [location], in the browser's history
  /// too: the address bar shows [location], and the browser's Back skips the
  /// replaced screen as the system Back does. A plain `pushReplacement` would
  /// add a history entry, and the browser's Back would return to it.
  void replaceWith(String location) {
    Router.neglect(this, () => pushReplacement(location));
  }
}
