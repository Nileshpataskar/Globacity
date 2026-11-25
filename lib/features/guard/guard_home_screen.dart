import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/device.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/guard.dart';
import '../../data/providers.dart';

/// Guard dashboard: shift, today's summary, emergency alerts and quick actions.
class GuardHomeScreen extends ConsumerWidget {
  const GuardHomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(guardContextProvider);
    ref.invalidate(guardSosProvider);
    ref.invalidate(guardSummaryProvider);
    await ref.read(guardSummaryProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gctx = ref.watch(guardContextProvider);
    final summary = ref.watch(guardSummaryProvider);
    final sos = (ref.watch(guardSosProvider).value ?? []).where((a) => a.isOpen).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(context: gctx.value)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
              sliver: SliverList.list(
                children: [
                  if (gctx.hasValue && gctx.value!.shift == null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      color: context.palette.warning.withValues(alpha: 0.08),
                      borderColor: context.palette.warning.withValues(alpha: 0.4),
                      onTap: () => context.push(Routes.guardShift),
                      child: Row(
                        children: [
                          IconBadge(icon: Icons.login_rounded, color: context.palette.warning),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("You're off duty", style: context.text.titleSmall),
                                Text('Select your gate and shift to start', style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                            onPressed: () => context.push(Routes.guardShift),
                            child: const Text('Start shift'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  for (final a in sos) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _SosCard(alert: a),
                  ],
                  const SectionHeader(title: 'Quick actions'),
                  const _QuickActions(),
                  const SectionHeader(title: "Today's summary"),
                  AsyncView<GuardSummary>(
                    value: summary,
                    compact: true,
                    onRetry: () => ref.invalidate(guardSummaryProvider),
                    data: (s) => _SummaryGrid(summary: s),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.context});

  final GuardContext? context;

  @override
  Widget build(BuildContext ctx, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final shift = context?.shift;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: ctx.palette.heroGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.xl)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(context?.communityName ?? 'Security', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: ctx.text.titleSmall?.copyWith(color: Colors.white)),
                  ),
                  IconButton(
                    onPressed: () => ctx.push(Routes.notifications),
                    icon: Badge(
                      isLabelVisible: ref.watch(unreadCountProvider) > 0,
                      label: Text('${ref.watch(unreadCountProvider)}'),
                      child: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Hello, ${user.name.split(' ').first}', style: ctx.text.headlineSmall?.copyWith(color: Colors.white)),
              const SizedBox(height: AppSpacing.sm),
              InkWell(
                onTap: () => ctx.push(Routes.guardShift),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(shift == null ? Icons.circle_outlined : Icons.circle, size: 10,
                          color: shift == null ? Colors.white70 : const Color(0xFF4ADE80)),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        shift == null
                            ? 'Off duty'
                            : '${shift.shiftLabel.split(' (').first} shift · ${shift.gateName ?? 'All gates'} · since ${Fmt.time(shift.startedAt)}',
                        style: ctx.text.labelMedium?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosCard extends ConsumerWidget {
  const _SosCard({required this.alert});

  final SosAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final danger = context.palette.danger;
    final a = alert;
    return AppCard(
      color: danger.withValues(alpha: 0.08),
      borderColor: danger.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: Icons.sos_rounded, color: danger),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EMERGENCY · ${a.type.toUpperCase()}', style: context.text.labelMedium?.copyWith(color: danger)),
                    Text('${a.unitLabel} · ${a.raisedBy}', style: context.text.titleSmall),
                    Text('${Fmt.relative(a.time)}${a.status == 'acknowledged' ? ' · acknowledged' : ''}', style: context.text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Device.call(context, a.phone),
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: a.status == 'active' ? danger : context.palette.success),
                  onPressed: () => runAction(context,
                      () => ref.read(guardActionsProvider).sosAction(a.id, a.status == 'active' ? 'acknowledge' : 'resolve'),
                      success: a.status == 'active' ? 'Resident notified that you are on the way' : 'Alert resolved'),
                  child: Text(a.status == 'active' ? 'Acknowledge' : 'Resolve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final actions = [
      (Icons.qr_code_scanner_rounded, 'Scan\npass', context.scheme.primary, () => context.push(Routes.guardScan)),
      (Icons.person_add_alt_rounded, 'Walk-in\nvisitor', const Color(0xFF7C3AED), () => context.push(Routes.guardWalkIn)),
      (Icons.directions_car_rounded, 'Vehicle\nentry', const Color(0xFF0EA5A4), () => context.push(Routes.guardVehicles)),
      (Icons.report_gmailerrorred_rounded, 'Report\nincident', p.danger, () => context.push(Routes.guardIncidents)),
      (Icons.cleaning_services_rounded, 'Daily help\ninside', const Color(0xFFEA580C), () => context.push(Routes.guardHelpers)),
      (Icons.child_care_rounded, 'Kid\nexits', const Color(0xFFDB2777), () => context.push(Routes.guardKidExits)),
      (Icons.manage_search_rounded, 'Resident\ndirectory', p.info, () => context.push(Routes.guardDirectory)),
      (Icons.sensor_door_rounded, 'Open\ngate', p.success, () => context.go(Routes.guardGate)),
    ];
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.78,
        children: [for (final (i, l, c, t) in actions) ActionTile(icon: i, label: l, color: c, onTap: t)],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final GuardSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tiles = [
      ('inside_now', 'Visitors inside', Icons.login_rounded, p.success, Routes.guardVisitors),
      ('waiting_approval', 'Waiting approval', Icons.hourglass_top_rounded, p.warning, Routes.guardVisitors),
      ('active_passes', 'Active passes', Icons.qr_code_2_rounded, context.scheme.primary, Routes.guardVisitors),
      ('visitors_today', 'Visitors today', Icons.groups_rounded, p.info, Routes.guardVisitors),
      ('deliveries_today', 'Deliveries', Icons.inventory_2_rounded, const Color(0xFFEA580C), Routes.guardVisitors),
      ('cabs_today', 'Cabs', Icons.local_taxi_rounded, const Color(0xFFCA8A04), Routes.guardVisitors),
      ('daily_help_inside', 'Daily help inside', Icons.cleaning_services_rounded, const Color(0xFF7C3AED), Routes.guardHelpers),
      ('staff_on_duty', 'Staff on duty', Icons.badge_rounded, const Color(0xFF0891B2), Routes.guardStaff),
      ('vehicles_in_today', 'Vehicles in', Icons.directions_car_rounded, const Color(0xFF0EA5A4), Routes.guardVehicles),
      ('open_incidents', 'Open incidents', Icons.report_gmailerrorred_rounded, p.danger, Routes.guardIncidents),
      ('kid_exits_active', 'Kid exits allowed', Icons.child_care_rounded, const Color(0xFFDB2777), Routes.guardKidExits),
      ('active_sos', 'Active SOS', Icons.sos_rounded, p.danger, Routes.guardHome),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.05,
      children: [
        for (final (key, label, icon, color, route) in tiles)
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            onTap: () => Routes.guardTabs.contains(route) ? context.go(route) : context.push(route),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const Spacer(),
                Text('${summary[key]}', style: context.text.headlineSmall),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
              ],
            ),
          ),
      ],
    );
  }
}
