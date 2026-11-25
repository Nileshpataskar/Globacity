import 'package:image_picker/image_picker.dart' show XFile;
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

class HelpdeskScreen extends ConsumerWidget {
  const HelpdeskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(ticketsProvider);
    final all = tickets.value ?? [];
    final open = all.where((t) => t.status.isActive).toList();
    final closed = all.where((t) => !t.status.isActive).toList();
    Widget list(List<Ticket> items) => RefreshIndicator(
          onRefresh: () => ref.refresh(ticketsProvider.future),
          child: AsyncView<List<Ticket>>(
            value: tickets,
            onRetry: () => ref.invalidate(ticketsProvider),
            data: (_) => _TicketList(tickets: items),
          ),
        );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Help desk'),
          bottom: TabBar(tabs: [Tab(text: tickets.hasValue ? 'Active (${open.length})' : 'Active'), const Tab(text: 'Closed')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'ticket',
          onPressed: () => context.push(Routes.newTicket),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New request'),
        ),
        body: TabBarView(children: [list(open), list(closed)]),
      ),
    );
  }
}

class _TicketList extends StatelessWidget {
  const _TicketList({required this.tickets});

  final List<Ticket> tickets;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) return ListView(children: const [EmptyState(icon: Icons.support_agent_rounded, title: 'No requests here')]);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
      itemCount: tickets.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) {
        final t = tickets[i];
        return AppCard(
          onTap: () => context.push(Routes.ticket(t.id)),
          child: Row(
            children: [
              const IconBadge(icon: Icons.build_circle_outlined),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: context.text.titleSmall),
                    const SizedBox(height: 2),
                    Text('#${t.number} · ${t.category} · ${Fmt.relative(t.createdAt)}', style: context.text.bodySmall),
                  ],
                ),
              ),
              StatusChip(label: t.status.label, tone: t.status.tone),
            ],
          ),
        );
      },
    );
  }
}

class NewTicketScreen extends ConsumerStatefulWidget {
  const NewTicketScreen({super.key});

  @override
  ConsumerState<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends ConsumerState<NewTicketScreen> {
  TicketCategory? _category;
  String _priority = 'Medium';
  final _title = TextEditingController();
  final _desc = TextEditingController();
  List<XFile> _photos = [];
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_category == null || _title.text.trim().isEmpty) {
      context.showSnack('Choose a category and add a title');
      return;
    }
    setState(() => _saving = true);
    final t = await runAction(context,
        () => ref.read(actionsProvider)
            .createTicket(_category!.id, _title.text.trim(), _desc.text.trim(), _priority, photos: _photos));
    if (!mounted) return;
    setState(() => _saving = false);
    if (t != null) {
      context.pop();
      context.showSnack('Request #${t.number} submitted');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New request')),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: AppSpacing.screenAll,
            child: FilledButton(onPressed: _saving ? null : _submit, child: const Text('Submit request'))),
      ),
      body: ListView(
        padding: AppSpacing.screenAll,
        children: [
          LabeledField(
            label: 'Category',
            child: AsyncView<List<TicketCategory>>(
              value: ref.watch(ticketCategoriesProvider),
              compact: true,
              onRetry: () => ref.invalidate(ticketCategoriesProvider),
              data: (cats) => GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 0.9,
                children: [
                  for (final c in cats)
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      borderColor: _category?.id == c.id ? context.scheme.primary : null,
                      color: _category?.id == c.id ? context.scheme.primary.withValues(alpha: 0.06) : null,
                      onTap: () => setState(() => _category = c),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(c.icon, color: _category?.id == c.id ? context.scheme.primary : context.palette.textMuted),
                          const SizedBox(height: AppSpacing.xs),
                          Text(c.name, textAlign: TextAlign.center, maxLines: 2, style: context.text.labelSmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          LabeledField(label: 'Title', child: TextField(controller: _title, decoration: const InputDecoration(hintText: 'Short summary of the issue'))),
          LabeledField(
            label: 'Description',
            child: TextField(controller: _desc, maxLines: 4,
                decoration: const InputDecoration(hintText: 'Describe the problem, location, best time to visit…')),
          ),
          LabeledField(
            label: 'Photos (optional)',
            child: PhotoPickerRow(photos: _photos, onChanged: (p) => setState(() => _photos = p)),
          ),
          LabeledField(
            label: 'Priority',
            child: SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'Low', label: Text('Low')), ButtonSegment(value: 'Medium', label: Text('Medium')),
                ButtonSegment(value: 'High', label: Text('High'))],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
          ),
        ],
      ),
    );
  }
}

class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ticketProvider(ticketId);
    return Scaffold(
      appBar: AppBar(title: const Text('Request')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(provider.future),
        child: AsyncView<Ticket>(
          value: ref.watch(provider),
          onRetry: () => ref.invalidate(provider),
          data: (t) => ListView(
            padding: AppSpacing.screenAll,
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      StatusChip(label: t.status.label, tone: t.status.tone),
                      const SizedBox(width: AppSpacing.sm),
                      StatusChip(label: '${t.priority} priority', tone: t.priority == 'High' ? Tone.danger : Tone.neutral),
                      const Spacer(),
                      Text('#${t.number}', style: context.text.labelMedium),
                    ]),
                    const SizedBox(height: AppSpacing.md),
                    Text(t.title, style: context.text.titleMedium),
                    if (t.description.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(t.description, style: context.text.bodyMedium),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    InfoRow(icon: Icons.category_outlined, label: 'Category', value: t.category),
                    InfoRow(icon: Icons.schedule_rounded, label: 'Raised', value: Fmt.dateTime(t.createdAt)),
                    if (t.attachments.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final url in t.attachments)
                            GestureDetector(
                              onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: Image.network(url))),
                              child: ClipRRect(
                                borderRadius: AppRadius.fieldRadius,
                                child: Image.network(url, width: 72, height: 72, fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const SizedBox(width: 72, height: 72, child: Icon(Icons.broken_image_outlined))),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SectionHeader(title: 'Timeline'),
              AppCard(
                child: Column(
                  children: [
                    for (var i = 0; i < t.updates.length; i++)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Column(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(shape: BoxShape.circle,
                                      color: i == t.updates.length - 1 ? context.scheme.primary : context.palette.border),
                                ),
                                if (i < t.updates.length - 1) Expanded(child: Container(width: 2, color: context.palette.border)),
                              ],
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.updates[i].message, style: context.text.titleSmall),
                                    const SizedBox(height: 2),
                                    Text('${t.updates[i].by} · ${Fmt.dateTime(t.updates[i].time)}', style: context.text.bodySmall),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (t.status == TicketStatus.resolved) ...[
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    children: [
                      Text('How was the service?', style: context.text.titleSmall),
                      const SizedBox(height: AppSpacing.sm),
                      RatingStars(
                        rating: 0,
                        size: 32,
                        onChanged: (v) => runAction(context, () => ref.read(actionsProvider).rateTicket(t.id, v),
                            success: 'Thanks for rating $v stars'),
                      ),
                    ],
                  ),
                ),
              ],
              if (t.rating != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Center(child: RatingStars(rating: t.rating!.toDouble(), size: 24)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
