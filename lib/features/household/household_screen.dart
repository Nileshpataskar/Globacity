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

/// Family, vehicles, daily help, pets and frequent entries for the selected unit.
class HouseholdScreen extends ConsumerStatefulWidget {
  const HouseholdScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends ConsumerState<HouseholdScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 5, vsync: this, initialIndex: widget.initialTab.clamp(0, 4));

  static const _addLabels = ['Add member', 'Add vehicle', 'Add daily help', 'Add pet', 'Add frequent entry'];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _add() {
    final a = ref.read(actionsProvider);
    switch (_tabs.index) {
      case 0:
        _showForm('Add family member', ['Full name', 'Relation (e.g. Son)', 'Mobile (optional)'],
            (v, minor) => a.addFamilyMember(v[0], v[1], v[2], minor), withMinor: true);
      case 1:
        _showForm('Add vehicle', ['Plate number', 'Make & model', 'Parking slot (optional)'],
            (v, _) => a.addVehicle(v[0], v[1], v[2]));
      case 2:
        _showForm('Add daily help', ['Full name', 'Role (e.g. Cook)', 'Mobile number', 'Timing (e.g. 9 AM - 1 PM)'],
            (v, _) => a.addDailyHelp(v[0], v[1], v[2], v[3]), required: 3);
      case 3:
        _showForm('Add pet', ['Name', 'Species (e.g. Dog)', 'Breed'], (v, _) => a.addPet(v[0], v[1], v[2]));
      case 4:
        context.push(Routes.invite);
    }
  }

  void _showForm(String title, List<String> fields, Future<void> Function(List<String>, bool minor) onSave,
      {bool withMinor = false, int required = 2}) {
    final controllers = [for (final _ in fields) TextEditingController()];
    var minor = false;
    var saving = false;
    showAppSheet(
      context,
      title: title,
      child: StatefulBuilder(
        builder: (sheetContext, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < fields.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: TextField(controller: controllers[i], decoration: InputDecoration(labelText: fields[i])),
              ),
            if (withMinor)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: minor,
                onChanged: (v) => setSheet(() => minor = v),
                title: const Text('Child (under 18)'),
                subtitle: const Text('Guards will need your permission before they leave alone'),
              ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final values = controllers.map((c) => c.text.trim()).toList();
                      if (values.take(required).any((v) => v.isEmpty)) {
                        sheetContext.showSnack('Please fill the required fields');
                        return;
                      }
                      setSheet(() => saving = true);
                      final ok = await runAction(sheetContext, () async {
                        await onSave(values, minor);
                        return true;
                      });
                      if (ok == true && sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                        if (mounted) context.showSnack('Saved');
                      } else {
                        setSheet(() => saving = false);
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My household'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [Tab(text: 'Family'), Tab(text: 'Vehicles'), Tab(text: 'Daily help'), Tab(text: 'Pets'), Tab(text: 'Frequent')],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'household-add',
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: Text(_addLabels[_tabs.index]),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _AsyncList(provider: familyProvider, emptyIcon: Icons.family_restroom_rounded, emptyTitle: 'No family members added',
              item: (m) => _FamilyCard(member: m)),
          _AsyncList(provider: vehiclesProvider, emptyIcon: Icons.directions_car_rounded, emptyTitle: 'No vehicles registered',
              item: (v) => _VehicleCard(vehicle: v)),
          _AsyncList(provider: dailyHelpProvider, emptyIcon: Icons.cleaning_services_rounded, emptyTitle: 'No daily help added',
              item: (h) => _HelperCard(helper: h)),
          _AsyncList(provider: petsProvider, emptyIcon: Icons.pets_rounded, emptyTitle: 'No pets registered',
              item: (p) => _PetCard(pet: p)),
          _AsyncList(provider: frequentEntriesProvider, emptyIcon: Icons.event_repeat_rounded, emptyTitle: 'No frequent entries',
              item: (f) => _FrequentCard(entry: f)),
        ],
      ),
    );
  }
}

