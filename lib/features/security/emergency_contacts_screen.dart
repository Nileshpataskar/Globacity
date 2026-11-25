import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/device.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Country emergency numbers (from the country config) + community + personal contacts.
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  void _add(BuildContext context, WidgetRef ref) {
    final name = TextEditingController();
    final phone = TextEditingController();
    showAppSheet(
      context,
      title: 'Add personal contact',
      child: Builder(
        builder: (sheetContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
                final ok = await runAction(sheetContext, () async {
                  await ref.read(actionsProvider).addPersonalContact(name.text.trim(), phone.text.trim());
                  return true;
                });
                if (ok == true && sheetContext.mounted) Navigator.pop(sheetContext);
              },
              child: const Text('Save'),
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
        title: const Text('Emergency contacts'),
        actions: [IconButton(onPressed: () => _add(context, ref), icon: const Icon(Icons.person_add_alt_rounded))],
      ),
      body: AsyncView<List<EmergencyContact>>(
        value: ref.watch(emergencyContactsProvider),
        onRetry: () => ref.invalidate(emergencyContactsProvider),
        data: (contacts) {
          final groups = <String>{for (final c in contacts) c.group};
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
            children: [
              for (final g in groups)
                TileGroup(
                  title: g,
                  children: [
                    for (final c in contacts.where((c) => c.group == g))
                      MenuTile(
                        icon: c.icon,
                        color: g == 'Public services' ? context.palette.danger : null,
                        title: c.name,
                        subtitle: c.phone,
                        trailing: IconButton.filledTonal(
                          onPressed: () => Device.call(context, c.phone),
                          icon: const Icon(Icons.call_rounded),
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
