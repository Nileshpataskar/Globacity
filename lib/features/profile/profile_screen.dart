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
import '../../data/models.dart';
import '../../data/providers.dart';
import '../home/property_switcher.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _pickTheme(BuildContext context, WidgetRef ref) {
    final current = ref.read(themeModeProvider);
    showAppSheet(
      context,
      title: 'Appearance',
      child: RadioGroup<ThemeMode>(
        groupValue: current,
        onChanged: (m) {
          if (m != null) ref.read(themeModeProvider.notifier).set(m);
          Navigator.pop(context);
        },
        child: const Column(
          children: [
            RadioListTile(value: ThemeMode.system, title: Text('System default')),
            RadioListTile(value: ThemeMode.light, title: Text('Light')),
            RadioListTile(value: ThemeMode.dark, title: Text('Dark')),
          ],
        ),
      ),
    );
  }

  void _pickLanguage(BuildContext context, WidgetRef ref) {
    final current = ref.read(localeProvider).languageCode;
    showAppSheet(
      context,
      title: 'Language',
      child: RadioGroup<String>(
        groupValue: current,
        onChanged: (code) {
          if (code != null) ref.read(localeProvider.notifier).set(Locale(code));
          Navigator.pop(context);
        },
        child: const Column(
          children: [
            RadioListTile(value: 'en', title: Text('English')),
            RadioListTile(value: 'ar', title: Text('العربية'), subtitle: Text('Arabic · right-to-left layout')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final property = ref.watch(currentPropertyProvider).value;
    final propertyCount = ref.watch(propertiesProvider).value?.length ?? 0;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
        children: [
          AppCard(
            onTap: () => context.push(Routes.editProfile),
            child: Row(
              children: [
                AppAvatar(name: user.name, size: 64, imageUrl: user.avatarUrl),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: context.text.titleMedium),
                      const SizedBox(height: 2),
                      Text(user.phone, style: context.text.bodySmall),
                      if (user.email.isNotEmpty) Text(user.email, style: context.text.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.edit_outlined, color: context.palette.textMuted),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            color: context.scheme.primary.withValues(alpha: 0.06),
            borderColor: context.scheme.primary.withValues(alpha: 0.2),
            onTap: () => showPropertySwitcher(context),
            child: Row(
              children: [
                const IconBadge(icon: Icons.apartment_rounded),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(property?.community ?? 'No approved unit yet', style: context.text.titleSmall),
                      Text(property == null ? 'Tap to see your requests' : '${property.shortLabel} · ${property.role.label} · ${property.currency}',
                          style: context.text.bodySmall),
                    ],
                  ),
                ),
                Text(propertyCount > 1 ? 'Switch' : 'Add', style: context.text.labelLarge?.copyWith(color: context.scheme.primary)),
              ],
            ),
          ),
          TileGroup(
            title: 'My home',
            children: [
              MenuTile(icon: Icons.family_restroom_rounded, title: 'Family members', onTap: () => context.push(Routes.household)),
              MenuTile(icon: Icons.directions_car_rounded, title: 'Vehicles', onTap: () => context.push('${Routes.household}?tab=1')),
              MenuTile(icon: Icons.cleaning_services_rounded, title: 'Daily help', onTap: () => context.push('${Routes.household}?tab=2')),
              MenuTile(icon: Icons.pets_rounded, title: 'Pets', onTap: () => context.push('${Routes.household}?tab=3')),
              MenuTile(icon: Icons.event_repeat_rounded, title: 'Frequent entries', onTap: () => context.push('${Routes.household}?tab=4')),
              MenuTile(icon: Icons.add_home_outlined, title: 'Join another community', onTap: () => context.push(Routes.joinCommunity)),
              if (ref.watch(isManagerProvider))
                MenuTile(icon: Icons.admin_panel_settings_outlined, title: 'Open management',
                    onTap: () => context.go(Routes.manageHome)),
            ],
          ),
          TileGroup(
            title: 'Preferences',
            children: [
              MenuTile(icon: Icons.notifications_none_rounded, title: 'Notification settings', onTap: () => context.push(Routes.notificationSettings)),
              MenuTile(icon: Icons.lock_outline_rounded, title: 'Privacy settings', onTap: () => context.push(Routes.privacySettings)),
              MenuTile(
                icon: Icons.translate_rounded,
                title: 'Language',
                subtitle: locale.languageCode == 'ar' ? 'العربية' : 'English',
                onTap: () => _pickLanguage(context, ref),
              ),
              MenuTile(
                icon: Icons.dark_mode_outlined,
                title: 'Appearance',
                subtitle: switch (themeMode) { ThemeMode.light => 'Light', ThemeMode.dark => 'Dark', ThemeMode.system => 'System default' },
                onTap: () => _pickTheme(context, ref),
              ),
            ],
          ),
          if (ref.watch(isGuardProvider))
            TileGroup(
              title: 'Work',
              children: [
                MenuTile(icon: Icons.shield_outlined, title: 'Switch to guard app', onTap: () => context.go(Routes.guardHome)),
              ],
            ),
          TileGroup(
            title: 'Support',
            children: [
              MenuTile(icon: Icons.support_agent_rounded, title: 'Help desk', onTap: () => context.push(Routes.helpdesk)),
              MenuTile(icon: Icons.contact_emergency_outlined, title: 'Emergency contacts', onTap: () => context.push(Routes.emergencyContacts)),
              MenuTile(icon: Icons.description_outlined, title: 'Terms & conditions', onTap: () => context.push(Routes.terms)),
              MenuTile(icon: Icons.privacy_tip_outlined, title: 'Privacy policy', onTap: () => context.push(Routes.privacyPolicy)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: context.palette.danger),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text('You will need to verify your number again to sign in.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await ref.read(sessionProvider.notifier).logout();
                if (context.mounted) context.go(Routes.login);
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log out'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(child: Text('${AppConfig.appName} · v1.0.0', style: context.text.bodySmall)),
        ],
      ),
    );
  }
}
