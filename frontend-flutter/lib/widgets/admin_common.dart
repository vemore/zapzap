import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_exception.dart';

/// The localised text of an admin failure: the backend's message is never
/// shown, only its code or status is read ([ApiException.code]). A tab
/// names what a 400 ([refused]) and a 404 ([notFound]) mean for its rows;
/// the defaults speak of accounts.
String adminErrorText(
  AppLocalizations l10n,
  Object error, {
  String? refused,
  String? notFound,
}) {
  if (error is! ApiException) return l10n.errorGeneric;
  if (error.isConnectivity) return l10n.errorNetwork;
  return switch (error.code) {
    // The backend answers 400, without a code, for oneself and an admin.
    ApiErrorCode.badRequest => refused ?? l10n.adminErrorRefused,
    ApiErrorCode.adminRequired ||
    ApiErrorCode.forbidden => l10n.adminErrorForbidden,
    ApiErrorCode.notFound ||
    ApiErrorCode.partyNotFound => notFound ?? l10n.adminErrorUserNotFound,
    _ => l10n.errorGeneric,
  };
}

/// Asks before an admin action, in a dialog keyed [key]: true only when
/// [confirmLabel] is pressed; cancelling or dismissing is false.
Future<bool> confirmAdminAction(
  BuildContext context, {
  required Key key,
  required String message,
  required String confirmLabel,
  Color? confirmColor,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: key,
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelButton),
        ),
        TextButton(
          key: const Key('admin-confirm-ok'),
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: confirmColor),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Previous, the rows on show, next — keyed `<keyPrefix>-previous`,
/// `-range` and `-next`.
class AdminPager extends StatelessWidget {
  const AdminPager({
    super.key,
    required this.keyPrefix,
    required this.pageSize,
    required this.offset,
    required this.total,
    required this.onPage,
  });

  final String keyPrefix;
  final int pageSize;
  final int offset;
  final int total;

  /// Null while a page loads.
  final ValueChanged<int>? onPage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = pageSize;
    final last = (offset + size).clamp(0, total);
    final onPage = this.onPage;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton(
            key: Key('$keyPrefix-previous'),
            onPressed: onPage == null || offset == 0
                ? null
                : () => onPage((offset - size).clamp(0, offset)),
            child: Text(l10n.adminPreviousPage),
          ),
          Text(
            l10n.adminPageRange(offset + 1, last, total),
            key: Key('$keyPrefix-range'),
          ),
          OutlinedButton(
            key: Key('$keyPrefix-next'),
            onPressed: onPage == null || last >= total
                ? null
                : () => onPage(offset + size),
            child: Text(l10n.adminNextPage),
          ),
        ],
      ),
    );
  }
}