class _AsyncList<T> extends ConsumerWidget {
  const _AsyncList({required this.provider, required this.item, required this.emptyIcon, required this.emptyTitle});

  final FutureProvider<List<T>> provider;
  final Widget Function(T) item;
  final IconData emptyIcon;
  final String emptyTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(provider.future),
      child: AsyncView<List<T>>(
        value: ref.watch(provider),
        onRetry: () => ref.invalidate(provider),
        data: (items) => items.isEmpty
            ? ListView(children: [EmptyState(icon: emptyIcon, title: emptyTitle)])
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (_, i) => item(items[i]),
              ),
      ),
    );
  }
}

class _FamilyCard extends ConsumerWidget {
  const _FamilyCard({required this.member});

  final FamilyMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = member;
    return AppCard(
      child: Row(
        children: [
          AppAvatar(name: m.name),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: context.text.titleSmall),
                Text([m.relation, if (m.phone != null) m.phone!].join(' · '), style: context.text.bodySmall),
              ],
            ),
          ),
          if (m.isMinor) const StatusChip(label: 'Minor', tone: Tone.info),
          PopupMenuButton<String>(
            onSelected: (_) => runAction(context, () => ref.read(actionsProvider).removeFamilyMember(m.id),
                success: '${m.name} removed'),
            itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove'))],
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    return AppCard(
      child: Row(
        children: [
          IconBadge(icon: v.isCar ? Icons.directions_car_rounded : Icons.two_wheeler_rounded),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(v.number, style: context.text.titleSmall), Text(v.model, style: context.text.bodySmall)],
            ),
          ),
          if (v.parkingSlot != null) StatusChip(label: 'P · ${v.parkingSlot}', tone: Tone.primary),
        ],
      ),
    );
  }
}

class _HelperCard extends StatelessWidget {
  const _HelperCard({required this.helper});

  final DailyHelp helper;

  @override
  Widget build(BuildContext context) {
    final h = helper;
    return AppCard(
      onTap: () => context.push(Routes.helper(h.id)),
      child: Row(
        children: [
          AppAvatar(name: h.name),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.name, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(child: Text(h.role, style: context.text.bodySmall, overflow: TextOverflow.ellipsis)),
                    if (h.reviewsCount > 0) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                      Text(' ${h.rating.toStringAsFixed(1)}', style: context.text.labelMedium),
                    ],
                  ],
                ),
              ],
            ),
          ),
          StatusChip(label: h.isInside ? 'Inside' : 'Out', tone: h.isInside ? Tone.success : Tone.neutral),
        ],
      ),
    );
  }
}

class _PetCard extends StatelessWidget {
  const _PetCard({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final p = pet;
    return AppCard(
      child: Row(
        children: [
          const IconBadge(icon: Icons.pets_rounded, color: Color(0xFFEA580C)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: context.text.titleSmall),
                Text([p.species, if (p.breed.isNotEmpty) p.breed].join(' · '), style: context.text.bodySmall),
              ],
            ),
          ),
          if (p.vaccinated) const StatusChip(label: 'Vaccinated', tone: Tone.success, icon: Icons.verified_rounded),
        ],
      ),
    );
  }
}

class _FrequentCard extends ConsumerWidget {
  const _FrequentCard({required this.entry});

  final FrequentEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = entry;
    return AppCard(
      child: Row(
        children: [
          AppAvatar(name: f.name, icon: f.type.icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.name, style: context.text.titleSmall),
                Text(f.schedule, style: context.text.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                Text('Code ${f.passCode} · valid till ${Fmt.date(f.validTill)}', style: context.text.labelSmall),
              ],
            ),
          ),
          IconButton(
            onPressed: () => runAction(context, () => ref.read(actionsProvider).removeFrequentEntry(f.id),
                success: 'Frequent entry removed'),
            icon: Icon(Icons.delete_outline_rounded, color: context.palette.danger),
          ),
        ],
      ),
    );
  }
}
