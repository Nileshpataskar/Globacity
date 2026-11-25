import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(eventsProvider.future),
        child: AsyncView<List<CommunityEvent>>(
          value: ref.watch(eventsProvider),
          onRetry: () => ref.invalidate(eventsProvider),
          data: (events) => events.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.celebration_outlined, title: 'No upcoming events')])
              : ListView.separated(
                  padding: AppSpacing.screenAll,
                  itemCount: events.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => _EventCard(event: events[i]),
                ),
        ),
      ),
    );
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.event});

  final CommunityEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    final accent = AppAvatar.colorFor(e.title);
    void toggle() => runAction(context, () => ref.read(actionsProvider).rsvp(e.id, !e.going),
        success: e.going ? 'RSVP cancelled' : "You're going!");
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 110,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.fieldRadius),
                  child: Column(
                    children: [
                      Text(Fmt.shortDate(e.date).split(' ').last.toUpperCase(), style: context.text.labelSmall?.copyWith(color: accent)),
                      Text('${e.date.day}', style: context.text.titleLarge?.copyWith(color: Colors.black87)),
                    ],
                  ),
                ),
                const Spacer(),
                StatusChip(label: e.category, tone: Tone.neutral),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: context.text.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(e.description, style: context.text.bodySmall),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 16, color: context.palette.textMuted),
                    const SizedBox(width: AppSpacing.xs),
                    Text('${Fmt.weekday(e.date)}, ${Fmt.time(e.date)}', style: context.text.bodySmall),
                    const SizedBox(width: AppSpacing.md),
                    Icon(Icons.place_outlined, size: 16, color: context.palette.textMuted),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: Text(e.venue, style: context.text.bodySmall, overflow: TextOverflow.ellipsis)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Text('${e.attendees} going', style: context.text.labelMedium?.copyWith(color: context.scheme.primary)),
                    const Spacer(),
                    e.going
                        ? OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                            onPressed: toggle,
                            icon: Icon(Icons.check_rounded, color: context.palette.success),
                            label: const Text('Going'),
                          )
                        : FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: toggle,
                            child: const Text('RSVP')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
