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

/// Lists the user's units; selecting one re-renders the whole app for that unit (and its country).
Future<void> showPropertySwitcher(BuildContext context) =>
    showAppSheet(context, title: 'My properties', child: const _PropertyList());

class _PropertyList extends ConsumerWidget {
  const _PropertyList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentPropertyProvider).value;
    return AsyncView<List<Property>>(
      value: ref.watch(propertiesProvider),
      compact: true,
      onRetry: () => ref.invalidate(propertiesProvider),
      data: (properties) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in properties) ...[
            AppCard(
              borderColor: p.id == current?.id ? context.scheme.primary : null,
              onTap: p.isApproved
                  ? () {
                      ref.read(actionsProvider).selectUnit(p.id);
                      Navigator.pop(context);
                      context.showSnack('Switched to ${p.community}');
                    }
                  : null,
              child: Row(
                children: [
                  IconBadge(icon: Icons.apartment_rounded,
                      color: p.id == current?.id ? context.scheme.primary : context.palette.textMuted),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.community, style: context.text.titleSmall),
                        const SizedBox(height: 2),
                        Text('${p.shortLabel} · ${p.city} · ${p.currency}', style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  p.isApproved
                      ? StatusChip(label: p.role.label, tone: p.id == current?.id ? Tone.primary : Tone.neutral)
                      : StatusChip(label: p.status == 'pending' ? 'Pending' : p.status, tone: Tone.warning),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              context.push(Routes.joinCommunity);
            },
            icon: const Icon(Icons.add_home_outlined),
            label: const Text('Add another property'),
          ),
        ],
      ),
    );
  }
}
