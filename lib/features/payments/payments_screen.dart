import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(duesSummaryProvider);
    final dues = ref.watch(duesProvider).value ?? [];
    final property = ref.watch(currentPropertyProvider).value;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            const SliverAppBar(pinned: true, title: Text('Payments')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: context.palette.heroGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: AppRadius.cardRadius,
                  ),
                  child: summary.when(
                    loading: () => const SizedBox(height: 96, child: Center(child: CircularProgressIndicator(color: Colors.white))),
                    error: (e, _) => Text(e.toString(), style: context.text.bodyMedium?.copyWith(color: Colors.white)),
                    data: (s) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total outstanding · ${property?.shortLabel ?? ''}',
                            style: context.text.bodySmall?.copyWith(color: Colors.white70)),
                        const SizedBox(height: AppSpacing.xs),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(Fmt.money(s.outstanding, s.currency),
                              style: context.text.displaySmall?.copyWith(color: Colors.white)),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.pendingCount == 0
                                    ? "You're all caught up!"
                                    : '${s.pendingCount} pending${s.nextDue != null ? ' · next due ${Fmt.shortDate(s.nextDue!)}' : ''}',
                                style: context.text.bodySmall?.copyWith(color: Colors.white),
                              ),
                            ),
                            if (dues.isNotEmpty)
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: context.palette.heroGradient.first,
                                  minimumSize: const Size(0, 42),
                                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                                ),
                                onPressed: () => context.push(Routes.pay(dues.map((d) => d.id).toList())),
                                child: const Text('Pay all'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SliverPersistentHeader(pinned: true, delegate: _TabsHeader()),
          ],
          body: const TabBarView(children: [_DuesTab(), _StatementTab(), _HistoryTab()]),
        ),
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  const _TabsHeader();

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ColoredBox(
        color: context.theme.scaffoldBackgroundColor,
        child: const TabBar(tabs: [Tab(text: 'Dues'), Tab(text: 'Statement'), Tab(text: 'History')]),
      );

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}

class _DuesTab extends ConsumerWidget {
  const _DuesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(duesSummaryProvider);
        ref.invalidate(duesProvider);
        await ref.read(duesProvider.future);
      },
      child: AsyncView<List<Due>>(
        value: ref.watch(duesProvider),
        onRetry: () => ref.invalidate(duesProvider),
        data: (dues) => dues.isEmpty
            ? ListView(children: const [
                EmptyState(icon: Icons.verified_rounded, title: 'No pending dues', message: 'All payments for this unit are up to date.'),
              ])
            : ListView.separated(
                padding: AppSpacing.screenAll,
                itemCount: dues.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (_, i) => _DueCard(due: dues[i]),
              ),
      ),
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({required this.due});

  final Due due;

  @override
  Widget build(BuildContext context) {
    final d = due;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: Icons.receipt_long_rounded, color: d.isOverdue ? context.palette.danger : context.scheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title, style: context.text.titleSmall),
                    Text([d.period, d.taxLabel].where((e) => e.isNotEmpty).join(' · '), style: context.text.bodySmall),
                  ],
                ),
              ),
              Text(Fmt.money(d.amount, d.currency), style: context.text.titleMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Flexible(
                child: StatusChip(
                  label: d.isOverdue ? 'Overdue since ${Fmt.shortDate(d.dueDate)}' : 'Due ${Fmt.date(d.dueDate)}',
                  tone: d.isOverdue ? Tone.danger : Tone.warning,
                ),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
                onPressed: () => context.push(Routes.pay([d.id])),
                child: const Text('Pay'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatementTab extends ConsumerWidget {
  const _StatementTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(statementProvider.future),
      child: AsyncView<Statement>(
        value: ref.watch(statementProvider),
        onRetry: () => ref.invalidate(statementProvider),
        data: (s) => ListView(
          padding: AppSpacing.screenAll,
          children: [
            Row(
              children: [
                Expanded(child: Text('Statement of account', style: context.text.titleSmall)),
                Text('Balance ${Fmt.money(s.closingBalance, s.currency)}', style: context.text.labelMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (s.entries.isEmpty)
              const EmptyState(icon: Icons.receipt_outlined, title: 'No transactions yet')
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, e) in s.entries.reversed.indexed) ...[
                      if (i > 0) const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                      ListTile(
                        title: Text(e.description),
                        subtitle: Text('${Fmt.date(e.date)} · Balance ${Fmt.money(e.balance, s.currency)}'),
                        trailing: Text(
                          e.credit > 0 ? '- ${Fmt.money(e.credit, s.currency)}' : '+ ${Fmt.money(e.debit, s.currency)}',
                          style: context.text.titleSmall?.copyWith(
                              color: e.credit > 0 ? context.palette.success : context.scheme.onSurface),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(paymentsProvider.future),
      child: AsyncView<List<Payment>>(
        value: ref.watch(paymentsProvider),
        onRetry: () => ref.invalidate(paymentsProvider),
        data: (payments) => payments.isEmpty
            ? ListView(children: const [EmptyState(icon: Icons.history_rounded, title: 'No payments yet')])
            : ListView.separated(
                padding: AppSpacing.screenAll,
                itemCount: payments.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (_, i) {
                  final p = payments[i];
                  return AppCard(
                    onTap: () => showAppSheet(
                      context,
                      title: 'Payment receipt',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InfoRow(icon: Icons.receipt_rounded, label: 'For', value: p.title),
                          InfoRow(icon: Icons.payments_outlined, label: 'Amount', value: Fmt.money(p.amount, p.currency)),
                          InfoRow(icon: Icons.calendar_today_rounded, label: 'Date', value: Fmt.dateTime(p.date)),
                          InfoRow(icon: Icons.credit_card_rounded, label: 'Method', value: p.method),
                          InfoRow(icon: Icons.tag_rounded, label: 'Reference', value: p.reference),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconBadge(icon: Icons.check_circle_rounded, color: context.palette.success),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.title, style: context.text.titleSmall),
                              Text('${Fmt.date(p.date)} · ${p.method}', style: context.text.bodySmall),
                            ],
                          ),
                        ),
                        Text(Fmt.money(p.amount, p.currency), style: context.text.titleSmall),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
