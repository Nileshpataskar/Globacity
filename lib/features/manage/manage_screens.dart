import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/guard.dart';
import '../../data/manage.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'manage_kit.dart';
import 'resources.dart';

// ---------------------------------------------------------------------------
// Shell
// ---------------------------------------------------------------------------

class ManageShell extends StatelessWidget {
  const ManageShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Dashboard'),
    (Icons.people_alt_outlined, Icons.people_alt_rounded, 'Residents'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Finance'),
    (Icons.support_agent_outlined, Icons.support_agent_rounded, 'Help desk'),
    (Icons.menu_rounded, Icons.menu_open_rounded, 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    // Laptop / desktop (web dashboard): sidebar navigation instead of bottom tabs.
    if (MediaQuery.sizeOf(context).width >= 900) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1200,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: AppLogo(size: 40),
            ),
            destinations: [
              for (final (icon, selected, label) in _items)
                NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
            ],
          ),
          VerticalDivider(width: 1, color: context.palette.border),
          Expanded(child: shell),
        ]),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: BrandNavBar(
        items: _items,
        index: shell.currentIndex,
        onSelect: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}

/// Opens a generic resource list, optionally on a given filter tab.
void openResource(BuildContext context, ResourceSpec spec, [int filter = 0, String? tower]) =>
    context.push(Routes.manageResource(spec.key, filter, tower));

