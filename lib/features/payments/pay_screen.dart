import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Checkout. The backend picks the gateway configured for the community's country
/// (mock in development; Noqodi / Razorpay / Stripe once configured).
class PayScreen extends ConsumerStatefulWidget {
  const PayScreen({super.key, required this.dueIds});

  final List<String> dueIds;

  @override
  ConsumerState<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends ConsumerState<PayScreen> {
  static const _methods = [
    (Icons.credit_card_rounded, 'card', 'Debit / credit card', 'Visa, Mastercard, AMEX'),
    (Icons.apple_rounded, 'apple_pay', 'Apple Pay', 'Pay with Face ID'),
    (Icons.g_mobiledata_rounded, 'google_pay', 'Google Pay', 'Pay with your Google account'),
    (Icons.account_balance_rounded, 'bank_transfer', 'Bank transfer', 'Direct debit'),
  ];

  int _method = 0;
  bool _processing = false;
  Payment? _done;

  Future<void> _pay(List<Due> dues) async {
    setState(() => _processing = true);
    final actions = ref.read(actionsProvider);
    final payment = await runAction(context, () async {
      final checkout = await actions.checkout(dues.map((d) => d.id).toList(), _methods[_method].$2);
      if (checkout.gateway != 'mock') {
        throw Exception('Gateway "${checkout.gateway}" checkout UI is not integrated yet.');
      }
      // Development gateway: confirm immediately. A real gateway opens its hosted page here.
      return actions.confirmMockPayment(checkout.paymentId);
    });
    if (!mounted) return;
    setState(() {
      _processing = false;
      _done = payment;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done != null) return _Success(payment: _done!);
    final ctx = ref.watch(contextProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: AsyncView<List<Due>>(
        value: ref.watch(duesProvider),
        onRetry: () => ref.invalidate(duesProvider),
        data: (all) {
          final dues = all.where((d) => widget.dueIds.contains(d.id)).toList();
          if (dues.isEmpty) return const EmptyState(icon: Icons.receipt_long_rounded, title: 'Nothing to pay');
          final currency = dues.first.currency;
          final total = dues.fold<double>(0, (s, d) => s + d.amount);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: AppSpacing.screenAll,
                  children: [
                    Text('Summary', style: context.text.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        children: [
                          for (final d in dues)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${d.title} · ${d.period}', style: context.text.bodyMedium),
                                        if (d.taxLabel.isNotEmpty) Text(d.taxLabel, style: context.text.bodySmall),
                                      ],
                                    ),
                                  ),
                                  Text(Fmt.money(d.amount, d.currency), style: context.text.titleSmall),
                                ],
                              ),
                            ),
                          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: Divider()),
                          Row(
                            children: [
                              Expanded(child: Text('Total', style: context.text.titleMedium)),
                              Text(Fmt.money(total, currency), style: context.text.titleLarge),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SectionHeader(title: 'Payment method'),
                    for (var i = 0; i < _methods.length; i++) ...[
                      AppCard(
                        onTap: () => setState(() => _method = i),
                        borderColor: _method == i ? context.scheme.primary : null,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                        child: Row(
                          children: [
                            IconBadge(icon: _methods[i].$1, size: 40),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [Text(_methods[i].$3, style: context.text.titleSmall),
                                  Text(_methods[i].$4, style: context.text.bodySmall)],
                              ),
                            ),
                            Icon(_method == i ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                color: _method == i ? context.scheme.primary : context.palette.textMuted),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded, size: 14, color: context.palette.textMuted),
                        const SizedBox(width: AppSpacing.xs),
                        Text(ctx == null ? 'Secure payment' : 'Secure payment · amounts in ${ctx.currencyCode}',
                            style: context.text.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: AppSpacing.screenAll,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _processing ? null : () => _pay(dues),
                      child: _processing
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                          : Text('Pay ${Fmt.money(total, currency)}'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(color: context.palette.success.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, size: 56, color: context.palette.success),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Payment successful', style: context.text.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(Fmt.money(payment.amount, payment.currency),
                    style: context.text.displaySmall?.copyWith(color: context.palette.success)),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Column(
                  children: [
                    InfoRow(icon: Icons.receipt_rounded, label: 'For', value: payment.title),
                    InfoRow(icon: Icons.credit_card_rounded, label: 'Method', value: payment.method),
                    InfoRow(icon: Icons.tag_rounded, label: 'Reference', value: payment.reference),
                    InfoRow(icon: Icons.schedule_rounded, label: 'Date', value: Fmt.dateTime(payment.date)),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(onPressed: () => context.pop(), child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}
