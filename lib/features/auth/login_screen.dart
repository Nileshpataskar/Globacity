import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_scaffold.dart';
import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'auth_flow.dart';

enum _Mode { phone, email }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.phone;
  CountryOption? _country;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(List<CountryOption> countries) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final session = ref.read(sessionProvider.notifier);
    if (_mode == _Mode.phone) {
      final phone = '${(_country ?? _defaultCountry(countries)).phoneCode}${_phone.text}';
      try {
        final devCode = await session.requestOtp(phone);
        if (mounted) {
          context.push('${Routes.otp}?to=${Uri.encodeComponent(phone)}${devCode != null ? '&dev=$devCode' : ''}');
        }
      } catch (e) {
        if (mounted) context.showSnack(e.toString());
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      final ok = await runAction(context, () async {
        await session.loginWithPassword(_email.text.trim(), _password.text);
        return true;
      });
      if (ok == true && mounted) await goAfterSignIn(context, ref);
      if (mounted) setState(() => _busy = false);
    }
  }

  CountryOption _defaultCountry(List<CountryOption> countries) =>
      countries.firstWhere((c) => c.iso2 == 'AE', orElse: () => countries.first);

  @override
  Widget build(BuildContext context) {
    final countries = ref.watch(countriesProvider);
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to manage your home and community.',
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(value: _Mode.phone, label: Text('Mobile'), icon: Icon(Icons.phone_iphone_rounded)),
                    ButtonSegment(value: _Mode.email, label: Text('Password'), icon: Icon(Icons.lock_outline_rounded)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: AppSpacing.xl),
                AsyncView<List<CountryOption>>(
                  value: countries,
                  compact: true,
                  onRetry: () => ref.invalidate(countriesProvider),
                  data: (list) => _mode == _Mode.phone ? _phoneForm(list) : _passwordForm(),
                ),
                const SizedBox(height: AppSpacing.sm),
                GradientButton(
                  label: _mode == _Mode.phone ? 'Send OTP' : 'Sign in',
                  icon: Icons.arrow_forward_rounded,
                  busy: _busy,
                  onPressed: !countries.hasValue ? null : () => _submit(countries.value!),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("Don't have an account?", style: context.text.bodyMedium),
                    TextButton(onPressed: () => context.push(Routes.signup), child: const Text('Sign up')),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Text('or continue with', style: context.text.bodySmall),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                for (final (icon, label) in [
                  (Icons.g_mobiledata_rounded, 'Continue with Google'),
                  (Icons.apple_rounded, 'Continue with Apple'),
                ]) ...[
                  OutlinedButton.icon(
                    onPressed: () => context.showSnack('Single sign-on will be enabled once provider keys are set up.'),
                    icon: Icon(icon, size: 26),
                    label: Text(label),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    Text('By continuing you agree to our ', style: context.text.bodySmall),
                    _Link('Terms', () => context.push(Routes.terms)),
                    Text(' and ', style: context.text.bodySmall),
                    _Link('Privacy Policy', () => context.push(Routes.privacyPolicy)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneForm(List<CountryOption> countries) {
    final country = _country ?? (countries.isEmpty ? null : _defaultCountry(countries));
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
                    for (final c in countries) PopupMenuItem(value: c, child: Text('${c.flag}  ${c.name} (${c.phoneCode})')),
                  ],
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: AppSpacing.lg, end: AppSpacing.sm),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${country.flag} ${country.phoneCode}', style: context.text.titleSmall),
                        const Icon(Icons.arrow_drop_down_rounded),
                      ],
                    ),
                  ),
                ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        ),
        validator: (v) =>
            (v == null || v.length != (country?.length ?? 9)) ? 'Enter ${country?.length ?? 9} digits' : null,
      ),
    );
  }

  Widget _passwordForm() {
    return Column(
      children: [
        LabeledField(
          label: 'Email or phone',
          child: TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'you@example.com or +971500000002',
                prefixIcon: Icon(Icons.person_outline_rounded)),
            validator: (v) => (v == null || v.trim().length < 5) ? 'Enter your email or phone' : null,
          ),
        ),
        LabeledField(
          label: 'Password',
          child: TextFormField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: '••••••••',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(onPressed: () => context.push(Routes.forgotPassword), child: const Text('Forgot password?')),
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Text(label, style: context.text.bodySmall?.copyWith(color: context.scheme.primary, fontWeight: FontWeight.w600)),
      );
}
