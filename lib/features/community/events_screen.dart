import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Community events: RSVP with instant feedback, choose how many are coming, see spots left.
class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(eventsProvider.future),
        child: AsyncView<List<CommunityEvent>>(
          value: ref.watch(eventsProvider),
          skeleton: const SkeletonList(count: 3, tall: true),
          onRetry: () => ref.invalidate(eventsProvider),
          data: (all) {
            // Soonest first; events that are over go to the end.
            final now = DateTime.now();
            bool over(CommunityEvent e) => (e.endsAt ?? e.date.add(const Duration(hours: 3))).isBefore(now);
            final events = [...all]..sort((a, b) {
                final o = (over(a) ? 1 : 0) - (over(b) ? 1 : 0);
                return o != 0 ? o : a.date.compareTo(b.date);
              });
            return events.isEmpty
              ? ListView(children: const [
                  EmptyState(
                    icon: Icons.celebration_outlined,
                    title: 'No events planned yet',
                    message: 'Festivals, sports days and meet-ups organised by your committee will show up here.',
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
                  itemCount: events.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
                  itemBuilder: (_, i) => i == 0
                      ? Text('Coming up in your community', style: context.text.bodyMedium?.copyWith(color: context.palette.textMuted))
                      : _EventCard(event: events[i - 1]).enter(i),
                );
          },
        ),
      ),
    );
  }
}

class _EventCard extends ConsumerStatefulWidget {
  const _EventCard({required this.event});

  final CommunityEvent event;

