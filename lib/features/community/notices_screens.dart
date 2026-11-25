import '../../core/utils/device.dart';
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

class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.notice});

  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final n = notice;
    return AppCard(
      onTap: () => context.push(Routes.notice(n.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    StatusChip(label: n.category, tone: Tone.primary),
                    if (n.pinned) const StatusChip(label: 'Pinned', tone: Tone.warning, icon: Icons.push_pin_rounded),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(Fmt.relative(n.date), style: context.text.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(n.title, style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

class NoticesScreen extends ConsumerStatefulWidget {
  const NoticesScreen({super.key});

  @override
  ConsumerState<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends ConsumerState<NoticesScreen> {
  String _category = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notice board')),
      body: AsyncView<List<Notice>>(
        value: ref.watch(noticesProvider),
        onRetry: () => ref.invalidate(noticesProvider),
        data: (all) {
          final categories = ['All', ...{for (final n in all) n.category}];
          final notices = _category == 'All' ? all : all.where((n) => n.category == _category).toList();
          return Column(
            children: [
              SizedBox(
                height: 48,
                child: ListView.separated(
                  padding: AppSpacing.screen,
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (_, i) => ChoiceChip(
                    label: Text(categories[i]),
                    selected: _category == categories[i],
                    onSelected: (_) => setState(() => _category = categories[i]),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => ref.refresh(noticesProvider.future),
                  child: notices.isEmpty
                      ? ListView(children: const [EmptyState(icon: Icons.campaign_outlined, title: 'No notices')])
                      : ListView.separated(
                          padding: AppSpacing.screenAll,
                          itemCount: notices.length,
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                          itemBuilder: (_, i) => NoticeCard(notice: notices[i]),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class NoticeDetailScreen extends ConsumerWidget {
  const NoticeDetailScreen({super.key, required this.noticeId});

  final String noticeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView<Notice>(
        value: ref.watch(noticeProvider(noticeId)),
        onRetry: () => ref.invalidate(noticeProvider(noticeId)),
        data: (n) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
          children: [
            Row(children: [StatusChip(label: n.category, tone: Tone.primary)]),
            const SizedBox(height: AppSpacing.md),
            Text(n.title, style: context.text.headlineSmall),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                AppAvatar(name: n.author, size: 36),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(n.author, style: context.text.titleSmall), Text(Fmt.dateTime(n.date), style: context.text.bodySmall)],
                  ),
                ),
                IconButton(
                  onPressed: () => Device.share(context, '${n.title}\n\n${n.body}', subject: n.title),
                  icon: const Icon(Icons.share_outlined),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(n.body, style: context.text.bodyLarge),
          ],
        ),
      ),
    );
  }
}
