import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Universal search (server-side) plus quick links to features.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _q = '';
  Timer? _debounce;

  static const _features = [
    (Icons.person_add_alt_1_rounded, 'Invite guest', Routes.invite),
    (Icons.receipt_long_rounded, 'Pay dues', Routes.payments),
    (Icons.support_agent_rounded, 'Help desk', Routes.helpdesk),
    (Icons.campaign_rounded, 'Notice board', Routes.notices),
    (Icons.how_to_vote_rounded, 'Polls', Routes.polls),
    (Icons.celebration_rounded, 'Events', Routes.events),
    (Icons.forum_rounded, 'Forum', Routes.forum),
    (Icons.sell_rounded, 'Classifieds', Routes.classifieds),
    (Icons.storefront_rounded, 'Home services', Routes.homestore),
    (Icons.family_restroom_rounded, 'My household', Routes.household),
    (Icons.sos_rounded, 'SOS', Routes.sos),
    (Icons.local_shipping_rounded, 'Move in / out', Routes.moveRequest),
  ];

  static const _icons = {
    'resident': Icons.person_outline_rounded,
    'staff': Icons.engineering_outlined,
    'daily_help': Icons.cleaning_services_outlined,
    'visitor': Icons.badge_outlined,
    'notice': Icons.campaign_outlined,
    'ticket': Icons.support_agent_rounded,
    'classified': Icons.sell_outlined,
  };

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _go(String route) => route == Routes.payments ? context.go(route) : context.push(route);

  Future<void> _open(SearchResult r) async {
    switch (r.type) {
      case 'resident':
        final conv = await runAction(context, () => ref.read(actionsProvider).startConversation(r.id));
        if (conv != null && mounted) context.push(Routes.chat(conv.id, r.title));
      case 'daily_help':
        context.push(Routes.helper(r.id));
      case 'notice':
        context.push(Routes.notice(r.id));
      case 'ticket':
        context.push(Routes.ticket(r.id));
      case 'visitor':
        context.go(Routes.visitors);
      case 'classified':
        context.push(Routes.classifieds);
      case 'staff':
        context.push('${Routes.directory}?tab=staff');
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = _features.where((f) => f.$2.toLowerCase().contains(_q.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsetsDirectional.only(end: AppSpacing.lg),
          child: TextField(
            autofocus: true,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _q = v.trim()));
            },
            decoration: const InputDecoration(hintText: 'Search people, notices, services…',
                prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
        ),
      ),
      body: _q.length < 2
          ? ListView(
              padding: AppSpacing.screenAll,
              children: [
                Text('Quick links', style: context.text.titleSmall),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final f in _features) ActionChip(avatar: Icon(f.$1, size: 18), label: Text(f.$2), onPressed: () => _go(f.$3)),
                  ],
                ),
              ],
            )
          : AsyncView<List<SearchResult>>(
              value: ref.watch(searchProvider(_q)),
              onRetry: () => ref.invalidate(searchProvider(_q)),
              data: (results) {
                if (results.isEmpty && features.isEmpty) {
                  return EmptyState(icon: Icons.search_off_rounded, title: 'No results for "$_q"');
                }
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  children: [
                    for (final f in features)
                      ListTile(leading: IconBadge(icon: f.$1, size: 40), title: Text(f.$2), subtitle: const Text('Feature'),
                          onTap: () => _go(f.$3)),
                    for (final r in results)
                      ListTile(
                        leading: IconBadge(icon: _icons[r.type] ?? Icons.search_rounded, size: 40),
                        title: Text(r.title),
                        subtitle: Text(r.subtitle),
                        onTap: () => _open(r),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
