import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class VisitorsScreen extends ConsumerWidget {
  const VisitorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(visitorsProvider('upcoming')).value?.length;
    final inside = ref.watch(visitorsProvider('inside')).value?.length;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Visitors'),
          actions: [
            IconButton(
              tooltip: 'Frequent entries',
              onPressed: () => context.push('${Routes.household}?tab=4'),
              icon: const Icon(Icons.event_repeat_rounded),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: upcoming == null ? 'Upcoming' : 'Upcoming ($upcoming)'),
              Tab(text: inside == null ? 'Inside' : 'Inside ($inside)'),
              const Tab(text: 'History'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'invite',
          onPressed: () => context.push(Routes.invite),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Invite'),
        ),
        body: const TabBarView(
          children: [
            _VisitorList(bucket: 'upcoming', empty: 'No upcoming visitors',
                emptyMessage: 'Pre-approve guests, cabs and deliveries for faster entry.'),
            _VisitorList(bucket: 'inside', empty: 'Nobody inside right now'),
            _VisitorList(bucket: 'history', empty: 'No visitor history yet'),
          ],
        ),
      ),
    );
  }
}

class _VisitorList extends ConsumerWidget {
  const _VisitorList({required this.bucket, required this.empty, this.emptyMessage});

  final String bucket;
  final String empty;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = visitorsProvider(bucket);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(provider.future),
      child: AsyncView<List<Visitor>>(
        value: ref.watch(provider),
        onRetry: () => ref.invalidate(provider),
        data: (visitors) => visitors.isEmpty
            ? ListView(children: [EmptyState(icon: Icons.badge_outlined, title: empty, message: emptyMessage)])
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
                itemCount: visitors.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (_, i) => VisitorTile(visitor: visitors[i]),
              ),
      ),
    );
  }
}

class VisitorTile extends StatelessWidget {
  const VisitorTile({super.key, required this.visitor});

  final Visitor visitor;

  @override
  Widget build(BuildContext context) {
    final v = visitor;
    return AppCard(
      onTap: () => v.status == VisitorStatus.waiting ? context.push(Routes.approval(v.id)) : showVisitorDetails(context, v),
      child: Row(
        children: [
          AppAvatar(name: v.name, icon: v.type.icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.name, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text([v.type.label, if (v.guests > 1) '${v.guests} people', Fmt.dateTime(v.time)].join(' · '),
                    style: context.text.bodySmall),
              ],
            ),
          ),
          StatusChip(label: v.status.label, tone: v.status.tone),
        ],
      ),
    );
  }
}

/// Bottom sheet with visitor details and context actions.
void showVisitorDetails(BuildContext context, Visitor v) {
  showAppSheet(
    context,
    title: v.name,
    child: Consumer(
      builder: (context, ref, _) {
        Future<void> act(String action, String message) async {
          final ok = await runAction(context, () async {
            await ref.read(actionsProvider).visitorAction(v.id, action);
            return true;
          }, success: message);
          if (ok == true && context.mounted) Navigator.pop(context);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              StatusChip(label: v.status.label, tone: v.status.tone),
              const SizedBox(width: AppSpacing.sm),
              StatusChip(label: v.type.label, icon: v.type.icon),
            ]),
            const SizedBox(height: AppSpacing.md),
            InfoRow(icon: Icons.schedule_rounded, label: 'Time', value: Fmt.dateTime(v.time)),
            InfoRow(icon: Icons.door_sliding_outlined, label: 'Gate', value: v.gate),
            if (v.company != null) InfoRow(icon: Icons.business_rounded, label: 'Company', value: v.company!),
            if (v.vehicleNo != null) InfoRow(icon: Icons.directions_car_rounded, label: 'Vehicle', value: v.vehicleNo!),
            if (v.phone != null) InfoRow(icon: Icons.phone_rounded, label: 'Phone', value: v.phone!),
            const SizedBox(height: AppSpacing.lg),
            if (v.status == VisitorStatus.expected) ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push(Routes.pass(v.id));
                },
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('View gate pass'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(onPressed: () => act('cancel', 'Invitation cancelled'), child: const Text('Cancel invitation')),
            ],
            if (v.status == VisitorStatus.inside)
              OutlinedButton.icon(
                onPressed: () => act('mark-exit', '${v.name} marked as exited'),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Mark as exited'),
              ),
          ],
        );
      },
    ),
  );
}
