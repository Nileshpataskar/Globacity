import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/providers.dart';

const _labels = {
  'visitor_at_gate': 'Visitor at gate',
  'daily_help_entry': 'Daily help entry / exit',
  'deliveries': 'Deliveries',
  'notices': 'Notices & broadcasts',
  'payment_reminders': 'Payment reminders',
  'polls_events': 'Polls & events',
  'forum_replies': 'Forum replies',
  'helpdesk_updates': 'Help desk updates',
  'show_in_directory': 'Show me in resident directory',
  'show_phone': 'Show my phone number',
  'show_unit': 'Show my unit number',
  'allow_messages': 'Allow residents to message me',
  'allow_guard_calls': 'Allow guard to call me',
};

/// Server-backed toggles (saved to /me/settings/).
class _ToggleList extends ConsumerWidget {
  const _ToggleList({required this.title, required this.group, required this.intro});

  final String title;
  final String group;
  final String intro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncView<Map<String, Map<String, bool>>>(
        value: ref.watch(userSettingsProvider),
        onRetry: () => ref.invalidate(userSettingsProvider),
        data: (all) {
          final prefs = all[group] ?? {};
          return ListView(
            padding: AppSpacing.screenAll,
            children: [
              Text(intro, style: context.text.bodySmall),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, e) in prefs.entries.indexed) ...[
                      if (i > 0) const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                      SwitchListTile(
                        value: e.value,
                        onChanged: (_) => ref.read(userSettingsProvider.notifier).toggle(group, e.key),
                        title: Text(_labels[e.key] ?? e.key),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _ToggleList(
        title: 'Notification settings',
        group: 'notification_prefs',
        intro: 'Choose which notifications you receive. Entry requests at the gate are always delivered.',
      );
}

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _ToggleList(
        title: 'Privacy settings',
        group: 'privacy_prefs',
        intro: 'Control what other residents and staff can see about you.',
      );
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.isTerms});

  final bool isTerms;

  @override
  Widget build(BuildContext context) {
    final sections = isTerms
        ? [
            ('1. Acceptance', 'By using ${AppConfig.appName} you agree to these terms and to the rules of your community association.'),
            ('2. Accounts', 'You are responsible for keeping your login and OTP codes confidential and for all activity on your account.'),
            ('3. Visitor management', 'Approvals you give through the app are treated as your authorisation for entry into the community.'),
            ('4. Payments', 'Payments are processed by licensed payment partners in your country. Receipts are issued electronically.'),
            ('5. Community conduct', 'Content posted in forums, classifieds and chats must be respectful and lawful. Management may remove content.'),
            ('6. Changes', 'We may update these terms. Continued use after changes means you accept the revised terms.'),
          ]
        : const [
            ('Data we collect', 'Name, contact details, unit information, visitor logs and payment history needed to operate community services.'),
            ('How we use it', 'To manage gate access, process payments, send notifications and provide support.'),
            ('Sharing', 'Data is shared with your community management and security staff only as needed. We never sell personal data.'),
            ('Retention', 'Visitor logs are retained for 12 months unless local law requires otherwise.'),
            ('Your rights', 'You can request access, correction or deletion of your data by contacting ${AppConfig.supportEmail}.'),
          ];
    return Scaffold(
      appBar: AppBar(title: Text(isTerms ? 'Terms & conditions' : 'Privacy policy')),
      body: ListView(
        padding: AppSpacing.screenAll,
        children: [
          Text('Last updated: 1 October 2026', style: context.text.bodySmall),
          for (final (title, body) in sections) ...[
            const SizedBox(height: AppSpacing.xl),
            Text(title, style: context.text.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(body, style: context.text.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}
