import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// One asynchronous read, with its three other states: loading, failed (with
/// a way to try again) and — through [isEmpty] — nothing to show.
///
/// The history and statistics screens each hold one or more of these, so a
/// failing leaderboard does not hide the personal statistics next to it.
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({
    super.key,
    required this.future,
    required this.errorMessage,
    required this.builder,
    this.onRetry,
    this.isEmpty,
    this.emptyMessage,
  });

  /// The read; a new one restarts the section.
  final Future<T> future;

  /// The text to show for a failure, chosen from the exception — never the
  /// backend's own message, which is for logs: screens react to the
  /// `ApiException.code`.
  final String Function(Object error) errorMessage;

  /// Builds the answer. Not called while [isEmpty] holds.
  final Widget Function(BuildContext context, T value) builder;

  /// Runs the read again; no button without it.
  final VoidCallback? onRetry;

  /// Answers that carry no row, so [emptyMessage] shows instead.
  final bool Function(T value)? isEmpty;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _Centered(
            child: CircularProgressIndicator(semanticsLabel: l10n.loading),
          );
        }
        if (snapshot.hasError) {
          return _Centered(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  errorMessage(snapshot.error!),
                  key: const Key('async-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.retryButton),
                  ),
                ],
              ],
            ),
          );
        }
        final value = snapshot.data as T;
        final empty = emptyMessage;
        if (empty != null && (isEmpty?.call(value) ?? false)) {
          return _Centered(
            child: Text(
              empty,
              key: const Key('async-empty'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return builder(context, value);
      },
    );
  }
}

/// [future], marked as already handled.
///
/// An [AsyncSection] subscribes to its future on the next build, so a read
/// that fails before that frame would be a zone-level unhandled error (and a
/// failing widget test). `ignore()` adds a listener that drops the error
/// without taking it away from the section, which shows it.
Future<T> startRead<T>(Future<T> future) => future..ignore();

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Center(child: child),
  );
}