/// App-bar title with a community switcher when the user manages more than one.
class _CommunityTitle extends ConsumerWidget {
  const _CommunityTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(managedCommunitiesProvider).value ?? [];
    final current = ref.watch(manageCommunityProvider);
    final myTowers = ref.watch(myManagedTowersProvider);
    final name = '${current?['name'] ?? 'Management'}${myTowers.isEmpty ? '' : ' · ${myTowers.join(', ')}'}';
    if (list.length < 2) return Text(name);
    return PopupMenuButton<String>(
      tooltip: 'Switch community',
      onSelected: (id) => selectManagedCommunity(ref, id),
      itemBuilder: (_) => [for (final c in list) PopupMenuItem(value: '${c['id']}', child: Text('${c['name']}'))],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
        const Icon(Icons.arrow_drop_down_rounded),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

class ManageDashboardScreen extends ConsumerWidget {
  const ManageDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final communities = ref.watch(managedCommunitiesProvider);
    final summary = ref.watch(manageSummaryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const _CommunityTitle(),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push(Routes.notifications),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: AsyncView<List<Json>>(
        value: communities,
        onRetry: () => ref.invalidate(managedCommunitiesProvider),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.location_city_rounded,
              title: 'No community yet',
              message: 'Create a community first, then manage it from here.',
              action: ref.watch(isPlatformAdminProvider) ? 'Add community' : null,
              onAction: () => openResource(context, platformCommunities),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(manageSummaryProvider);
              await ref.read(manageSummaryProvider.future).catchError((_) => null);
            },
            child: AsyncView<Json?>(
              value: summary,
              onRetry: () => ref.invalidate(manageSummaryProvider),
              data: (s) => s == null
                  ? const SizedBox.shrink()
                  : ManageWidth(child: _Dashboard(summary: s, towerAdmin: ref.watch(isTowerAdminProvider))),
            ),
          );
        },
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.summary, this.towerAdmin = false});

  final Json summary;
  final bool towerAdmin;

  @override
  Widget build(BuildContext context) {
    final c = (summary['counts'] as Json).map((k, v) => MapEntry(k, (v as num).toInt()));
    final towerRows = (summary['towers'] as List? ?? []).cast<Json>();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final m = summary['money'] as Json;
    final currency = '${(summary['community'] as Json)['currency']}';
    String money(String key) => fmtMoney(m[key], currency);
    int n(String k) => c[k] ?? 0;

    final alerts = [
      if (n('active_sos') > 0)
        (Icons.sos_rounded, '${n('active_sos')} active SOS alert${n('active_sos') == 1 ? '' : 's'}', Tone.danger, sos, 0),
      if (n('pending_approvals') > 0)
        (Icons.how_to_reg_rounded, '${n('pending_approvals')} resident${n('pending_approvals') == 1 ? '' : 's'} waiting for approval',
            Tone.warning, memberships, 0),
      if (n('pending_move_requests') > 0)
        (Icons.local_shipping_rounded, '${n('pending_move_requests')} move request${n('pending_move_requests') == 1 ? '' : 's'} to review',
            Tone.warning, moveRequests, 0),
      if (n('open_incidents') > 0)
        (Icons.report_gmailerrorred_rounded, '${n('open_incidents')} open incident${n('open_incidents') == 1 ? '' : 's'}', Tone.danger,
            incidents, 0),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
      children: [
        for (final (icon, text, tone, spec, filter) in alerts) ...[
          AppCard(
            onTap: () => openResource(context, spec, filter),
            color: tone.resolve(context).withValues(alpha: 0.08),
            borderColor: tone.resolve(context).withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(children: [
              Icon(icon, color: tone.resolve(context)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(text, style: context.text.titleSmall)),
              Icon(Icons.chevron_right_rounded, color: context.palette.textMuted),
            ]),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (alerts.isEmpty)
          AppCard(
            color: context.palette.success.withValues(alpha: 0.08),
            borderColor: context.palette.success.withValues(alpha: 0.3),
            child: Row(children: [
              Icon(Icons.check_circle_rounded, color: context.palette.success),
              const SizedBox(width: AppSpacing.md),
              const Expanded(child: Text('All clear. Nothing needs your attention.')),
            ]),
          ),
        const SectionHeader(title: 'Money'),
        AppCard(
          onTap: () => StatefulNavigationShell.maybeOf(context)?.goBranch(2),
          child: Column(children: [
            Row(children: [
              Expanded(child: _Metric(label: 'Collected this month', value: money('collected_this_month'), tone: Tone.success)),
              Expanded(child: _Metric(label: 'Billed this month', value: money('invoiced_this_month'))),
            ]),
            const Divider(height: AppSpacing.xl),
            Row(children: [
              Expanded(child: _Metric(label: 'Outstanding', value: money('outstanding'), tone: Tone.warning)),
              Expanded(child: _Metric(label: 'Overdue (${n('defaulter_units')} flats)', value: money('overdue'), tone: Tone.danger)),
            ]),
          ]),
        ),
        SectionHeader(title: towerAdmin ? 'My towers' : 'Towers'),
        for (final t in towerRows) ...[_TowerCard(tower: t, currency: currency), const SizedBox(height: AppSpacing.sm)],
        if (towerRows.isEmpty) const Text('No towers yet. Add one from More → Towers.'),
        const SectionHeader(title: 'Community'),
        GridView.count(
          crossAxisCount: wide ? 6 : 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.05,
          children: [
            _Stat(icon: Icons.apartment_rounded, value: '${n('towers')}', label: 'Towers', onTap: () => openResource(context, towers)),
            _Stat(icon: Icons.door_front_door_rounded, value: '${n('occupied_units')}/${n('units')}', label: 'Flats occupied',
                onTap: () => openResource(context, units)),
            _Stat(icon: Icons.people_alt_rounded, value: '${n('residents')}', label: 'Residents',
                onTap: () => openResource(context, memberships, 1)),
            _Stat(icon: Icons.support_agent_rounded, value: '${n('open_tickets')}', label: 'Open tickets',
                onTap: () => StatefulNavigationShell.maybeOf(context)?.goBranch(3)),
            _Stat(icon: Icons.groups_rounded, value: '${n('inside_now')}', label: 'Visitors inside',
                onTap: () => openResource(context, visitorLog, 1)),
            if (!towerAdmin)
              _Stat(icon: Icons.badge_rounded, value: '${n('staff')}', label: 'Staff', onTap: () => openResource(context, staff))
            else
              _Stat(icon: Icons.warning_amber_rounded, value: '${n('defaulter_units')}', label: 'Defaulters',
                  onTap: () => openResource(context, defaulters)),
          ],
        ),
        const SectionHeader(title: 'Quick actions'),
        GridView.count(
          crossAxisCount: wide ? 8 : 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.85,
          children: [
            ActionTile(icon: Icons.how_to_reg_rounded, label: 'Approvals', onTap: () => openResource(context, memberships)),
            ActionTile(icon: Icons.campaign_rounded, label: 'Post notice', onTap: () => openResource(context, notices)),
            ActionTile(icon: Icons.receipt_long_rounded, label: 'Bill all flats', onTap: () => context.push(Routes.manageBulkBill)),
            if (!towerAdmin) ...[
              ActionTile(icon: Icons.person_add_alt_1_rounded, label: 'Add staff', onTap: () => openResource(context, staff)),
              ActionTile(icon: Icons.how_to_vote_rounded, label: 'New poll', onTap: () => openResource(context, polls)),
            ] else
              ActionTile(icon: Icons.apartment_rounded, label: 'Tower settings', onTap: () => openResource(context, towers)),
          ],
        ),
      ],
    );
  }
}

/// One tower on the dashboard: occupancy, approvals, dues and its admins.
class _TowerCard extends StatelessWidget {
  const _TowerCard({required this.tower, required this.currency});

  final Json tower;
  final String currency;

  @override
  Widget build(BuildContext context) {
    int n(String k) => (tower[k] as num?)?.toInt() ?? 0;
    final pending = n('pending_approvals');
    final auto = tower['approval_mode'] == 'auto';
    final admins = (tower['admins'] as List? ?? []).cast<String>();
    final id = '${tower['id']}';
    return AppCard(
      onTap: () => openResource(context, memberships, pending > 0 ? 0 : 1, id),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const IconBadge(icon: Icons.apartment_rounded, size: 38),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${tower['name']}', style: context.text.titleMedium),
              Text(admins.isEmpty ? 'Managed by community admin' : 'Tower admin: ${admins.join(', ')}',
                  style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          StatusChip(label: auto ? 'Auto-approve' : 'Manual approval', tone: auto ? Tone.info : Tone.neutral),
        ]),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.sm, children: [
          _Metric(label: 'Flats occupied', value: '${n('occupied_units')}/${n('units')}'),
          _Metric(label: 'Residents', value: '${n('residents')}'),
          _Metric(label: 'Pending', value: '$pending', tone: pending > 0 ? Tone.warning : null),
          _Metric(label: 'Open tickets', value: '${n('open_tickets')}'),
          _Metric(label: 'Overdue', value: fmtMoney(tower['overdue'], currency),
              tone: (num.tryParse('${tower['overdue']}') ?? 0) > 0 ? Tone.danger : null),
          _Metric(label: 'Maintenance',
              value: tower['maintenance_amount'] == null ? 'Not set' : fmtMoney(tower['maintenance_amount'], currency)),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.sm, children: [
          if (pending > 0)
            FilledButton.tonalIcon(
              onPressed: () => openResource(context, memberships, 0, id),
              icon: const Icon(Icons.how_to_reg_rounded, size: 18),
              label: Text('Review $pending request${pending == 1 ? '' : 's'}'),
            ),
          TextButton(onPressed: () => openResource(context, memberships, 1, id), child: const Text('Residents')),
          TextButton(onPressed: () => openResource(context, invoices, 0, id), child: const Text('Bills')),
        ]),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Tone? tone;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: context.text.titleMedium?.copyWith(color: tone?.resolve(context))),
        ],
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label, this.onTap});

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: context.scheme.primary, size: 22),
            Text(value, style: context.text.titleLarge),
            Text(label, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Residents & help desk tabs
// ---------------------------------------------------------------------------

class ManageResidentsTab extends StatelessWidget {
  const ManageResidentsTab({super.key});

  @override
  Widget build(BuildContext context) => ResourceListScreen(spec: memberships, embedded: true);
}

class ManageHelpdeskTab extends StatelessWidget {
  const ManageHelpdeskTab({super.key});

  @override
  Widget build(BuildContext context) => ResourceListScreen(spec: tickets, embedded: true);
}

// ---------------------------------------------------------------------------
// Finance
// ---------------------------------------------------------------------------

class ManageFinanceScreen extends ConsumerWidget {
  const ManageFinanceScreen({super.key});

  Future<void> _remindAll(BuildContext context, WidgetRef ref) async {
    if (!await confirmDialog(context, 'Send a payment reminder to every flat with overdue bills?', action: 'Send')) return;
    if (!context.mounted) return;
    final api = ref.read(manageApiProvider);
    await runAction(context, () async {
      final res = await api.post('/manage/defaulters/remind/', {'community': api.communityId}) as Json;
      return res;
    }, success: 'Reminders sent');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(manageSummaryProvider).value;
    final towerAdmin = ref.watch(isTowerAdminProvider);
    final m = s?['money'] as Json?;
    final currency = '${(s?['community'] as Json?)?['currency'] ?? ''}';
    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
      body: ManageWidth(child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(manageSummaryProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
          children: [
            if (m != null)
              AppCard(
                child: Row(children: [
                  Expanded(child: _Metric(label: 'Outstanding', value: fmtMoney(m['outstanding'], currency), tone: Tone.warning)),
                  Expanded(child: _Metric(label: 'Overdue', value: fmtMoney(m['overdue'], currency), tone: Tone.danger)),
                  Expanded(child: _Metric(label: 'Collected (month)', value: fmtMoney(m['collected_this_month'], currency),
                      tone: Tone.success)),
                ]),
              ),
            TileGroup(title: 'Billing', children: [
              MenuTile(icon: Icons.post_add_rounded, title: 'Bill all flats', subtitle: 'Raise maintenance or any charge in one go',
                  onTap: () => context.push(Routes.manageBulkBill)),
              MenuTile(icon: Icons.receipt_long_rounded, title: 'Bills', subtitle: 'Raise single bills, record cash/cheque, cancel',
                  onTap: () => openResource(context, invoices)),
              if (!towerAdmin)
                MenuTile(icon: Icons.category_rounded, title: 'Charge types', subtitle: 'Maintenance, water, parking…',
                    onTap: () => openResource(context, chargeTypes)),
            ]),
            TileGroup(title: 'Collections', children: [
              MenuTile(icon: Icons.account_balance_wallet_rounded, title: 'Payments received',
                  onTap: () => openResource(context, payments)),
              MenuTile(icon: Icons.warning_amber_rounded, title: 'Defaulters', color: context.palette.danger,
                  subtitle: s == null ? null : '${(s['counts'] as Json)['defaulter_units']} flats overdue',
                  onTap: () => openResource(context, defaulters)),
              MenuTile(icon: Icons.notifications_active_rounded, title: 'Remind all defaulters',
                  onTap: () => _remindAll(context, ref)),
            ]),
          ],
        ),
      )),
    );
  }
}

