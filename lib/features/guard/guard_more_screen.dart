import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/guard.dart';
import '../../data/manage.dart';
import '../../data/providers.dart';

/// Guard menu + profile.
class GuardMoreScreen extends ConsumerWidget {
  const GuardMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final gctx = ref.watch(guardContextProvider).value;
    final hasUnits = (ref.watch(propertiesProvider).value ?? []).any((p) => p.isApproved);
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
        children: [
          AppCard(
            onTap: () => context.push(Routes.editProfile),
            child: Row(
              children: [
                AppAvatar(name: user.name, size: 60, imageUrl: user.avatarUrl),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: context.text.titleMedium),
                      Text(user.phone, style: context.text.bodySmall),
                      const SizedBox(height: AppSpacing.xs),
                      StatusChip(label: 'Security · ${gctx?.communityName ?? ''}', tone: Tone.primary, icon: Icons.shield_rounded),
                    ],
                  ),
                ),
                Icon(Icons.edit_outlined, color: context.palette.textMuted),
              ],
            ),
          ),
          TileGroup(
            title: 'Gate operations',
            children: [
              MenuTile(icon: Icons.schedule_rounded, title: 'My shift', subtitle: gctx?.shift?.shiftLabel ?? 'Off duty',
                  onTap: () => context.push(Routes.guardShift)),
              MenuTile(icon: Icons.directions_car_rounded, title: 'Vehicle entry log', onTap: () => context.push(Routes.guardVehicles)),
              MenuTile(icon: Icons.report_gmailerrorred_rounded, title: 'Incidents', color: context.palette.danger,
                  onTap: () => context.push(Routes.guardIncidents)),
              MenuTile(icon: Icons.cleaning_services_rounded, title: 'Daily help inside', onTap: () => context.push(Routes.guardHelpers)),
              MenuTile(icon: Icons.child_care_rounded, title: 'Kid exit permissions', onTap: () => context.push(Routes.guardKidExits)),
              MenuTile(icon: Icons.manage_search_rounded, title: 'Resident directory', onTap: () => context.push(Routes.guardDirectory)),
            ],
          ),
          TileGroup(
            title: 'Account',
            children: [
              MenuTile(icon: Icons.notifications_none_rounded, title: 'Notifications', onTap: () => context.push(Routes.notifications)),
              if (hasUnits && !AppConfig.guardApp)
                MenuTile(icon: Icons.home_outlined, title: 'Switch to resident app', onTap: () => context.go(Routes.home)),
              if (ref.watch(isManagerProvider) && !AppConfig.guardApp)
                MenuTile(icon: Icons.admin_panel_settings_outlined, title: 'Open management', onTap: () => context.go(Routes.manageHome)),
              MenuTile(icon: Icons.description_outlined, title: 'Terms & conditions', onTap: () => context.push(Routes.terms)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: context.palette.danger),
            onPressed: () async {
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) context.go(Routes.login);
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
