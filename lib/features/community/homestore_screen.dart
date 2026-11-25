import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Local services marketplace listed by community management.
class HomestoreScreen extends ConsumerStatefulWidget {
  const HomestoreScreen({super.key});

  @override
  ConsumerState<HomestoreScreen> createState() => _HomestoreScreenState();
}

class _HomestoreScreenState extends ConsumerState<HomestoreScreen> {
  String? _category;

  static const _icons = {
    'Cleaning': Icons.cleaning_services_rounded,
    'AC Repair': Icons.ac_unit_rounded,
    'Plumbing': Icons.plumbing_rounded,
    'Laundry': Icons.local_laundry_service_rounded,
    'Pest Control': Icons.pest_control_rounded,
    'Grocery': Icons.shopping_basket_rounded,
  };

  void _book(ServiceVendor v) {
    final now = DateTime.now();
    final slots = [
      ('Today 4–6 PM', DateTime(now.year, now.month, now.day, 16)),
      ('Today 6–8 PM', DateTime(now.year, now.month, now.day, 18)),
      ('Tomorrow 9–11 AM', DateTime(now.year, now.month, now.day + 1, 9)),
      ('Tomorrow 2–4 PM', DateTime(now.year, now.month, now.day + 1, 14)),
    ].where((s) => s.$2.isAfter(now)).toList();
    var slot = 0;
    final notes = TextEditingController();
    showAppSheet(
      context,
      title: 'Book ${v.name}',
      child: StatefulBuilder(
        builder: (sheetContext, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose a slot', style: sheetContext.text.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < slots.length; i++)
                  ChoiceChip(label: Text(slots[i].$1), selected: slot == i, onSelected: (_) => setSheet(() => slot = i)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(hintText: 'Notes for the provider (optional)')),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () async {
                final ok = await runAction(sheetContext, () async {
                  await ref.read(actionsProvider).bookService(v.id, slots[slot].$2, notes.text);
                  return true;
                }, success: 'Booking requested for ${slots[slot].$1}');
                if (ok == true && sheetContext.mounted) Navigator.pop(sheetContext);
              },
              child: Text(v.priceFrom == 0 ? 'Request booking' : 'Request · from ${Fmt.money(v.priceFrom, v.currency)}'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home services')),
      body: AsyncView<List<ServiceVendor>>(
        value: ref.watch(vendorsProvider),
        onRetry: () => ref.invalidate(vendorsProvider),
        data: (all) {
          final categories = {for (final v in all) v.category}.toList();
          final vendors = all.where((v) => _category == null || v.category == _category).toList();
          return ListView(
            padding: AppSpacing.screenAll,
            children: [
              if (categories.isNotEmpty)
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1.1,
                  children: [
                    for (final label in categories)
                      AppCard(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        borderColor: _category == label ? context.scheme.primary : null,
                        color: _category == label ? context.scheme.primary.withValues(alpha: 0.06) : null,
                        onTap: () => setState(() => _category = _category == label ? null : label),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconBadge(icon: _icons[label] ?? Icons.storefront_rounded, color: AppAvatar.colorFor(label), size: 40),
                            const SizedBox(height: AppSpacing.sm),
                            Text(label, style: context.text.labelMedium?.copyWith(color: context.scheme.onSurface), textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                  ],
                ),
              SectionHeader(title: _category ?? 'Trusted by your neighbours'),
              if (vendors.isEmpty) const EmptyState(icon: Icons.storefront_outlined, title: 'No services listed yet'),
              for (final v in vendors) ...[
                AppCard(
                  child: Row(
                    children: [
                      AppAvatar(name: v.name, size: 48),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.name, style: context.text.titleSmall),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (v.rating > 0) ...[
                                  const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                                  Text(' ${v.rating.toStringAsFixed(1)}  ·  ', style: context.text.labelMedium),
                                ],
                                Flexible(
                                  child: Text([v.category, if (v.eta.isNotEmpty) v.eta].join('  ·  '),
                                      style: context.text.bodySmall, overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(v.priceFrom == 0 ? 'Free delivery' : 'From ${Fmt.money(v.priceFrom, v.currency)}',
                                style: context.text.labelMedium?.copyWith(color: context.scheme.primary)),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                        onPressed: () => _book(v),
                        child: const Text('Book'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        },
      ),
    );
  }
}