class BulkBillScreen extends ConsumerWidget {
  const BulkBillScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(manageApiProvider);
    return ValuesFormScreen(
      title: 'Bill all flats',
      intro: 'Creates one bill per flat. Tax (GST/VAT) uses your country\'s rate. Residents are notified and can pay in the app.',
      fields: bulkBillFields,
      submitLabel: 'Create bills',
      onSubmit: (values) async {
        final res = await api.post('/manage/invoices/bulk/', {'community': api.communityId, ...values}) as Json;
        ref.invalidate(manageSummaryProvider);
        return res;
      },
      successMessage: (r) => 'Created ${(r as Json)['created']} bills',
    );
  }
}

class CommunitySettingsScreen extends ConsumerWidget {
  const CommunitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(manageCommunityProvider);
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return ValuesFormScreen(
      title: 'Community settings',
      fields: communitySettingsFields,
      initial: c,
      submitLabel: 'Save',
      onSubmit: (values) async {
        final settings = {...?(c['settings'] as Json?), ...?(values['settings'] as Json?)};
        await ref.read(manageApiProvider).patch('/manage/communities/${c['id']}/', {...values, 'settings': settings});
        ref.invalidate(managedCommunitiesProvider);
        return true;
      },
      successMessage: (_) => 'Settings saved',
    );
  }
}

