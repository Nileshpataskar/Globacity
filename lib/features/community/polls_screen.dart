import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class PollsScreen extends ConsumerWidget {
  const PollsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Polls & surveys')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pollsProvider.future),
        child: AsyncView<List<Poll>>(
          value: ref.watch(pollsProvider),
          onRetry: () => ref.invalidate(pollsProvider),
          data: (polls) => polls.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.how_to_vote_outlined, title: 'No polls yet')])
              : ListView.separated(
                  padding: AppSpacing.screenAll,
                  itemCount: polls.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => PollCard(poll: polls[i]),
                ),
        ),
      ),
    );
  }
}

class PollCard extends ConsumerWidget {
  const PollCard({super.key, required this.poll});

  final Poll poll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showResults = poll.isClosed || poll.myVote != null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(label: poll.isClosed ? 'Closed' : 'Ends ${Fmt.relative(poll.endsAt)}',
                  tone: poll.isClosed ? Tone.neutral : Tone.success),
              const Spacer(),
              Text('${poll.totalVotes} votes', style: context.text.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(poll.question, style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          for (final o in poll.options)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: showResults
                  ? _ResultBar(option: o, mine: poll.myVote == o.id)
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), alignment: AlignmentDirectional.centerStart),
                      onPressed: () => runAction(context, () => ref.read(actionsProvider).vote(poll.id, o.id),
                          success: 'Vote recorded'),
                      child: Text(o.label),
                    ),
            ),
        ],
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({required this.option, required this.mine});

  final PollOption option;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final pct = option.percent / 100;
    final c = mine ? context.scheme.primary : context.palette.textMuted;
    return ClipRRect(
      borderRadius: AppRadius.fieldRadius,
      child: Stack(
        children: [
          Container(height: 44, color: context.palette.surfaceAlt),
          FractionallySizedBox(widthFactor: pct.clamp(0, 1), child: Container(height: 44, color: c.withValues(alpha: 0.18))),
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  if (mine) ...[Icon(Icons.check_circle_rounded, size: 16, color: c), const SizedBox(width: AppSpacing.xs)],
                  Expanded(child: Text(option.label, style: context.text.bodyMedium?.copyWith(fontWeight: mine ? FontWeight.w600 : null))),
                  Text('${option.percent.round()}%', style: context.text.titleSmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
