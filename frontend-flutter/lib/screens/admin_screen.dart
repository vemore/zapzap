import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../router.dart';
import '../utils/navigation.dart';
import '../widgets/admin_parties.dart';
import '../widgets/admin_stats.dart';
import '../widgets/admin_users.dart';
import '../widgets/zapzap_app_bar.dart';

/// The tabs of the admin screen; each [segment] is its path under
/// `/admin/` ([AppRoutes.adminTab]).
enum AdminTab {
  users,
  parties,
  statistics;

  String get segment => name;

  /// The tab a path segment names, or null.
  static AdminTab? fromSegment(String segment) {
    for (final tab in values) {
      if (tab.segment == segment) return tab;
    }
    return null;
  }
}

/// The admin shell, the port of `frontend/src/components/Admin/AdminLayout.jsx`:
/// Users, Parties and Statistics tabs under the app bar. Only admins reach
/// it — [authRedirect] sends everyone else to the parties — but that guard
/// is cosmetic: the backend refuses every `/api/admin` call to a non-admin.
///
/// A tab is built — and loads — the first time it is on show, then kept
/// alive, so the users list keeps its page and search, and the parties
/// their filter, while another tab is on show. The URL stays the one the
/// screen was opened with.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, this.initialTab = AdminTab.users});

  final AdminTab initialTab;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: AdminTab.values.length,
    initialIndex: widget.initialTab.index,
    vsync: this,
  )..addListener(() => setState(() => _opened.add(_tabs.index)));

  /// The tabs shown at least once: the others are not built yet.
  late final Set<int> _opened = {widget.initialTab.index};

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ZapZapAppBar(
        title: l10n.adminTitle,
        leading: BackButton(
          key: const Key('back'),
          onPressed: () => context.popOrGo(AppRoutes.parties),
        ),
      ),
      body: Column(
        children: [
          TabBar(
            key: const Key('admin-tabs'),
            controller: _tabs,
            // Scrollable, so three labels fit a phone at a large font.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                key: const Key('admin-tab-users'),
                icon: const Icon(Icons.people),
                text: l10n.adminTabUsers,
              ),
              Tab(
                key: const Key('admin-tab-parties'),
                icon: const Icon(Icons.sports_esports),
                text: l10n.adminTabParties,
              ),
              Tab(
                key: const Key('admin-tab-statistics'),
                icon: const Icon(Icons.bar_chart),
                text: l10n.adminTabStatistics,
              ),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _tabs.index,
              children: [
                for (final tab in AdminTab.values)
                  if (!_opened.contains(tab.index))
                    const SizedBox.shrink()
                  else
                    switch (tab) {
                      AdminTab.users => const AdminUsersView(),
                      AdminTab.parties => const AdminPartiesView(),
                      AdminTab.statistics => const AdminStatisticsView(),
                    },
              ],
            ),
          ),
        ],
      ),
    );
  }
}
