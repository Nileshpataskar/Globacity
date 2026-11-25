import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/device.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Resident and staff directory. Phone numbers are shown only when the person allows it.
class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Directory'),
          bottom: const TabBar(tabs: [Tab(text: 'Residents'), Tab(text: 'Staff')]),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
                decoration: const InputDecoration(hintText: 'Search by name or unit', prefixIcon: Icon(Icons.search_rounded)),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _PeopleList(provider: residentsProvider, query: _query),
                  _PeopleList(provider: staffProvider, query: _query),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeopleList extends ConsumerWidget {
  const _PeopleList({required this.provider, required this.query});

  final FutureProvider<List<Person>> provider;
  final String query;

  Future<void> _message(BuildContext context, WidgetRef ref, Person p) async {
    final conv = await runAction(context, () => ref.read(actionsProvider).startConversation(p.userId!));
    if (conv != null && context.mounted) context.push(Routes.chat(conv.id, p.name));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<Person>>(
      value: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      data: (all) {
        final people = all
            .where((p) => p.name.toLowerCase().contains(query) || p.subtitle.toLowerCase().contains(query))
            .toList();
        if (people.isEmpty) return const EmptyState(icon: Icons.person_search_rounded, title: 'No matches');
        return ListView.separated(
          padding: AppSpacing.screenAll,
          itemCount: people.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) {
            final p = people[i];
            return AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
              child: Row(
                children: [
                  AppAvatar(name: p.name),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: context.text.titleSmall),
                        Text(p.subtitle, style: context.text.bodySmall),
                        if (p.tag != null) ...[const SizedBox(height: AppSpacing.xs), StatusChip(label: p.tag!)],
                      ],
                    ),
                  ),
                  if (p.canMessage && p.userId != null)
                    IconButton(
                      onPressed: () => _message(context, ref, p),
                      icon: Icon(Icons.chat_bubble_outline_rounded, color: context.scheme.primary),
                    ),
                  if (p.phone != null)
                    IconButton(
                      onPressed: () => Device.call(context, p.phone!),
                      icon: Icon(Icons.call_outlined, color: context.palette.success),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
