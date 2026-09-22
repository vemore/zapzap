import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';

/// The ZapZap mark: a bolt over the application name.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.bolt, size: 72, color: AppColors.amber400),
        Text(
          l10n.appTitle,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: AppColors.amber400,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
