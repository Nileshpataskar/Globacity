import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class ClassifiedsScreen extends ConsumerStatefulWidget {
  const ClassifiedsScreen({super.key});

  @override
  ConsumerState<ClassifiedsScreen> createState() => _ClassifiedsScreenState();
}

class _ClassifiedsScreenState extends ConsumerState<ClassifiedsScreen> {
  String _category = 'All';

  static const _icons = {
    'Furniture': Icons.chair_rounded,
    'Electronics': Icons.devices_rounded,
    'Kids': Icons.toys_rounded,
    'Other': Icons.category_rounded,
  };

  void _post() {
    final title = TextEditingController();
    final price = TextEditingController();
    final desc = TextEditingController();
    var category = 'Furniture';
    XFile? photo;
    showAppSheet(
      context,
      title: 'Post an ad',
      child: StatefulBuilder(
        builder: (sheetContext, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PhotoPickerRow(photos: [?photo], max: 1, onChanged: (p) => setSheet(() => photo = p.isEmpty ? null : p.first)),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: 'Price (${Fmt.currency})'),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final c in _icons.keys)
                  ChoiceChip(label: Text(c), selected: category == c, onSelected: (_) => setSheet(() => category = c)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true)),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty || price.text.isEmpty) return;
                final ok = await runAction(sheetContext, () async {
                  await ref.read(actionsProvider)
                      .createClassified(title.text.trim(), price.text, category, desc.text.trim(), image: photo);
                  return true;
                });
                if (ok == true && sheetContext.mounted) Navigator.pop(sheetContext);
              },
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
  }

  void _details(Classified c) {
    final mine = c.sellerId == ref.read(userProvider).id;
    showAppSheet(
      context,
      title: c.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.imageUrl != null) ...[
            ClipRRect(borderRadius: AppRadius.cardRadius,
                child: Image.network(c.imageUrl!, height: 200, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(Fmt.money(c.price, c.currency), style: context.text.headlineSmall?.copyWith(color: context.scheme.primary)),
          const SizedBox(height: AppSpacing.md),
          if (c.description.isNotEmpty) Text(c.description, style: context.text.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          InfoRow(icon: Icons.person_outline_rounded, label: 'Seller', value: '${c.seller} · ${c.unit}'),
          InfoRow(icon: Icons.category_outlined, label: 'Category', value: c.category),
          InfoRow(icon: Icons.schedule_rounded, label: 'Posted', value: Fmt.relative(c.posted)),
          const SizedBox(height: AppSpacing.lg),
          Builder(
            builder: (sheetContext) => mine
                ? OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await runAction(sheetContext, () async {
                        await ref.read(actionsProvider).markSold(c.id);
                        return true;
                      }, success: 'Marked as sold');
                      if (ok == true && sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.sell_outlined),
                    label: const Text('Mark as sold'),
                  )
                : FilledButton.icon(
                    onPressed: () async {
                      final conv = await runAction(sheetContext, () => ref.read(actionsProvider).startConversation(c.sellerId));
                      if (conv == null || !sheetContext.mounted) return;
                      Navigator.pop(sheetContext);
                      if (mounted) context.push(Routes.chat(conv.id, c.seller));
                    },
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Message seller'),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Classifieds')),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'ad', onPressed: _post, icon: const Icon(Icons.add_rounded), label: const Text('Sell')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              padding: AppSpacing.screen,
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in ['All', ..._icons.keys])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                    child: ChoiceChip(label: Text(c), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(classifiedsProvider.future),
              child: AsyncView<List<Classified>>(
                value: ref.watch(classifiedsProvider),
                onRetry: () => ref.invalidate(classifiedsProvider),
                data: (all) {
                  final items = _category == 'All' ? all : all.where((c) => c.category == _category).toList();
                  if (items.isEmpty) {
                    return ListView(children: const [EmptyState(icon: Icons.sell_outlined, title: 'Nothing listed yet')]);
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 96),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220, mainAxisSpacing: AppSpacing.md, crossAxisSpacing: AppSpacing.md, childAspectRatio: 0.72),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final c = items[i];
                      final accent = AppAvatar.colorFor(c.title);
                      return AppCard(
                        padding: EdgeInsets.zero,
                        onTap: () => _details(c),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: c.imageUrl != null
                                  ? Image.network(c.imageUrl!, width: double.infinity, fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Icon(_icons[c.category] ?? Icons.category_rounded, size: 48, color: accent))
                                  : Container(
                                      width: double.infinity,
                                      color: accent.withValues(alpha: 0.12),
                                      child: Icon(_icons[c.category] ?? Icons.category_rounded, size: 48, color: accent),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(Fmt.money(c.price, c.currency), style: context.text.titleSmall?.copyWith(color: context.scheme.primary)),
                                  const SizedBox(height: 2),
                                  Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                                  Text('${c.unit} · ${Fmt.relative(c.posted)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: context.text.bodySmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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
