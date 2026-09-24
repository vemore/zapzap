import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/party.dart';
import '../providers/auth_provider.dart';
import '../providers/party_provider.dart';
import '../providers/sse_provider.dart';
import '../repositories/party_repository.dart';
import '../router.dart';
import '../utils/app_theme.dart';
import '../widgets/error_banner.dart';
import '../widgets/party_card.dart';
import '../widgets/zapzap_app_bar.dart';

/// The public parties (`PartyList.jsx`), in two sections: "My games" — a
/// running game first, with an "In progress" badge and Resume — then
/// "Available games", which ends on an invitation to create one when there
/// is none.
/// Skeleton cards while the first answer is on its way; the event stream
/// keeps the list current, and pulling down refreshes it by hand.
class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key});

  /// The space below the last card, so the floating Create button — 56 px
  /// high, 16 px above the bottom — never covers its button.
  static const fabClearance = 88.0;

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  late final PartyListProvider _parties;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = context.read<AuthProvider>().user?.id;
    _parties = PartyListProvider(
      context.read<PartyRepository>(),
      events: context.read<SseProvider>().events,
    )..load();
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

  void _create() => context.push(AppRoutes.createParty);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ZapZapAppBar(title: l10n.partiesTitle),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-party'),
        backgroundColor: AppColors.amber400,
        foregroundColor: AppColors.slate900,
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(l10n.partiesCreateButton),
      ),
      body: ListenableBuilder(
        listenable: _parties,
        builder: (context, _) {
          final error = _parties.error;
          final mine = _parties.myParties;
          final others = _parties.openParties;
          return RefreshIndicator(
            onRefresh: () => _parties.load(showSpinner: false),
            child: CustomScrollView(
              // Pull to refresh works on a list shorter than the screen.
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (error != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: ErrorBanner(
                        message: partyErrorText(l10n, error),
                        onRetry: _parties.load,
                      ),
                    ),
                  ),
                if (_parties.loading)
                  _skeletons()
                else ...[
                  if (mine.isNotEmpty) ...[
                    _heading(context, l10n.partiesMine, 'mine'),
                    _cards(context, mine),
                  ],
                  _heading(context, l10n.partiesHeading, 'open'),
                  if (others.isNotEmpty)
                    _cards(context, others)
                  // A failed first load has no list to speak of: the banner
                  // alone, not "no party yet" under it.
                  else if (error == null)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(
                        child: _OpenPartiesInvite(
                          onCreate: _create,
                          nothingAtAll: mine.isEmpty,
                        ),
                      ),
                    ),
                ],
                const SliverToBoxAdapter(
                  child: SizedBox(height: PartiesScreen.fabClearance),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _heading(BuildContext context, String text, String id) =>
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        sliver: SliverToBoxAdapter(
          child: Semantics(
            header: true,
            child: Text(
              text,
              key: Key('parties-heading-$id'),
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: AppColors.slate400, letterSpacing: 0.8),
            ),
          ),
        ),
      );

  /// Three grey cards the shape of the real ones, while the list loads.
  Widget _skeletons() => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    sliver: SliverToBoxAdapter(
      child: Semantics(
        label: AppLocalizations.of(context).partiesLoading,
        child: const ExcludeSemantics(
          child: Column(
            children: [
              _SkeletonCard(),
              SizedBox(height: 12),
              _SkeletonCard(),
              SizedBox(height: 12),
              _SkeletonCard(),
            ],
          ),
        ),
      ),
    ),
  );

  /// [parties] as cards, one column on a phone and up to three on a wide
  /// screen.
  ///
  /// Rows rather than a `SliverGrid`: a grid tile needs a height decided
  /// before the card is laid out, and any fixed one is too short at a large
  /// system font size. A row sizes to its tallest card, and stretches the
  /// others to match.
  Widget _cards(BuildContext context, List<PartySummary> parties) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = ((width - 32) ~/ 340).clamp(1, 3);
    final rows = (parties.length + columns - 1) ~/ columns;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: rows,
        itemBuilder: (context, row) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
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
                        isHost:
                            _userId != null &&
                            parties[index].ownerId == _userId,
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

/// The end of an empty "Available games" section: there is nothing to join, so
/// create one, or pull down in case one just appeared.
class _OpenPartiesInvite extends StatelessWidget {
  const _OpenPartiesInvite({
    required this.onCreate,
    required this.nothingAtAll,
  });

  final VoidCallback onCreate;

  /// No party at all, mine included: the first-visit wording.
  final bool nothingAtAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: AppColors.slate400);
    return Container(
      key: const Key('parties-invite'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate600, width: 1.5),
      ),
      child: Column(
        children: [
          if (nothingAtAll) ...[
            Text(
              l10n.partiesEmptyTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.partiesEmptyBody,
              textAlign: TextAlign.center,
              style: muted,
            ),
          ] else
            Text(
              l10n.partiesOpenEmpty,
              textAlign: TextAlign.center,
              style: muted,
            ),
          TextButton(
            key: const Key('parties-invite-create'),
            onPressed: onCreate,
            child: Text(l10n.partiesEmptyCreate, textAlign: TextAlign.center),
          ),
          Text(
            l10n.partiesPullToRefresh,
            textAlign: TextAlign.center,
            style: muted,
          ),
        ],
      ),
    );
  }
}

/// A party card's outline in grey: a name bar, a detail bar and a button.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.slate700,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
    return Container(
      key: const Key('party-skeleton'),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(140, 16),
                const SizedBox(height: 12),
                bar(100, 12),
              ],
            ),
          ),
          bar(88, 36),
        ],
      ),
    );
  }
}
