import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/guard.dart';
import 'walk_in_screen.dart';

/// Resident / vehicle directory for the gate.
class GuardDirectoryScreen extends ConsumerStatefulWidget {
  const GuardDirectoryScreen({super.key});

  @override
  ConsumerState<GuardDirectoryScreen> createState() => _GuardDirectoryScreenState();
}

class _GuardDirectoryScreenState extends ConsumerState<GuardDirectoryScreen> {
  String _q = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resident directory')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
            child: TextField(
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _q = v.trim()));
              },
              decoration: const InputDecoration(hintText: 'Unit, resident name or vehicle plate', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: _q.isEmpty
                ? const EmptyState(icon: Icons.manage_search_rounded, title: 'Search residents',
                    message: 'Find a unit to call residents or verify a vehicle.')
                : AsyncView<List<DirectoryEntry>>(
                    value: ref.watch(guardDirectoryProvider(_q)),
                    onRetry: () => ref.invalidate(guardDirectoryProvider(_q)),
                    data: (rows) => rows.isEmpty
                        ? const EmptyState(icon: Icons.search_off_rounded, title: 'No matches')
                        : ListView.separated(
                            padding: AppSpacing.screenAll,
                            itemCount: rows.length,
                            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              return AppCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      const IconBadge(icon: Icons.apartment_rounded, size: 38),
                                      const SizedBox(width: AppSpacing.md),
                                      Expanded(child: Text(r.unitLabel, style: context.text.titleSmall)),
                                    ]),
                                    if (r.residents.isEmpty)
                                      Padding(padding: const EdgeInsets.only(top: AppSpacing.sm),
                                          child: Text('No registered residents', style: context.text.bodySmall)),
                                    for (final p in r.residents)
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        leading: AppAvatar(name: p.name, size: 32),
                                        title: Text(p.name),
                                        subtitle: Text(p.role),
                                        trailing: IconButton(
                                          onPressed: () => callResident(context, p.phone),
                                          icon: Icon(Icons.call_rounded,
                                              color: p.phone == null ? context.palette.textMuted : context.palette.success),
                                        ),
                                      ),
                                    if (r.vehicles.isNotEmpty)
                                      Wrap(spacing: AppSpacing.sm, children: [
                                        for (final v in r.vehicles) StatusChip(label: v, icon: Icons.directions_car_rounded),
                                      ]),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Children currently allowed to leave unaccompanied.
class GuardKidExitsScreen extends ConsumerWidget {
  const GuardKidExitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kid exit permissions')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(guardKidExitsProvider.future),
        child: AsyncView<List<KidExit>>(
          value: ref.watch(guardKidExitsProvider),
          onRetry: () => ref.invalidate(guardKidExitsProvider),
          data: (items) => items.isEmpty
              ? ListView(children: const [
                  EmptyState(icon: Icons.child_care_rounded, title: 'No active permissions',
                      message: 'Children may not leave alone unless a parent allows it.'),
                ])
              : ListView.separated(
                  padding: AppSpacing.screenAll,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) {
                    final k = items[i];
                    return AppCard(
                      child: Row(
                        children: [
                          IconBadge(icon: Icons.child_care_rounded, color: context.palette.success),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(k.children.join(', '), style: context.text.titleSmall),
                                Text(k.unitLabel, style: context.text.bodySmall),
                                if (k.note.isNotEmpty) Text(k.note, style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          StatusChip(label: 'Until ${Fmt.time(k.until)}', tone: Tone.success),
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

/// Daily help currently inside, with check-out.
class GuardHelpersScreen extends ConsumerWidget {
  const GuardHelpersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily help inside')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(guardHelpersInsideProvider.future),
        child: AsyncView<List<HelperInside>>(
          value: ref.watch(guardHelpersInsideProvider),
          onRetry: () => ref.invalidate(guardHelpersInsideProvider),
          data: (items) => items.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.cleaning_services_outlined, title: 'No daily help inside')])
              : ListView.separated(
                  padding: AppSpacing.screenAll,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) {
                    final h = items[i];
                    return AppCard(
                      child: Row(
                        children: [
                          AppAvatar(name: h.name),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(h.name, style: context.text.titleSmall),
                                Text([h.role, if (h.since != null) 'since ${Fmt.time(h.since!)}'].join(' · '), style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: () => runAction(context, () => ref.read(guardActionsProvider).checkOutHelper(h.id),
                                success: '${h.name} checked out'),
                            child: const Text('Check out'),
                          ),
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
