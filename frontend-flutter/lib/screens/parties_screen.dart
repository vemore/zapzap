import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/party.dart';
import '../providers/party_provider.dart';
import '../repositories/party_repository.dart';
import '../router.dart';
import '../widgets/error_banner.dart';
import '../widgets/party_card.dart';
import '../widgets/zapzap_app_bar.dart';

/// The public parties (`PartyList.jsx`): one card each, a Joined badge on
/// the ones the user is in, and the single thing to do with each — join it,
/// go back to its lobby, or continue its game. Pull down to refresh.
class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key});

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  late final PartyListProvider _parties;

  @override
  void initState() {
    super.initState();
    _parties = PartyListProvider(context.read<PartyRepository>())..load();
  }

  @override
  void dispose() {
    _parties.dispose();
    super.dispose();
  }

  // `push` rather than `go` everywhere below: the lobby, the game and the
  // form go on top of the list, so the Android system Back returns to it.
  void _open(PartySummary party) => context.push(
    party.status == PartyStatus.playing
        ? AppRoutes.gamePath(party.id)
        : AppRoutes.partyPath(party.id),
  );

  Future<void> _join(PartySummary party) async {
    if (await _parties.join(party.id) && mounted) {
      context.push(AppRoutes.partyPath(party.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ZapZapAppBar(title: l10n.partiesTitle),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-party'),
        onPressed: () => context.push(AppRoutes.createParty),
        icon: const Icon(Icons.add),
        label: Text(l10n.partiesCreateButton),
      ),
      body: ListenableBuilder(
        listenable: _parties,
        builder: (context, _) {
          if (_parties.loading) {
            return Center(
              child: CircularProgressIndicator(
                semanticsLabel: l10n.partiesLoading,
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => _parties.load(showSpinner: false),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.partiesHeading,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (_parties.error != null) ...[
                          const SizedBox(height: 12),
                          ErrorBanner(
                            message: partyErrorText(l10n, _parties.error!),
                            onRetry: _parties.load,
                          ),
                        ],
                        // A failed first load has no list to speak of: the
                        // banner alone, not "no party yet" under it.
                        if (_parties.parties.isEmpty &&
                            _parties.error == null) ...[
                          const SizedBox(height: 48),
                          const Icon(Icons.groups, size: 56),
                          const SizedBox(height: 12),
                          Text(
                            l10n.partiesEmptyTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.partiesEmptyBody,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _cards(context),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The cards, one column on a phone and up to three on a wide screen.
  ///
  /// Rows rather than a `SliverGrid`: a grid tile needs a height decided
  /// before the card is laid out, and any fixed one is too short at a large
  /// system font size. A row sizes to its tallest card, and stretches the
  /// others to match.
  Widget _cards(BuildContext context) {
    final parties = _parties.parties;
    final width = MediaQuery.sizeOf(context).width;
    final columns = ((width - 32) ~/ 340).clamp(1, 3);
    final rows = (parties.length + columns - 1) ~/ columns;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      sliver: SliverList.builder(
        itemCount: rows,
        itemBuilder: (context, row) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) const SizedBox(width: 12),
                  Expanded(
                    child: switch (row * columns + column) {
                      final index when index < parties.length => PartyCard(
                        party: parties[index],
                        onJoin: () => _join(parties[index]),
                        onOpen: () => _open(parties[index]),
                      ),
                      // The last row's empty columns, so the cards beside
                      // them keep their width.
                      _ => const SizedBox.shrink(),
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
