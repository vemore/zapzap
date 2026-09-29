import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../router.dart';
import '../utils/app_theme.dart';

/// The lasting warning to a guest ([AuthProvider.isGuest]): the account is
/// only on this device until the player sets a password of their own — on
/// the web, only in this browser, and lost with its data. On the parties
/// screen and the account page; nothing for any other player.
///
/// [showButton] adds the way to the account page ([AppRoutes.account]),
/// which the account page itself leaves out.
class GuestBanner extends StatelessWidget {
  const GuestBanner({super.key, this.showButton = true, this.web = kIsWeb});

  final bool showButton;

  /// The web build's wording: the account lives in the browser's storage.
  final bool web;

  @override
  Widget build(BuildContext context) {
    if (!context.select<AuthProvider, bool>((auth) => auth.isGuest)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final text = [l10n.guestBanner, if (web) l10n.guestBannerWeb].join(' ');
    return Container(
      key: const Key('guest-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amber500.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.amber500),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.amber400,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(text, key: const Key('guest-banner-text'))),
            ],
          ),
          if (showButton)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('guest-banner-register'),
                onPressed: () => context.push(AppRoutes.account),
                child: Text(l10n.guestBannerButton),
              ),
            ),
        ],
      ),
    );
  }
}
