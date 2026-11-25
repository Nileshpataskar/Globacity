import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/device.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Daily help profile with gate code, attendance calendar and ratings.
class HelperDetailScreen extends ConsumerWidget {
  const HelperDetailScreen({super.key, required this.helperId});

  final String helperId;

  void _rate(BuildContext context, WidgetRef ref, DailyHelp h) {
    var stars = 5;
    final comment = TextEditingController();
    showAppSheet(
      context,
      title: 'Rate ${h.name}',
      child: StatefulBuilder(
        builder: (sheetContext, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: RatingStars(rating: stars.toDouble(), size: 40, onChanged: (v) => setState(() => stars = v))),
            const SizedBox(height: AppSpacing.lg),
            TextField(controller: comment, maxLines: 3, decoration: const InputDecoration(hintText: 'Share your experience (optional)')),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () async {
                final ok = await runAction(sheetContext, () async {
                  await ref.read(actionsProvider).reviewHelper(h.id, stars, comment.text.trim());
                  return true;
                });
                if (ok == true && sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                  context.showSnack('Thanks for your feedback');
                }
              },
              child: const Text('Submit rating'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily help'),
        actions: [
          IconButton(
            tooltip: 'Remove from my unit',
            onPressed: () async {
              final ok = await runAction(context, () async {
                await ref.read(actionsProvider).removeDailyHelp(helperId);
                return true;
              }, success: 'Removed from your unit');
              if (ok == true && context.mounted) context.pop();
            },
            icon: const Icon(Icons.person_remove_outlined),
          ),
        ],
      ),
      body: AsyncView<DailyHelp>(
        value: ref.watch(helperProvider(helperId)),
        onRetry: () => ref.invalidate(helperProvider(helperId)),
        data: (h) => ListView(
          padding: AppSpacing.screenAll,
          children: [
            AppCard(
              child: Column(
                children: [
                  AppAvatar(name: h.name, size: 84),
                  const SizedBox(height: AppSpacing.md),
                  Text(h.name, style: context.text.titleLarge),
                  Text(h.role, style: context.text.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RatingStars(rating: h.rating),
                      const SizedBox(width: AppSpacing.xs),
                      Text(h.reviewsCount == 0 ? 'No ratings yet' : '${h.rating.toStringAsFixed(1)} (${h.reviewsCount})',
                          style: context.text.bodySmall),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  StatusChip(
                    label: h.isInside
                        ? 'Inside since ${Fmt.time(h.lastEntry!)}'
                        : (h.lastEntry != null ? 'Last seen ${Fmt.relative(h.lastEntry!)}' : 'Not checked in'),
                    tone: h.isInside ? Tone.success : Tone.neutral,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    onPressed: () => Device.call(context, h.phone),
                    icon: const Icon(Icons.call_rounded),
                    label: Text(h.phone),
                  ),
                ],
              ),
            ),
            const SectionHeader(title: 'Details'),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Column(
                children: [
                  InfoRow(icon: Icons.password_rounded, label: 'Gate code', value: h.passCode),
                  InfoRow(icon: Icons.schedule_rounded, label: 'Timings', value: h.timing),
                  InfoRow(icon: Icons.home_work_outlined, label: 'Works in', value: '${h.homesServed} ${h.homesServed == 1 ? 'home' : 'homes'}'),
                  InfoRow(icon: Icons.event_available_rounded, label: 'Registered', value: Fmt.date(h.since)),
                  InfoRow(icon: Icons.verified_user_outlined, label: 'ID verification', value: h.idVerified ? 'Verified' : 'Pending'),
                ],
              ),
            ),
            SectionHeader(title: 'Attendance · ${Fmt.month(DateTime.now())}'),
            AsyncView<AttendanceMonth>(
              value: ref.watch(helperAttendanceProvider(helperId)),
              compact: true,
              data: (a) => _AttendanceCalendar(present: a.presentDays),
            ),
            SectionHeader(title: 'Reviews', action: 'Rate', onAction: () => _rate(context, ref, h)),
            AsyncView<List<Review>>(
              value: ref.watch(helperReviewsProvider(helperId)),
              compact: true,
              data: (reviews) => reviews.isEmpty
                  ? AppCard(child: Text('Be the first to rate ${h.name.split(' ').first}.', style: context.text.bodySmall))
                  : Column(
                      children: [
                        for (final r in reviews) ...[
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    AppAvatar(name: r.author, size: 32),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(child: Text('${r.author} · ${r.unit}', style: context.text.titleSmall)),
                                    RatingStars(rating: r.rating.toDouble(), size: 14),
                                  ],
                                ),
                                if (r.comment.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(r.comment, style: context.text.bodyMedium),
                                ],
                                const SizedBox(height: AppSpacing.xs),
                                Text(Fmt.relative(r.date), style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _AttendanceCalendar extends StatelessWidget {
  const _AttendanceCalendar({required this.present});

  final Set<int> present;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final leading = first.weekday % 7; // Sunday-first grid
    final absent = now.day - present.where((d) => d <= now.day).length;

    Widget legend(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: context.text.bodySmall),
          ],
        );

    return AppCard(
      child: Column(
        children: [
          Row(children: [
            for (final d in ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Expanded(child: Center(child: Text(d, style: context.text.labelSmall))),
          ]),
          const SizedBox(height: AppSpacing.sm),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (var i = 0; i < leading; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d++)
                Builder(builder: (context) {
                  final future = d > now.day;
                  final c = future ? null : (present.contains(d) ? context.palette.success : context.palette.danger);
                  return Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c?.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: d == now.day ? Border.all(color: context.scheme.primary, width: 1.5) : null,
                    ),
                    child: Text('$d', style: context.text.labelMedium?.copyWith(color: c ?? context.palette.textMuted)),
                  );
                }),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [legend(context.palette.success, 'Present · ${present.length}'),
              legend(context.palette.danger, 'Absent · $absent')],
          ),
        ],
      ),
    );
  }
}
