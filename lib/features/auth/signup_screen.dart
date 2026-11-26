import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_scaffold.dart';
import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api/api_client.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Create an account: details -> OTP verification -> join community.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key, this.initialPhone, this.initialCountry});

  /// Number carried over from the login screen ("not registered → sign up").
  final String? initialPhone;
  final String? initialCountry;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _phone = TextEditingController(text: widget.initialPhone ?? '');
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  CountryOption? _country;
  bool _agreed = false;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  CountryOption _defaultCountry(List<CountryOption> list) =>
      list.firstWhere((c) => c.iso2 == (widget.initialCountry ?? 'IN'), orElse: () => list.first);

  Future<void> _submit(List<CountryOption> countries) async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      context.showSnack('Please accept the Terms and Privacy Policy');
      return;
    }
    final phone = '${(_country ?? _defaultCountry(countries)).phoneCode}${_phone.text}';
    ref.read(pendingSignupProvider.notifier).set(PendingSignup(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
        ));
    setState(() => _busy = true);
    try {
      final devCode = await ref.read(sessionProvider.notifier).requestOtp(phone, purpose: 'signup');
      if (mounted) {
        context.push('${Routes.otp}?to=${Uri.encodeComponent(phone)}${devCode != null ? '&dev=$devCode' : ''}');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'already_registered') {
        ref.read(pendingSignupProvider.notifier).set(null);
        final signIn = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.how_to_reg_rounded, size: 36),
            title: const Text('Already registered'),
            content: Text('$phone already has an account. Sign in with this number instead.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign in')),
            ],
          ),
        );
        if (signIn == true && mounted) context.canPop() ? context.pop() : context.go(Routes.login);
      } else {
        context.showSnack(e.message);
      }
    } catch (e) {
      if (mounted) context.showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final countries = ref.watch(countriesProvider);
    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Join your community in a minute. We will verify your mobile number.',
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.sm),
                LabeledField(
                  label: 'Full name',
                  child: TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'e.g. Aarav Mehta', prefixIcon: Icon(Icons.person_outline_rounded)),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                  ),
                ),
                AsyncView<List<CountryOption>>(
                  value: countries,
                  compact: true,
                  onRetry: () => ref.invalidate(countriesProvider),
                  data: (list) {
                    final country = _country ?? (list.isEmpty ? null : _defaultCountry(list));
                    return LabeledField(
                      label: 'Mobile number',
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(country?.length ?? 12)],
                        decoration: InputDecoration(
                          hintText: '${country?.length ?? 9} digits',
                          prefixIcon: country == null
                              ? null
                              : PopupMenuButton<CountryOption>(
                                  tooltip: 'Country',
                                  onSelected: (c) => setState(() => _country = c),
                                  itemBuilder: (_) => [
                                    for (final c in list) PopupMenuItem(value: c, child: Text('${c.flag}  ${c.name} (${c.phoneCode})')),
                                  ],
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(start: AppSpacing.lg, end: AppSpacing.sm),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Text('${country.flag} ${country.phoneCode}', style: context.text.titleSmall),
                                      const Icon(Icons.arrow_drop_down_rounded),
                                    ]),
                                  ),
                                ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        ),
                        validator: (v) => (v == null || v.length != (country?.length ?? 9)) ? 'Enter ${country?.length ?? 9} digits' : null,
                      ),
                    );
                  },
                ),
                LabeledField(
                  label: 'Email (optional)',
                  child: TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(hintText: 'you@example.com', prefixIcon: Icon(Icons.mail_outline_rounded)),
                    validator: (v) => (v != null && v.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v))
                        ? 'Enter a valid email'
                        : null,
                  ),
                ),
                LabeledField(
                  label: 'Password (optional, for email or password login)',
                  child: TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: 'At least 8 characters',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v != null && v.isNotEmpty && v.length < 8) ? 'Minimum 8 characters' : null,
                  ),
                ),
                LabeledField(
                  label: 'Confirm password',
                  child: TextFormField(
                    controller: _confirm,
                    obscureText: _obscure,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline_rounded)),
                    validator: (v) => (v ?? '') != _password.text ? 'Passwords do not match' : null,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(value: _agreed, onChanged: (v) => setState(() => _agreed = v ?? false)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text.rich(TextSpan(
                          style: context.text.bodySmall,
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms',
                              style: TextStyle(color: context.scheme.primary, fontWeight: FontWeight.w600),
                              recognizer: TapGestureRecognizer()..onTap = () => context.push(Routes.terms),
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: TextStyle(color: context.scheme.primary, fontWeight: FontWeight.w600),
                              recognizer: TapGestureRecognizer()..onTap = () => context.push(Routes.privacyPolicy),
                            ),
                          ],
                        )),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                GradientButton(
                  label: 'Continue',
                  icon: Icons.arrow_forward_rounded,
                  busy: _busy,
                  onPressed: !countries.hasValue ? null : () => _submit(countries.value!),
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Already have an account?', style: context.text.bodyMedium),
                    TextButton(onPressed: () => context.pop(), child: const Text('Sign in')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
