import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';

/// The ZapZap mark: a bolt over the application name and, with [pitch], one
/// line that says what the game is about — for a newcomer who reaches a
/// screen other than home through a direct link.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.pitch = false});

  final bool pitch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.bolt, size: 72, color: AppColors.amber400),
        Text(
          l10n.appTitle,
          style: theme.textTheme.displaySmall?.copyWith(
            color: AppColors.amber400,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (pitch) ...[
          const SizedBox(height: 8),
          Text(
            l10n.authPitch,
            key: const Key('app-pitch'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.slate400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
