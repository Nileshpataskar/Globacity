import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_scaffold.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/providers.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _sent = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_email.text.contains('@')) {
      context.showSnack('Enter a valid email address');
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await ref.read(apiProvider).post('/auth/password/forgot/', data: {'email': _email.text.trim()}, auth: false);
      return true;
    });
    if (mounted) {
      setState(() {
        _busy = false;
        _sent = ok == true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Forgot password?',
      subtitle: "Enter your account email and we'll send reset instructions.",
      icon: Icons.key_rounded,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: _sent
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    const EmptyState(
                      icon: Icons.mark_email_read_rounded,
                      title: 'Check your inbox',
                      message: 'If that email is registered, we have sent instructions to reset your password.',
                    ),
                    const Spacer(),
                    FilledButton(onPressed: () => context.pop(), child: const Text('Back to sign in')),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    LabeledField(
                      label: 'Email',
                      child: TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(hintText: 'you@example.com', prefixIcon: Icon(Icons.mail_outline_rounded)),
                      ),
                    ),
                    FilledButton(onPressed: _busy ? null : _send, child: const Text('Send reset instructions')),
                  ],
                ),
        ),
      ),
    );
  }
}
