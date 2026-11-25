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
import '../../data/models.dart';

/// Waiting / expected / inside visitors, filterable by type (cab, delivery, guest, service).
class GuardVisitorsScreen extends ConsumerStatefulWidget {
  const GuardVisitorsScreen({super.key});

  @override
  ConsumerState<GuardVisitorsScreen> createState() => _GuardVisitorsScreenState();
}

class _GuardVisitorsScreenState extends ConsumerState<GuardVisitorsScreen> {
  VisitorType? _type;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Visitors'),
          bottom: const TabBar(tabs: [Tab(text: 'At gate'), Tab(text: 'Expected'), Tab(text: 'Inside')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'walk-in',
          onPressed: () => context.push(Routes.guardWalkIn),
          icon: const Icon(Icons.person_add_alt_rounded),
          label: const Text('Walk-in'),
        ),
        body: Column(
          children: [
            SizedBox(
              height: 52,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                scrollDirection: Axis.horizontal,
                children: [
                  for (final t in <VisitorType?>[null, VisitorType.delivery, VisitorType.cab, VisitorType.guest, VisitorType.service])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                      child: ChoiceChip(
                        avatar: t == null ? null : Icon(t.icon, size: 16),
                        label: Text(t?.label ?? 'All'),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _List(status: 'waiting', type: _type, empty: 'Nobody waiting at the gate'),
                  _List(status: 'expected', type: _type, empty: 'No pre-approved visitors'),
                  _List(status: 'inside', type: _type, empty: 'No visitors inside'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.status, required this.type, required this.empty});

  final String status;
  final VisitorType? type;
  final String empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = guardVisitorsProvider(status);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(provider.future),
      child: AsyncView<List<Visitor>>(
        value: ref.watch(provider),
        onRetry: () => ref.invalidate(provider),
        data: (all) {
          final items = type == null ? all : all.where((v) => v.type == type).toList();
          if (items.isEmpty) return ListView(children: [EmptyState(icon: Icons.groups_outlined, title: empty)]);
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) => _VisitorCard(visitor: items[i]),
          );
        },
      ),
    );
  }
}

class _VisitorCard extends ConsumerWidget {
  const _VisitorCard({required this.visitor});

  final Visitor visitor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = visitor;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(name: v.name, icon: v.type.icon),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.name, style: context.text.titleSmall),
                    Text([v.unitLabel, v.type.label, if (v.vehicleNo != null) v.vehicleNo!].join(' · '), style: context.text.bodySmall),
                    Text(v.status == VisitorStatus.expected ? 'Expected ${Fmt.dateTime(v.time)}' : Fmt.relative(v.time),
                        style: context.text.labelSmall),
                  ],
                ),
              ),
              StatusChip(label: v.status.label, tone: v.status.tone),
            ],
          ),
          if (v.status == VisitorStatus.inside || (v.phone != null && v.status == VisitorStatus.waiting)) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (v.phone != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: () => Device.call(context, v.phone!),
                      icon: const Icon(Icons.call_rounded, size: 18),
                      label: const Text('Call'),
                    ),
                  ),
                if (v.phone != null && v.status == VisitorStatus.inside) const SizedBox(width: AppSpacing.sm),
                if (v.status == VisitorStatus.inside)
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: () => runAction(context, () => ref.read(guardActionsProvider).checkOutVisitor(v.id),
                          success: '${v.name} checked out'),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Check out'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