  @override
  ConsumerState<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends ConsumerState<_EventCard> {
  // Optimistic copy of the RSVP so the card reacts instantly; synced from the server after each save.
  late bool _going = widget.event.going;
  late int _people = widget.event.going ? widget.event.myGuests.clamp(1, 20) : 1;
  late int _attendees = widget.event.attendees;
  bool _saving = false;
  int _celebrate = 0;

  CommunityEvent get e => widget.event;

  @override
  void didUpdateWidget(_EventCard old) {
    super.didUpdateWidget(old);
    if (!_saving && old.event != widget.event) {
      _going = e.going;
      _people = e.going ? e.myGuests.clamp(1, 20) : 1;
      _attendees = e.attendees;
    }
  }

  bool get _ended => (e.endsAt ?? e.date.add(const Duration(hours: 3))).isBefore(DateTime.now());
  int? get _spotsLeft => e.capacity == null ? null : (e.capacity! - _attendees).clamp(0, e.capacity!);
  bool get _full => !_going && _spotsLeft != null && _spotsLeft! <= 0;

  Future<void> _save({required bool going, required int people}) async {
    final before = (_going, _people, _attendees);
    final mine = _going ? _people : 0;
    setState(() {
      _saving = true;
      _going = going;
      _people = people;
      _attendees = _attendees - mine + (going ? people : 0);
      if (going && !before.$1) _celebrate++;
    });
    if (going && !before.$1) HapticFeedback.mediumImpact();
    try {
      await ref.read(actionsProvider).rsvp(e.id, going, people: people);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _going = before.$1;
        _people = before.$2;
        _attendees = before.$3;
      });
      context.showSnack(err.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _details() => showAppSheet(
        context,
        title: e.title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoRow(icon: Icons.event_rounded, label: 'When',
                value: '${Fmt.weekday(e.date)}, ${Fmt.date(e.date)} · ${Fmt.time(e.date)}${e.endsAt == null ? '' : ' – ${Fmt.time(e.endsAt!)}'}'),
            InfoRow(icon: Icons.place_rounded, label: 'Where', value: e.venue),
            InfoRow(icon: Icons.groups_rounded, label: 'Going',
                value: e.capacity == null ? '$_attendees people' : '$_attendees of ${e.capacity} spots taken'),
            if (e.description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(e.description, style: context.text.bodyMedium),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final accent = AppAvatar.colorFor(e.title);
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: _details,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner with date block and category
          Container(
            height: 104,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [accent, Color.lerp(accent, Colors.black, 0.35)!],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Column(children: [
                    Text(Fmt.month(e.date).substring(0, 3).toUpperCase(),
                        style: context.text.labelSmall?.copyWith(color: accent, fontWeight: FontWeight.w800)),
                    Text('${e.date.day}', style: context.text.titleLarge?.copyWith(color: const Color(0xFF101828), height: 1.1)),
                  ]),
                ),
                const Spacer(),
                if (_ended)
                  const _Pill(label: 'Ended', icon: Icons.history_rounded)
                else if (_going)
                  const _Pill(label: "You're going", icon: Icons.check_circle_rounded)
                else if (e.category.isNotEmpty)
                  _Pill(label: e.category),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: context.text.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Wrap(spacing: AppSpacing.md, runSpacing: 4, children: [
                  _Meta(icon: Icons.schedule_rounded, text: '${Fmt.weekday(e.date)}, ${Fmt.time(e.date)}'),
                  _Meta(icon: Icons.place_outlined, text: e.venue),
                ]),
                if (e.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(e.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                ],
                const SizedBox(height: AppSpacing.md),
                _Attendance(attendees: _attendees, capacity: e.capacity),
                const SizedBox(height: AppSpacing.md),
                if (_ended)
                  Text(_going ? 'You were there 🎉' : 'This event is over.', style: context.text.bodySmall)
                else
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
                    ),
                    child: _going ? _goingPanel(context) : _rsvpButton(context),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rsvpButton(BuildContext context) => SizedBox(
        key: const ValueKey('rsvp'),
        width: double.infinity,
        child: _full
            ? OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.block_rounded), label: const Text('Event full'))
            : GradientButton(
                label: 'Count me in',
                icon: Icons.celebration_rounded,
                busy: _saving,
                onPressed: () => _save(going: true, people: _people),
              ),
      );

  Widget _goingPanel(BuildContext context) {
    final green = context.palette.success;
    return Container(
      key: const ValueKey('going'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.08),
        border: Border.all(color: green.withValues(alpha: 0.35)),
        borderRadius: AppRadius.fieldRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.check_circle_rounded, color: green)
                .animate(key: ValueKey(_celebrate))
                .scaleXY(begin: 0.4, end: 1, duration: 450.ms, curve: Curves.elasticOut),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text("You're going! See you there.", style: context.text.titleSmall?.copyWith(color: green))),
            if (_saving) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Text('Coming:', style: context.text.bodyMedium),
            const SizedBox(width: AppSpacing.sm),
            _Stepper(
              value: _people,
              onChanged: _saving ? null : (v) => _save(going: true, people: v),
              max: e.capacity == null ? 20 : (_people + (_spotsLeft ?? 0)).clamp(1, 20),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(_people == 1 ? 'person' : 'people', style: context.text.bodyMedium),
            const Spacer(),
            TextButton(
              onPressed: _saving ? null : () => _save(going: false, people: 1),
              style: TextButton.styleFrom(foregroundColor: context.palette.textMuted),
              child: const Text("Can't make it"),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Attendance extends StatelessWidget {
  const _Attendance({required this.attendees, required this.capacity});

  final int attendees;
  final int? capacity;

  @override
  Widget build(BuildContext context) {
    final text = attendees == 0
        ? 'Be the first to join'
        : '$attendees ${attendees == 1 ? 'neighbour' : 'neighbours'} going';
    final left = capacity == null ? null : (capacity! - attendees).clamp(0, capacity!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.groups_rounded, size: 18, color: context.scheme.primary),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(text, key: ValueKey(text), style: context.text.labelLarge?.copyWith(color: context.scheme.primary)),
          ),
          const Spacer(),
          if (left != null)
            Text(left == 0 ? 'Full' : '$left spots left',
                style: context.text.labelMedium?.copyWith(color: left == 0 ? context.palette.danger : null)),
        ]),
        if (capacity != null && capacity! > 0) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (attendees / capacity!).clamp(0, 1)),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: context.palette.surfaceAlt,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged, this.max = 20});

  final int value;
  final ValueChanged<int>? onChanged;
  final int max;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, int? next) => InkResponse(
          onTap: onChanged == null || next == null ? null : () => onChanged!(next),
          radius: 18,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.scheme.surface,
              border: Border.all(color: context.palette.border),
            ),
            child: Icon(icon, size: 16, color: next == null ? context.palette.textMuted.withValues(alpha: 0.4) : null),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.remove_rounded, value > 1 ? value - 1 : null),
      SizedBox(
        width: 30,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text('$value', key: ValueKey(value), textAlign: TextAlign.center, style: context.text.titleMedium),
        ),
      ),
      btn(Icons.add_rounded, value < max ? value + 1 : null),
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: Colors.white), const SizedBox(width: 4)],
          Text(label, style: context.text.labelMedium?.copyWith(color: Colors.white)),
        ]),
      );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: context.palette.textMuted),
        const SizedBox(width: 4),
        Text(text, style: context.text.bodySmall),
      ]);
}
