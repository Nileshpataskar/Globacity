import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
              ? ListView(children: const [
                  EmptyState(icon: Icons.how_to_vote_outlined, title: 'No polls right now',
                      message: 'When your committee asks for opinions, you can vote here.'),
                ])
              : ListView.separated(
                  padding: AppSpacing.screenAll,
                  itemCount: polls.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => PollCard(poll: polls[i]).enter(i),
                ),
        ),
      ),
    );
  }
}

/// A poll: tap an option to vote; your choice highlights instantly and the results animate in.
class PollCard extends ConsumerStatefulWidget {
  const PollCard({super.key, required this.poll});

  final Poll poll;

  @override
  ConsumerState<PollCard> createState() => _PollCardState();
}

class _PollCardState extends ConsumerState<PollCard> {
  int? _myVote; // optimistic vote until the server confirms
  bool _saving = false;

  Poll get poll => widget.poll;

  @override
  void didUpdateWidget(PollCard old) {
    super.didUpdateWidget(old);
    if (!_saving) _myVote = null;
  }

  Future<void> _vote(int optionId) async {
    HapticFeedback.selectionClick();
    setState(() {
      _myVote = optionId;
      _saving = true;
    });
    try {
      await ref.read(actionsProvider).vote(poll.id, optionId);
      if (mounted) context.showSnack('Thanks for voting!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _myVote = null);
      context.showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myVote = _myVote ?? poll.myVote;
    final voted = myVote != null;
    final showResults = poll.isClosed || voted;
    // Include an optimistic vote in the numbers until the refreshed poll arrives.
    final optimistic = _myVote != null && poll.myVote == null;
    final total = poll.totalVotes + (optimistic ? 1 : 0);
    double pct(PollOption o) => total == 0 ? 0 : (o.votes + (optimistic && o.id == _myVote ? 1 : 0)) / total;

    final status = poll.isClosed
        ? 'Voting closed'
        : 'Closes ${Fmt.relative(poll.endsAt)}';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(label: status, tone: poll.isClosed ? Tone.neutral : Tone.success,
                  icon: poll.isClosed ? Icons.lock_outline_rounded : Icons.schedule_rounded),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text('$total ${total == 1 ? 'vote' : 'votes'}', key: ValueKey(total), style: context.text.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(poll.question, style: context.text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              poll.isClosed
                  ? (voted ? 'Final results · your vote is marked' : 'Final results')
                  : voted
                      ? 'You voted · results so far'
                      : 'Tap an option to vote',
              key: ValueKey('$voted${poll.isClosed}'),
              style: context.text.bodySmall?.copyWith(color: voted ? context.palette.success : context.palette.textMuted),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final o in poll.options)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _OptionTile(
                label: o.label,
                mine: myVote == o.id,
                showResults: showResults,
                percent: pct(o),
                onTap: showResults || _saving ? null : () => _vote(o.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.label, required this.mine, required this.showResults, required this.percent, this.onTap});

  final String label;
  final bool mine;
  final bool showResults;
  final double percent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.scheme.primary;
    final c = mine ? primary : context.palette.textMuted;
    return Pressable(
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.fieldRadius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 48,
            decoration: BoxDecoration(
              color: context.palette.surfaceAlt,
              borderRadius: AppRadius.fieldRadius,
              border: Border.all(color: mine ? primary : context.palette.border, width: mine ? 1.6 : 1),
            ),
            child: ClipRRect(
              borderRadius: AppRadius.fieldRadius,
              child: Stack(
                children: [
                  // Result bar grows in once results are shown.
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: showResults ? percent.clamp(0, 1) : 0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => FractionallySizedBox(
                      widthFactor: v,
                      child: Container(color: c.withValues(alpha: mine ? 0.18 : 0.12)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Row(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Icon(
                            mine ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            key: ValueKey(mine),
                            size: 20,
                            color: mine ? primary : context.palette.textMuted,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(label,
                              style: context.text.bodyMedium?.copyWith(fontWeight: mine ? FontWeight.w700 : FontWeight.w500)),
                        ),
                        if (showResults)
                          Text('${(percent * 100).round()}%', style: context.text.titleSmall)
                              .animate()
                              .fadeIn(duration: 300.ms),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
