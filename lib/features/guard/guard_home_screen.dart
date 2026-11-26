import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/device.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/guard.dart';
import '../../data/providers.dart';

/// Gate home: big, simple actions for the guard on duty, emergencies first.
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
    final summary = ref.watch(guardSummaryProvider).value;
    final sos = (ref.watch(guardSosProvider).value ?? []).where((a) => a.isOpen).toList();
    final offDuty = gctx.hasValue && gctx.value!.shift == null;

    final sections = <Widget>[
      for (final a in sos) ...[const SizedBox(height: AppSpacing.lg), _SosCard(alert: a)],
      if (offDuty) ...[const SizedBox(height: AppSpacing.lg), const _OffDutyCard()],
      const SizedBox(height: AppSpacing.lg),
      const _GateActions(),
      const SizedBox(height: AppSpacing.md),
      const _MoreActions(),
      const SectionHeader(title: 'Right now'),
      _LiveCounts(summary: summary),
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(context: gctx.value)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
              sliver: SliverList.list(children: [for (final (i, w) in sections.indexed) w.enter(i)]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scan a pass and jump to the gate screen with the code filled in.
Future<void> scanPass(BuildContext context) async {
  final code = await context.push<String>(Routes.guardScan);
  if (code != null && context.mounted) {
    HapticFeedback.selectionClick();
    context.go('${Routes.guardGate}?code=$code');
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.context});

  final GuardContext? context;

  @override
  Widget build(BuildContext ctx, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final shift = context?.shift;
    final unread = ref.watch(unreadCountProvider);
    return BrandBackdrop(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.sm, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BrandMark(size: 34, glow: true),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context?.communityName ?? 'Security', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: ctx.text.titleSmall?.copyWith(color: Colors.white)),
                      Text('Security desk', style: ctx.text.bodySmall?.copyWith(color: Colors.white60)),
                    ]),
                  ),
                  IconButton(
                    onPressed: () => ctx.push(Routes.notifications),
                    icon: Badge(
                      isLabelVisible: unread > 0,
                      label: Text('$unread'),
                      child: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Hello, ${user.name.split(' ').first}',
                      style: ctx.text.headlineMedium?.copyWith(color: Colors.white))
                  .enter(1, 0.3),
              const SizedBox(height: AppSpacing.sm),
              InkWell(
                onTap: () => ctx.push(Routes.guardShift),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: shift == null ? Colors.white54 : const Color(0xFF4ADE80),
                        ),
                      ).animate(onPlay: (c) => shift == null ? null : c.repeat(reverse: true)).fade(begin: 1, end: 0.35, duration: 900.ms),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        shift == null
                            ? 'Off duty · tap to start shift'
                            : 'On duty · ${shift.gateName ?? 'All gates'} · since ${Fmt.time(shift.startedAt)}',
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

class _OffDutyCard extends StatelessWidget {
  const _OffDutyCard();

  @override
  Widget build(BuildContext context) {
    final warn = context.palette.warning;
    return AppCard(
      color: warn.withValues(alpha: 0.08),
      borderColor: warn.withValues(alpha: 0.4),
      onTap: () => context.push(Routes.guardShift),
      child: Row(
        children: [
          IconBadge(icon: Icons.login_rounded, color: warn),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("You're off duty", style: context.text.titleSmall),
              Text('Pick your gate and shift to start', style: context.text.bodySmall),
            ]),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40), shape: const StadiumBorder()),
            onPressed: () => context.push(Routes.guardShift),
            child: const Text('Start shift'),
          ),
        ],
      ),
    );
  }
}

/// The four things a guard does all day, as big buttons.
class _GateActions extends StatelessWidget {
  const _GateActions();

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (Icons.qr_code_scanner_rounded, 'Scan QR', 'Visitor pass', const [AppColors.primary, Color(0xFF1D9BF0)], () => scanPass(context)),
      (Icons.dialpad_rounded, 'Enter code', '6-digit pass', const [Color(0xFF101828), Color(0xFF1E3A6E)], () => context.go(Routes.guardGate)),
      (Icons.person_add_alt_1_rounded, 'New visitor', 'Ask resident', const [Color(0xFF7C3AED), Color(0xFFA855F7)], () => context.push(Routes.guardWalkIn)),
      (Icons.delivery_dining_rounded, 'Delivery', 'Swiggy, Amazon…', const [Color(0xFFEA580C), Color(0xFFF59E0B)],
          () => context.push('${Routes.guardWalkIn}?type=delivery')),
    ];
    return GridView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisExtent: 128, mainAxisSpacing: AppSpacing.md, crossAxisSpacing: AppSpacing.md),
      children: [
        for (final (i, (icon, title, sub, colors, onTap)) in tiles.indexed)
          Pressable(
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))],
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                          child: Icon(icon, color: Colors.white, size: 26),
                        ),
                        const Spacer(),
                        Text(title, style: context.text.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                        Text(sub, style: context.text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ).pop(80 * i),
      ],
    );
  }
}

class _MoreActions extends ConsumerWidget {
  const _MoreActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final gates = ref.watch(guardContextProvider).value?.gates ?? [];
    final actions = [
      (Icons.logout_rounded, 'Check\nout', p.success, () => context.go(Routes.guardVisitors)),
      (Icons.cleaning_services_rounded, 'Daily\nhelp', const Color(0xFF0891B2), () => context.push(Routes.guardHelpers)),
      (Icons.directions_car_rounded, 'Vehicle\nentry', const Color(0xFF0EA5A4), () => context.push(Routes.guardVehicles)),
      (Icons.report_gmailerrorred_rounded, 'Report\nincident', p.danger, () => context.push(Routes.guardIncidents)),
      (Icons.manage_search_rounded, 'Call\nresident', p.info, () => context.push(Routes.guardDirectory)),
      (Icons.child_care_rounded, 'Kid\nexits', const Color(0xFFDB2777), () => context.push(Routes.guardKidExits)),
      (Icons.badge_rounded, 'Staff\nattendance', const Color(0xFF7C3AED), () => context.go(Routes.guardStaff)),
      if (gates.any((g) => g.iotEnabled))
        (Icons.sensor_door_rounded, 'Open\ngate', p.success, () => context.go(Routes.guardGate))
      else
        (Icons.history_rounded, 'Visitor\nlog', const Color(0xFFCA8A04), () => context.go(Routes.guardVisitors)),
    ];
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xs),
      child: GridView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: 112),
        children: [
          for (final (i, (icon, label, color, onTap)) in actions.indexed)
            ActionTile(icon: icon, label: label, color: color, onTap: onTap).pop(200 + 40 * i),
        ],
      ),
    );
  }
}

class _LiveCounts extends StatelessWidget {
  const _LiveCounts({required this.summary});

  final GuardSummary? summary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tiles = [
      ('inside_now', 'Inside now', Icons.login_rounded, p.success),
      ('waiting_approval', 'Waiting', Icons.hourglass_top_rounded, p.warning),
      ('active_passes', 'Expected', Icons.qr_code_2_rounded, context.scheme.primary),
      ('deliveries_today', 'Deliveries', Icons.inventory_2_rounded, const Color(0xFFEA580C)),
    ];
    return Row(
      children: [
        for (final (i, (key, label, icon, color)) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
              onTap: () => context.go(Routes.guardVisitors),
              child: Column(children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: AppSpacing.xs),
                Text(summary == null ? '–' : '${summary![key]}', style: context.text.titleLarge),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
              ]),
            ),
          ),
        ],
      ],
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

