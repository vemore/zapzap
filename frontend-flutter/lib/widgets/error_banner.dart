import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/party_provider.dart';
import '../services/api_exception.dart';
import '../utils/app_theme.dart';

/// The localised text of a party failure. As everywhere in this client, the
/// backend's own message is never shown: only its code is read
/// ([ApiException.code]).
String partyErrorText(AppLocalizations l10n, Object error) {
  if (error is! ApiException) return l10n.errorGeneric;
  if (error.isConnectivity) return l10n.errorNetwork;
  return switch (error.code) {
    ApiErrorCode.partyNotFound => l10n.errorPartyNotFound,
    ApiErrorCode.partyFull => l10n.errorPartyFull,
    PartyErrorCode.partyStarted ||
    PartyErrorCode.partyAlreadyPlaying ||
    PartyErrorCode.partyPlaying => l10n.errorPartyStarted,
    PartyErrorCode.notOwner ||
    PartyErrorCode.notAuthorized ||
    ApiErrorCode.forbidden => l10n.errorNotOwner,
    PartyErrorCode.notInParty => l10n.errorNotInParty,
    _ => l10n.errorGeneric,
  };
}

/// A failure, in the red card the React client uses for the same thing.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});

  final String message;

  /// Shows a "try again" button when given.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(l10n.retryButton)),
        ],
      ),
    );
  }
}
