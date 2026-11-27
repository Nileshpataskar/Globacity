import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';

/// Join a community: search -> tower -> unit -> role -> request (approved by management).
class JoinCommunityScreen extends ConsumerStatefulWidget {
  const JoinCommunityScreen({super.key, this.isOnboarding = false});

  final bool isOnboarding;

  @override
  ConsumerState<JoinCommunityScreen> createState() => _JoinCommunityScreenState();
}

class _JoinCommunityScreenState extends ConsumerState<JoinCommunityScreen> {
  Timer? _debounce;
  String _query = '';
  late Future<List<Community>> _results = _search('');
  Community? _community;
  Future<List<TowerOption>>? _towers;
  TowerOption? _tower;
  Future<List<UnitOption>>? _units;
  UnitOption? _unit;
  ResidentRole _role = ResidentRole.owner;
  bool _submitting = false;

  AppActions get _actions => ref.read(actionsProvider);

  Future<List<Community>> _search(String q) => _actions.searchCommunities(q);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() {
          _query = q;
          _results = _search(q);
        }));
  }

  void _pickCommunity(Community c) => setState(() {
        _community = c;
        _towers = _actions.towers(c.id);
        _tower = null;
        _unit = null;
        _units = null;
      });

  void _pickTower(TowerOption t) => setState(() {
        _tower = t;
        _unit = null;
        _units = _actions.units(_community!.id, t.id);
      });

  Future<void> _submit() async {
    if (_unit == null) {
      context.showSnack('Select your unit');
      return;
    }
    setState(() => _submitting = true);
    final approved = await runAction(context, () => _actions.joinUnit(_unit!.id, _role));
    if (!mounted) return;
    setState(() => _submitting = false);
    if (approved == null) return;
    context.showSnack(approved
        ? 'Welcome to ${_community!.name}! You now have access.'
        : 'Request sent to ${_community!.name} management for approval');
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _community == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _community = null);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.isOnboarding || _community != null,
          title: Text(_community == null ? 'Find your community' : 'Your unit'),
          actions: [
            if (widget.isOnboarding && _community == null)
              TextButton(onPressed: () => context.go(Routes.home), child: const Text('Skip')),
          ],
        ),
        body: _community == null ? _buildSearch() : _buildUnitForm(),
      ),
    );
  }

  Widget _buildSearch() {
    return ListView(
      padding: AppSpacing.screenAll,
      children: [
        Text('Search by community name or area to join as a resident.',
            style: context.text.bodyMedium?.copyWith(color: context.palette.textMuted)),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          onChanged: _onQuery,
          decoration: const InputDecoration(hintText: 'Search communities', prefixIcon: Icon(Icons.search_rounded)),
        ),
        const SizedBox(height: AppSpacing.lg),
        FutureBuilder<List<Community>>(
          future: _results,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 360, child: SkeletonList(count: 4, padding: EdgeInsets.zero));
            }
            if (snap.hasError) {
              return EmptyState(icon: Icons.cloud_off_rounded, title: "Couldn't search", message: '${snap.error}',
                  action: 'Retry', onAction: () => setState(() => _results = _search(_query)));
            }
            final list = snap.data!;
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.search_off_rounded, title: 'No communities found',
                  message: 'Ask your community manager to onboard your building.');
            }
            return Column(
              children: [
                for (final c in list) ...[
                  AppCard(
                    onTap: () => _pickCommunity(c),
                    child: Row(
                      children: [
                        const IconBadge(icon: Icons.location_city_rounded),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name, style: context.text.titleSmall),
                              const SizedBox(height: 2),
                              Text(c.area, style: context.text.bodySmall),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: context.palette.textMuted),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildUnitForm() {
    final c = _community!;
    return ListView(
      padding: AppSpacing.screenAll,
      children: [
        AppCard(
          color: context.scheme.primary.withValues(alpha: 0.06),
          borderColor: context.scheme.primary.withValues(alpha: 0.2),
          child: Row(
            children: [
              const IconBadge(icon: Icons.location_city_rounded),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(c.name, style: context.text.titleSmall), Text(c.area, style: context.text.bodySmall)],
                ),
              ),
              TextButton(onPressed: () => setState(() => _community = null), child: const Text('Change')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        LabeledField(
          label: 'Tower / Building',
          child: FutureBuilder<List<TowerOption>>(
            future: _towers,
            builder: (context, snap) => !snap.hasData
                ? (snap.hasError ? Text('${snap.error}') : const SkeletonLines(lines: 1))
                : snap.data!.isEmpty
                ? _NotSetUp(
                    message: '${c.name} hasn\'t added its towers and flats yet. '
                        'Please ask your community management to set them up, then try again.',
                  )
                : Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final t in snap.data!)
                        ChoiceChip(label: Text(t.name), selected: _tower?.id == t.id, onSelected: (_) => _pickTower(t)),
                    ],
                  ),
          ),
        ),
        if (_units != null)
          LabeledField(
            label: 'Unit / Flat number',
            child: FutureBuilder<List<UnitOption>>(
              future: _units,
              builder: (context, snap) => !snap.hasData
                  ? (snap.hasError ? Text('${snap.error}') : const SkeletonLines(lines: 1))
                  : snap.data!.isEmpty
                  ? _NotSetUp(message: '${_tower?.name ?? 'This tower'} has no flats yet. Please ask your community management to add them.')
                  : DropdownMenu<UnitOption>(
                      expandedInsets: EdgeInsets.zero,
                      enableFilter: true,
                      requestFocusOnTap: true,
                      hintText: 'Search or select your unit',
                      leadingIcon: const Icon(Icons.door_front_door_outlined),
                      menuHeight: 320,
                      onSelected: (u) => setState(() => _unit = u),
                      dropdownMenuEntries: [
                        for (final u in snap.data!) DropdownMenuEntry(value: u, label: u.number),
                      ],
                    ),
            ),
          ),
        LabeledField(
          label: 'I am the',
          child: SegmentedButton<ResidentRole>(
            segments: [for (final r in ResidentRole.values) ButtonSegment(value: r, label: Text(r.label))],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          color: context.palette.surfaceAlt,
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: context.palette.info),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('Your request will be verified by the community management. '
                    'You may be asked for ownership or tenancy documents.', style: context.text.bodySmall),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        GradientButton(label: 'Request to join', busy: _submitting, onPressed: _unit == null ? null : _submit),
      ],
    );
  }
}

/// Shown when a community has no towers, or a tower has no flats, yet.
class _NotSetUp extends StatelessWidget {
  const _NotSetUp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => AppCard(
        color: context.palette.warning.withValues(alpha: 0.08),
        borderColor: context.palette.warning.withValues(alpha: 0.35),
        child: Row(children: [
          Icon(Icons.apartment_rounded, color: context.palette.warning),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(message, style: context.text.bodySmall?.copyWith(color: context.scheme.onSurface))),
        ]),
      );
}
