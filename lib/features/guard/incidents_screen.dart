import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/guard.dart';

/// Incident reporting with photo, plus follow-up (investigating / resolved).
class IncidentsScreen extends ConsumerWidget {
  const IncidentsScreen({super.key});

  static const _severities = ['low', 'medium', 'high', 'critical'];
  static const _categories = ['Security', 'Safety', 'Damage', 'Noise', 'Parking', 'Other'];

  void _report(BuildContext context, WidgetRef ref) {
    final title = TextEditingController();
    final desc = TextEditingController();
    final location = TextEditingController();
    var severity = 'medium';
    var category = 'Security';
    XFile? photo;
    var saving = false;
    showAppSheet(
      context,
      title: 'Report incident',
      child: StatefulBuilder(
        builder: (sheetContext, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'What happened?')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: location, decoration: const InputDecoration(labelText: 'Location (e.g. Tower A lobby)')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Details', alignLabelWithHint: true)),
            const SizedBox(height: AppSpacing.md),
            Text('Category', style: sheetContext.text.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
              for (final c in _categories)
                ChoiceChip(label: Text(c), selected: category == c, onSelected: (_) => setSheet(() => category = c)),
            ]),
            const SizedBox(height: AppSpacing.md),
            Text('Severity', style: sheetContext.text.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<String>(
              segments: [for (final s in _severities) ButtonSegment(value: s, label: Text('${s[0].toUpperCase()}${s.substring(1)}'))],
              selected: {severity},
              onSelectionChanged: (s) => setSheet(() => severity = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            PhotoPickerRow(photos: [?photo], max: 1, onChanged: (p) => setSheet(() => photo = p.isEmpty ? null : p.first)),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (title.text.trim().isEmpty) return;
                      setSheet(() => saving = true);
                      final ok = await runAction(sheetContext, () async {
                        await ref.read(guardActionsProvider).reportIncident({
                          'title': title.text.trim(),
                          'description': desc.text.trim(),
                          'location': location.text.trim(),
                          'severity': severity,
                          'category': category,
                        }, photo: photo);
                        return true;
                      }, success: 'Incident reported to management');
                      if (ok == true && sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      } else {
                        setSheet(() => saving = false);
                      }
                    },
              child: const Text('Submit report'),
            ),
          ],
        ),
      ),
    );
  }

  void _update(BuildContext context, WidgetRef ref, Incident i) {
    final note = TextEditingController(text: i.resolution);
    showAppSheet(
      context,
      title: i.title,
      child: Builder(
        builder: (sheetContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (i.photoUrl != null) ...[
              ClipRRect(borderRadius: AppRadius.cardRadius,
                  child: Image.network(i.photoUrl!, height: 180, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())),
              const SizedBox(height: AppSpacing.md),
            ],
            if (i.description.isNotEmpty) Text(i.description, style: sheetContext.text.bodyMedium),
            const SizedBox(height: AppSpacing.md),
            InfoRow(icon: Icons.place_outlined, label: 'Location', value: i.location.isEmpty ? '-' : i.location),
            InfoRow(icon: Icons.person_outline_rounded, label: 'Reported by', value: i.reportedBy ?? '-'),
            InfoRow(icon: Icons.schedule_rounded, label: 'Reported', value: Fmt.dateTime(i.createdAt)),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Action taken / notes')),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final ok = await runAction(sheetContext, () async {
                        await ref.read(guardActionsProvider).updateIncident(i.id, 'investigating', note.text.trim());
                        return true;
                      });
                      if (ok == true && sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    child: const Text('Investigating'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: sheetContext.palette.success),
                    onPressed: () async {
                      final ok = await runAction(sheetContext, () async {
                        await ref.read(guardActionsProvider).updateIncident(i.id, 'resolved', note.text.trim());
                        return true;
                      }, success: 'Incident resolved');
                      if (ok == true && sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    child: const Text('Resolved'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Incidents')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'incident',
        backgroundColor: context.palette.danger,
        onPressed: () => _report(context, ref),
        icon: const Icon(Icons.report_gmailerrorred_rounded),
        label: const Text('Report'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(guardIncidentsProvider.future),
        child: AsyncView<List<Incident>>(
          value: ref.watch(guardIncidentsProvider),
          onRetry: () => ref.invalidate(guardIncidentsProvider),
          data: (items) => items.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.verified_user_outlined, title: 'No incidents reported')])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, idx) {
                    final i = items[idx];
                    return AppCard(
                      onTap: () => _update(context, ref, i),
                      child: Row(
                        children: [
                          IconBadge(icon: Icons.report_gmailerrorred_rounded, color: i.severityTone.resolve(context)),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(i.title, style: context.text.titleSmall),
                                Text([if (i.location.isNotEmpty) i.location, Fmt.relative(i.createdAt)].join(' · '),
                                    style: context.text.bodySmall),
                                const SizedBox(height: AppSpacing.xs),
                                StatusChip(label: i.severity, tone: i.severityTone),
                              ],
                            ),
                          ),
                          StatusChip(label: i.status, tone: i.statusTone),
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
