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
}
