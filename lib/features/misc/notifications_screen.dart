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

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  /// Deep link from a notification's data payload.
  void _open(BuildContext context, AppNotification n) {
    final d = n.data;
    final route = switch (d) {
      {'visitor_id': final String id, 'action': 'respond'} => Routes.approval(id),
      {'ticket_id': final String id} => Routes.ticket(id),
      {'notice_id': final String id} => Routes.notice(id),
      {'post_id': final String id} => Routes.forumPost(id),
      {'helper_id': final String id} => Routes.helper(id),
      {'invoice_id': _} || {'payment_id': _} => Routes.payments,
      {'visitor_id': _} => Routes.visitors,
      {'event_id': _} => Routes.events,
      {'poll_id': _} => Routes.polls,
      _ => null,
    };
    if (route == null) return;
    route == Routes.payments || route == Routes.visitors ? context.go(route) : context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => runAction(context, () => ref.read(actionsProvider).markAllNotificationsRead()),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(notificationsProvider.future),
        child: AsyncView<List<AppNotification>>(
          value: ref.watch(notificationsProvider),
          onRetry: () => ref.invalidate(notificationsProvider),
          data: (items) => items.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.notifications_none_rounded, title: "You're all caught up")])
              : ListView.separated(
                  padding: AppSpacing.screenAll,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final n = items[i];
                    final c = n.tone.resolve(context);
                    return AppCard(
                      onTap: () => _open(context, n),
                      color: n.read ? null : context.scheme.primary.withValues(alpha: 0.04),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconBadge(icon: n.icon, color: c, size: 40),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(child: Text(n.title, style: context.text.titleSmall)),
                                  Text(Fmt.relative(n.time), style: context.text.bodySmall),
                                ]),
                                if (n.body.isNotEmpty) ...[const SizedBox(height: 2), Text(n.body, style: context.text.bodySmall)],
                              ],
                            ),
                          ),
                          if (!n.read) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6),
                                decoration: BoxDecoration(color: context.scheme.primary, shape: BoxShape.circle)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
