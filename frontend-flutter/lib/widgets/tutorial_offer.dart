import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../router.dart';
import '../services/tutorial_offer_store.dart';

/// On the app's first opening, the offer of the example game: Start or
/// Later. Either answer is remembered in [store], and the offer is never
/// made again; the ⋮ menu and the login screen still lead to the tutorial.
///
/// Offered to a signed-out user only, and never over the tutorial itself:
/// decided once, when both the stored session and [store] are read. A
/// signed-in user (every tester who had the app before it) or one opening on
/// `/tutorial` is not offered it, and the offer is marked made — a later
/// sign-out does not bring it up. A signed-in user is the only one who can
/// be on a game, so it never covers one. A [store] that fails offers nothing.
///
/// Above the router's navigator (`MaterialApp.builder`), so it is a card
/// over a barrier rather than a dialog; shown once the stored session is
/// read, so it never covers the splash.
class TutorialOffer extends StatefulWidget {
  const TutorialOffer({
    super.key,
    required this.store,
    required this.onStart,
    required this.location,
    required this.child,
  });

  final TutorialOfferStore store;

  /// Opens the tutorial.
  final VoidCallback onStart;

  /// The router's location now: `/tutorial`, or the splash remembering it,
  /// is not offered the tutorial again.
  final Uri? Function() location;

  final Widget child;

  @override
  State<TutorialOffer> createState() => _TutorialOfferState();
}

class _TutorialOfferState extends State<TutorialOffer> {
  /// What [TutorialOffer.store] answered, `null` until it has.
  bool? _offered;
  bool _decided = false;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    bool offered;
    try {
      offered = await widget.store.wasOffered();
    } catch (error) {
      // Unreadable: offered already, rather than at every opening.
      debugPrint('Tutorial offer not read: $error');
      offered = true;
    }
    if (mounted) setState(() => _offered = offered);
  }

  /// Once the session and the store are read: the offer, or not — then
  /// marked made, unless it shows (its answer marks it).
  void _decide({required bool signedIn}) {
    _decided = true;
    if (_offered != false) return;
    if (!signedIn && !_onTutorial()) {
      _show = true;
    } else {
      _mark();
    }
  }

  bool _onTutorial() {
    final uri = widget.location();
    if (uri == null) return false;
    if (uri.path == AppRoutes.tutorial) return true;
    final from = uri.queryParameters[AppRoutes.from];
    return from != null && Uri.tryParse(from)?.path == AppRoutes.tutorial;
  }

  /// A store that fails leaves the flag unset: the offer may come again.
  void _mark() => widget.store.markOffered().catchError((Object error) {
    debugPrint('Tutorial offer not marked: $error');
  });

  void _answer({required bool start}) {
    setState(() => _show = false);
    _mark();
    if (start) widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    final (restored, signedIn) = context.select<AuthProvider, (bool, bool)>(
      (a) => (a.isRestored, a.isAuthenticated),
    );
    if (!_decided && restored && _offered != null) {
      _decide(signedIn: signedIn);
    }
    // Always a stack, the app first in it: the router's navigator keeps its
    // place, and its state, when the offer comes and goes.
    return Stack(children: [widget.child, if (_show) ..._offer(context)]);
  }

  List<Widget> _offer(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return [
      const ModalBarrier(dismissible: false, color: Colors.black54),
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              key: const Key('tutorial-offer'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.tutorialOfferTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.tutorialOfferBody),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: [
                        TextButton(
                          key: const Key('tutorial-offer-later'),
                          onPressed: () => _answer(start: false),
                          child: Text(l10n.tutorialOfferLater),
                        ),
                        FilledButton(
                          key: const Key('tutorial-offer-start'),
                          onPressed: () => _answer(start: true),
                          child: Text(l10n.tutorialOfferStart),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
