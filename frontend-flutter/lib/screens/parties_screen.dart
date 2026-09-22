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

  void _open(PartySummary party) => context.go(
    party.status == PartyStatus.playing
        ? AppRoutes.gamePath(party.id)
        : AppRoutes.partyPath(party.id),
  );

  Future<void> _join(PartySummary party) async {
    if (await _parties.join(party.id) && mounted) {
      context.go(AppRoutes.partyPath(party.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ZapZapAppBar(title: l10n.partiesTitle),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-party'),
        onPressed: () => context.go(AppRoutes.createParty),
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
                        if (_parties.parties.isEmpty) ...[
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 360,
                          mainAxisExtent: 192,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: _parties.parties.length,
                    itemBuilder: (context, index) {
                      final party = _parties.parties[index];
                      return PartyCard(
                        party: party,
                        onJoin: () => _join(party),
                        onOpen: () => _open(party),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
