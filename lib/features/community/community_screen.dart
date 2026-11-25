import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'notices_screens.dart';
import 'polls_screen.dart';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final property = ref.watch(currentPropertyProvider).value;
    final settings = ref.watch(contextProvider).value?.settings ?? const {};
    final activePolls = ref.watch(pollsProvider).value?.where((p) => !p.isClosed).toList() ?? [];

    final modules = [
      (Icons.campaign_rounded, 'Notice board', context.scheme.primary, Routes.notices),
      (Icons.how_to_vote_rounded, 'Polls & surveys', const Color(0xFF7C3AED), Routes.polls),
      (Icons.celebration_rounded, 'Events', const Color(0xFFDB2777), Routes.events),
      if (settings['allow_forum'] != false) (Icons.forum_rounded, 'Forum', const Color(0xFF0EA5A4), Routes.forum),
      (Icons.people_alt_rounded, 'Residents', const Color(0xFF0891B2), Routes.directory),
      (Icons.engineering_rounded, 'Staff', const Color(0xFFCA8A04), '${Routes.directory}?tab=staff'),
      if (settings['allow_classifieds'] != false)
        (Icons.sell_rounded, 'Classifieds', const Color(0xFFEA580C), Routes.classifieds),
      (Icons.storefront_rounded, 'Home store', context.palette.success, Routes.homestore),
      (Icons.local_shipping_rounded, 'Move in / out', const Color(0xFF64748B), Routes.moveRequest),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [const Text('Community'), Text(property?.community ?? '', style: context.text.bodySmall)],
        ),
        actions: [IconButton(onPressed: () => context.push(Routes.search), icon: const Icon(Icons.search_rounded))],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(pollsProvider);
          ref.invalidate(noticesProvider);
          await ref.read(noticesProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
          children: [
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.05,
                children: [
                  for (final (icon, label, color, route) in modules)
                    ActionTile(icon: icon, label: label, color: color, onTap: () => context.push(route)),
                ],
              ),
            ),
            if (activePolls.isNotEmpty) ...[
              SectionHeader(title: 'Active poll', action: 'All polls', onAction: () => context.push(Routes.polls)),
              PollCard(poll: activePolls.first),
            ],
            SectionHeader(title: 'Latest notices', action: 'See all', onAction: () => context.push(Routes.notices)),
            AsyncView<List<Notice>>(
              value: ref.watch(noticesProvider),
              compact: true,
              onRetry: () => ref.invalidate(noticesProvider),
              data: (notices) => Column(
                children: [
                  for (final n in notices.take(3)) ...[NoticeCard(notice: n), const SizedBox(height: AppSpacing.md)],
                  if (notices.isEmpty) AppCard(child: Text('No notices yet.', style: context.text.bodySmall)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
