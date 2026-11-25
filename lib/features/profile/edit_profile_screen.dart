import '../../core/utils/device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/providers.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final _user = ref.read(userProvider);
  late final _name = TextEditingController(text: _user.name == _user.phone ? '' : _user.name);
  late final _email = TextEditingController(text: _user.email);
  bool _saving = false;
  bool _uploading = false;

  Future<void> _changePhoto() async {
    final photo = await Device.pickImage(context);
    if (photo == null || !mounted) return;
    setState(() => _uploading = true);
    await runAction(context, () => ref.read(sessionProvider.notifier).updateAvatar(photo), success: 'Photo updated');
    if (mounted) setState(() => _uploading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      await ref.read(sessionProvider.notifier).updateProfile(name: _name.text.trim(), email: _email.text.trim());
      return true;
    }, success: 'Profile updated');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: AppSpacing.screenAll,
            child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Save changes'))),
      ),
      body: ListView(
        padding: AppSpacing.screenAll,
        children: [
          Center(
            child: Stack(
              children: [
                AppAvatar(name: _name.text.isEmpty ? '?' : _name.text, size: 96, imageUrl: ref.watch(userProvider).avatarUrl),
                PositionedDirectional(
                  end: 0,
                  bottom: 0,
                  child: IconButton.filled(
                    onPressed: _uploading ? null : _changePhoto,
                    icon: _uploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.camera_alt_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          LabeledField(
            label: 'Full name',
            child: TextField(controller: _name, onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded))),
          ),
          LabeledField(
            label: 'Email',
            child: TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline_rounded))),
          ),
          LabeledField(
            label: 'Mobile number',
            child: TextField(
              controller: TextEditingController(text: _user.phone),
              enabled: false,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_outlined),
                  helperText: 'Contact management to change your registered number'),
            ),
          ),
        ],
      ),
    );
  }
}
