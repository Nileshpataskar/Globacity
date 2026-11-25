import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_scaffold.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/providers.dart';
import 'auth_flow.dart';

/// Verifies the SMS code and signs in (creating the account on first login).
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone, this.devCode});

  final String phone;

  /// Code returned by a DEBUG backend, shown as a hint during development.
  final String? devCode;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _seconds = 30;
  bool _verifying = false;
  String? _devCode;
  String? _signupWarning;

  @override
  void initState() {
    super.initState();
    _devCode = widget.devCode;
    _startTimer();
    _controller.addListener(() => setState(() {}));
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _seconds = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds == 0) {
        t.cancel();
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    final ok = await runAction(context, () async {
      final session = ref.read(sessionProvider.notifier);
      final signup = ref.read(pendingSignupProvider);
      await session.verifyOtp(widget.phone, _controller.text, fullName: signup?.name);
      if (signup != null) {
        ref.read(pendingSignupProvider.notifier).set(null);
        try {
          await session.completeSignup(signup);
        } catch (e) {
          // The account exists and is signed in; profile details can be fixed later in Profile.
          _signupWarning = 'Account created, but some details were not saved: $e';
        }
      }
      return true;
    });
    if (!mounted) return;
    if (ok == true) {
      if (_signupWarning != null) context.showSnack(_signupWarning!);
      await goAfterSignIn(context, ref);
    } else {
      _controller.clear();
      setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    final code = await runAction(context, () => ref.read(sessionProvider.notifier).requestOtp(widget.phone),
        success: 'A new code has been sent');
    if (mounted) setState(() => _devCode = code ?? _devCode);
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final code = _controller.text;
    return AuthScaffold(
      title: "Verify it's you",
      subtitle: 'Enter the 6-digit code sent to ${widget.phone}',
      icon: Icons.sms_rounded,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              if (_devCode != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  color: context.palette.info.withValues(alpha: 0.08),
                  borderColor: context.palette.info.withValues(alpha: 0.3),
                  onTap: () => _controller.text = _devCode!,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(Icons.developer_mode_rounded, color: context.palette.info, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text('Development code: $_devCode (tap to fill)', style: context.text.bodySmall)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              GestureDetector(
                onTap: () => _focus.requestFocus(),
                child: Stack(
                  children: [
                    Opacity(
                      opacity: 0,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        onSubmitted: (_) => code.length == 6 ? _verify() : null,
                      ),
                    ),
                    Row(
                      children: List.generate(6, (i) {
                        final filled = i < code.length;
                        final active = i == code.length && _focus.hasFocus;
                        return Expanded(
                          child: Container(
                            height: 56,
                            margin: EdgeInsetsDirectional.only(end: i == 5 ? 0 : AppSpacing.sm),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: context.scheme.surface,
                              borderRadius: AppRadius.fieldRadius,
                              border: Border.all(
                                color: active || filled ? context.scheme.primary : context.palette.border,
                                width: active ? 1.8 : 1,
                              ),
                            ),
                            child: Text(filled ? code[i] : '', style: context.text.headlineSmall),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Center(
                child: _seconds > 0
                    ? Text('Resend code in 0:${_seconds.toString().padLeft(2, '0')}', style: context.text.bodySmall)
                    : TextButton(onPressed: _resend, child: const Text('Resend code')),
              ),
              const SizedBox(height: AppSpacing.xl),
              GradientButton(
                label: 'Verify & continue',
                icon: Icons.check_rounded,
                busy: _verifying,
                onPressed: code.length == 6 ? _verify : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded, size: 14, color: context.palette.textMuted),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text('Protected with two-factor authentication', style: context.text.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