// ---------------------------------------------------------------------------
// More
// ---------------------------------------------------------------------------

class ManageMoreScreen extends ConsumerWidget {
  const ManageMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final roles = ref.watch(myRolesProvider).value ?? {};
    final platform = ref.watch(isPlatformAdminProvider);
    final hasUnits = (ref.watch(propertiesProvider).value ?? []).any((p) => p.isApproved);
    final community = ref.watch(manageCommunityProvider);
    final myTowers = ref.watch(myManagedTowersProvider);
    final towerAdmin = myTowers.isNotEmpty;
    MenuTile tile(ResourceSpec spec, {String? subtitle, Color? color}) =>
        MenuTile(icon: spec.icon, title: spec.title, subtitle: subtitle, color: color, onTap: () => openResource(context, spec));
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ManageWidth(maxWidth: 720, child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
        children: [
          AppCard(
            onTap: () => context.push(Routes.editProfile),
            child: Row(children: [
              AppAvatar(name: user.name, size: 56, imageUrl: user.avatarUrl),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user.name, style: context.text.titleMedium),
                  Text(user.phone, style: context.text.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  StatusChip(
                    label: platform
                        ? 'Platform admin'
                        : towerAdmin
                            ? 'Tower admin · ${myTowers.join(', ')}'
                            : (roles.contains('admin') ? 'Community admin' : 'Manager'),
                    tone: Tone.primary,
                    icon: Icons.admin_panel_settings_rounded,
                  ),
                ]),
              ),
            ]),
          ),
          TileGroup(title: 'Property', children: [
            tile(towers, subtitle: towerAdmin ? 'Your tower settings and flats' : 'Approval rule, maintenance, flats, contact'),
            tile(units),
            if (!towerAdmin) ...[
              tile(gates),
              MenuTile(icon: Icons.tune_rounded, title: 'Community settings', subtitle: '${community?['name'] ?? ''}',
                  onTap: () => context.push(Routes.manageSettings)),
            ],
          ]),
          if (!towerAdmin)
            TileGroup(title: 'People', children: [
              tile(staff, subtitle: 'Community admins, tower admins, guards, facility'),
              tile(emergencyContacts),
            ]),
          TileGroup(title: 'Communication', children: [
            tile(notices, subtitle: towerAdmin ? 'Post to your tower(s)' : null),
            if (!towerAdmin) ...[tile(polls), tile(events)],
          ]),
          TileGroup(title: 'Requests & services', children: [
            tile(moveRequests),
            if (!towerAdmin) ...[tile(vendors), tile(bookings), tile(ticketCategories)],
          ]),
          TileGroup(title: 'Security', children: [
            tile(visitorLog),
            tile(sos, color: context.palette.danger),
            tile(incidents, color: context.palette.danger),
          ]),
          if (!towerAdmin) TileGroup(title: 'Moderation', children: [tile(forum), tile(classifieds)]),
          if (platform)
            TileGroup(title: 'Platform', children: [
              tile(platformCommunities, subtitle: 'Create and edit communities'),
              tile(platformCities),
            ]),
          TileGroup(title: 'Account', children: [
            MenuTile(icon: Icons.notifications_none_rounded, title: 'Notifications', onTap: () => context.push(Routes.notifications)),
            if (hasUnits) MenuTile(icon: Icons.home_outlined, title: 'Switch to resident app', onTap: () => context.go(Routes.home)),
            if (roles.contains('guard'))
              MenuTile(icon: Icons.shield_outlined, title: 'Switch to guard app', onTap: () => context.go(Routes.guardHome)),
          ]),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: context.palette.danger),
            onPressed: () async {
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) context.go(Routes.login);
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log out'),
          ),
        ],
      )),
    );
  }
}
