import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../community/notices_screens.dart';
import '../visitors/visitors_screen.dart';
import 'property_switcher.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(propertiesProvider);
    ref.invalidate(visitorsProvider);
    ref.invalidate(duesSummaryProvider);
    ref.invalidate(noticesProvider);
    ref.invalidate(eventsProvider);
    ref.invalidate(notificationsProvider);
    await ref.read(currentPropertyProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final property = ref.watch(currentPropertyProvider);
    return Scaffold(
      body: AsyncView<Property?>(
        value: property,
        skeleton: const HomeSkeleton(),
        onRetry: () => ref.invalidate(propertiesProvider),
        data: (p) => p == null
            ? const _AwaitingApproval()
            : RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _Header(property: p)),
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
                      sliver: SliverToBoxAdapter(child: _Body()),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(visitorsProvider('upcoming'));
    final inside = ref.watch(visitorsProvider('inside'));
    final waiting = upcoming.value?.where((v) => v.status == VisitorStatus.waiting).toList() ?? [];
    final expected = [
      ...?upcoming.value?.where((v) => v.status == VisitorStatus.expected),
      ...?inside.value,
    ];
    final events = ref.watch(eventsProvider).value ?? [];

    final sections = <Widget>[
        for (final v in waiting) ...[
          const SizedBox(height: AppSpacing.lg),
          _GateRequestCard(visitor: v),
        ],
        const SectionHeader(title: 'Quick actions'),
        const _QuickActions(),
        const _DuesCard(),
        SectionHeader(title: 'Expected & inside', action: 'View all', onAction: () => context.go(Routes.visitors)),
        if (upcoming.isLoading && !upcoming.hasValue)
          const AsyncView(value: AsyncLoading<void>(), compact: true, data: _none)
        else if (upcoming.hasError)
          AsyncView(value: upcoming, compact: true, data: _none, onRetry: () => ref.invalidate(visitorsProvider))
        else if (expected.isEmpty)
          AppCard(child: Text('No visitors expected. Tap "Invite guest" to pre-approve someone.', style: context.text.bodySmall))
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: expected.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (_, i) => _VisitorMini(visitor: expected[i]),
            ),
          ),
        SectionHeader(title: 'Notice board', action: 'See all', onAction: () => context.push(Routes.notices)),
        AsyncView<List<Notice>>(
          value: ref.watch(noticesProvider),
          compact: true,
          onRetry: () => ref.invalidate(noticesProvider),
          data: (notices) => notices.isEmpty
              ? AppCard(child: Text('No notices yet.', style: context.text.bodySmall))
              : Column(children: [
                  for (final n in notices.take(2)) ...[NoticeCard(notice: n), const SizedBox(height: AppSpacing.md)],
                ]),
        ),
        if (events.isNotEmpty) ...[
          SectionHeader(title: 'Upcoming event', action: 'All events', onAction: () => context.push(Routes.events)),
          _EventBanner(event: events.first),
        ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final (i, w) in sections.indexed) w.enter(i)],
    );
  }
}

Widget _none(Object? _) => const SizedBox.shrink();

