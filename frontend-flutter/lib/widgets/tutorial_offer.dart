import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/tutorial_offer_store.dart';

/// On the app's first opening, over whatever screen it opens on, the offer
/// of the example game: Start or Later. Either answer is remembered in
/// [store], and the offer is never made again; the ⋮ menu and the login
/// screen still lead to the tutorial.
///
/// Above the router's navigator (`MaterialApp.builder`), so it is a card
/// over a barrier rather than a dialog; shown once the stored session is
/// read, so it never covers the splash.
class TutorialOffer extends StatefulWidget {
  const TutorialOffer({
    super.key,
    required this.store,
    required this.onStart,
    required this.child,
  });

  final TutorialOfferStore store;

  /// Opens the tutorial.
  final VoidCallback onStart;

  final Widget child;

  @override
  State<TutorialOffer> createState() => _TutorialOfferState();
}

class _TutorialOfferState extends State<TutorialOffer> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.store.wasOffered().then((offered) {
      if (mounted && !offered) setState(() => _show = true);
    });
  }

  void _answer({required bool start}) {
    setState(() => _show = false);
    widget.store.markOffered();
    if (start) widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    final restored = context.select<AuthProvider, bool>((a) => a.isRestored);
    // Always a stack, the app first in it: the router's navigator keeps its
    // place, and its state, when the offer comes and goes.
    return Stack(
      children: [widget.child, if (_show && restored) ..._offer(context)],
    );
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