class _AwaitingApproval extends ConsumerWidget {
  const _AwaitingApproval();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(propertiesProvider).value ?? [];
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(propertiesProvider.future),
        child: ListView(
          padding: AppSpacing.screenAll,
          children: [
            const SizedBox(height: AppSpacing.xxl),
            EmptyState(
              icon: Icons.hourglass_top_rounded,
              title: pending.isEmpty ? 'Join your community' : 'Waiting for approval',
              message: pending.isEmpty
                  ? 'Find your community and unit to get started.'
                  : 'Your community management will review your request. Pull down to refresh.',
            ),
            for (final p in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AppCard(
                  child: Row(
                    children: [
                      const IconBadge(icon: Icons.apartment_rounded),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Text(p.community, style: context.text.titleSmall),
                            Text(p.shortLabel, style: context.text.bodySmall)],
                        ),
                      ),
                      StatusChip(label: p.status, tone: Tone.warning),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => context.push(Routes.joinCommunity),
              icon: const Icon(Icons.add_home_outlined),
              label: Text(pending.isEmpty ? 'Join a community' : 'Join another community'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.property});

  final Property property;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
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
                  Expanded(
                    child: InkWell(
                      onTap: () => showPropertySwitcher(context),
                      borderRadius: AppRadius.fieldRadius,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(property.community, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: context.text.titleSmall?.copyWith(color: Colors.white)),
                                  Text(property.shortLabel, style: context.text.bodySmall?.copyWith(color: Colors.white70)),
                                ],
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(onPressed: () => context.push(Routes.search), icon: const Icon(Icons.search_rounded, color: Colors.white)),
                  IconButton(
                    onPressed: () => context.push(Routes.notifications),
                    icon: Badge(
                      isLabelVisible: unread > 0,
                      label: Text('$unread'),
                      child: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: AppColors.brandGradient),
                      ),
                      child: AppAvatar(name: user.name, imageUrl: user.avatarUrl, size: 50),
                    ).pop(),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_greeting()} 👋', style: context.text.bodyMedium?.copyWith(color: Colors.white70)).enter(1, 0.3),
                          const SizedBox(height: 2),
                          Text(user.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: context.text.headlineMedium?.copyWith(color: Colors.white))
                              .enter(2, 0.3),
                        ],
                      ),
                    ),
                    _SosButton(onTap: () => context.push(Routes.sos))
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scaleXY(begin: 1, end: 1.05, duration: 1400.ms, curve: Curves.easeInOut),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.danger,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sos_rounded, color: Colors.white, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Text('SOS', style: context.text.labelLarge?.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GateRequestCard extends StatelessWidget {
  const _GateRequestCard({required this.visitor});

  final Visitor visitor;

  @override
  Widget build(BuildContext context) {
    final warn = context.palette.warning;
    return AppCard(
      color: warn.withValues(alpha: 0.08),
      borderColor: warn.withValues(alpha: 0.4),
      onTap: () => context.push(Routes.approval(visitor.id)),
      child: Row(
        children: [
          AppAvatar(name: visitor.name, icon: visitor.type.icon, color: warn),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${visitor.type.label} waiting at ${visitor.gate}', style: context.text.labelMedium?.copyWith(color: warn)),
                const SizedBox(height: 2),
                Text(visitor.name, style: context.text.titleSmall),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
            onPressed: () => context.push(Routes.approval(visitor.id)),
            child: const Text('Respond'),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final actions = [
      (Icons.person_add_alt_1_rounded, 'Invite\nguest', context.scheme.primary, () => context.push(Routes.invite)),
      (Icons.cleaning_services_rounded, 'Daily\nhelp', const Color(0xFF7C3AED), () => context.push('${Routes.household}?tab=2')),
      (Icons.family_restroom_rounded, 'My\nhousehold', const Color(0xFF0EA5A4), () => context.push(Routes.household)),
      (Icons.receipt_long_rounded, 'Pay\ndues', p.success, () => context.go(Routes.payments)),
      (Icons.support_agent_rounded, 'Help\ndesk', p.info, () => context.push(Routes.helpdesk)),
      (Icons.child_care_rounded, 'Allow\nkid exit', const Color(0xFFDB2777), () => context.push(Routes.kidExit)),
      (Icons.storefront_rounded, 'Home\nservices', const Color(0xFFEA580C), () => context.push(Routes.homestore)),
      (Icons.contact_emergency_rounded, 'Emergency\ncontacts', p.danger, () => context.push(Routes.emergencyContacts)),
    ];
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xs),
      child: GridView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        // Fixed row height: icon (52) + gap + two label lines + padding.
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: 116),
        children: [
          for (final (i, (icon, label, color, onTap)) in actions.indexed)
            ActionTile(icon: icon, label: label, color: color, onTap: onTap).pop(120 + 45 * i),
        ],
      ),
    );
  }
}

class _DuesCard extends ConsumerWidget {
  const _DuesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(duesSummaryProvider).value;
    final dues = ref.watch(duesProvider).value ?? [];
    if (summary == null || summary.pendingCount == 0) return const SizedBox.shrink();
    final overdue = summary.overdue > 0;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Pressable(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: overdue ? [const Color(0xFFDC2626), const Color(0xFFF97316)] : const [AppColors.primary, Color(0xFF1D9BF0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: AppRadius.cardRadius,
            boxShadow: [
              BoxShadow(color: (overdue ? const Color(0xFFDC2626) : AppColors.primary).withValues(alpha: 0.3),
                  blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: AppRadius.cardRadius,
              onTap: () => context.go(Routes.payments),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(overdue ? 'Overdue dues' : 'Outstanding dues',
                              style: context.text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                          const SizedBox(height: 2),
                          Text(Fmt.money(summary.outstanding, summary.currency),
                              style: context.text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: overdue ? const Color(0xFFDC2626) : AppColors.primary,
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: dues.isEmpty ? null : () => context.push(Routes.pay(dues.map((d) => d.id).toList())),
                      child: const Text('Pay now'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VisitorMini extends StatelessWidget {
  const _VisitorMini({required this.visitor});

  final Visitor visitor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => showVisitorDetails(context, visitor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppAvatar(name: visitor.name, icon: visitor.type.icon, size: 36),
            const Spacer(),
            Text(visitor.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
            const SizedBox(height: 2),
            Text(visitor.status == VisitorStatus.inside ? 'Since ${Fmt.time(visitor.time)}' : Fmt.relative(visitor.time),
                style: context.text.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            StatusChip(label: visitor.status.label, tone: visitor.status.tone),
          ],
        ),
      ),
    );
  }
}

class _EventBanner extends StatelessWidget {
  const _EventBanner({required this.event});

  final CommunityEvent event;

  @override
  Widget build(BuildContext context) {
    final accent = AppAvatar.colorFor(event.title);
    return AppCard(
      onTap: () => context.push(Routes.events),
      child: Row(
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: AppRadius.fieldRadius),
            child: Column(
              children: [
                Text(Fmt.weekday(event.date).toUpperCase(), style: context.text.labelSmall?.copyWith(color: accent)),
                Text('${event.date.day}', style: context.text.headlineSmall?.copyWith(color: accent)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text('${Fmt.time(event.date)} · ${event.venue}', style: context.text.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                Text('${event.attendees} going', style: context.text.labelMedium?.copyWith(color: context.scheme.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
