import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// One-to-one chat. New messages arrive over the realtime connection.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId, required this.name});

  final String conversationId;
  final String name;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await runAction(context, () async {
      await ref.read(actionsProvider).sendMessage(widget.conversationId, text);
      return true;
    });
    if (ok == true) _input.clear();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = chatMessagesProvider(widget.conversationId);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            AppAvatar(name: widget.name, size: 36),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(widget.name, style: context.text.titleSmall)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AsyncView<List<ChatMessage>>(
              value: ref.watch(provider),
              onRetry: () => ref.invalidate(provider),
              data: (messages) => messages.isEmpty
                  ? EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'Say hello to ${widget.name.split(' ').first}')
                  : ListView.builder(
                      reverse: true,
                      padding: AppSpacing.screenAll,
                      itemCount: messages.length,
                      itemBuilder: (_, i) => _Bubble(message: messages[messages.length - 1 - i]),
                    ),
            ),
          ),
          MessageComposer(controller: _input, hint: 'Type a message', onSend: _send),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return Align(
      alignment: m.mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: m.mine ? context.scheme.primary : context.scheme.surface,
          border: m.mine ? null : Border.all(color: context.palette.border),
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(AppRadius.lg),
            topEnd: const Radius.circular(AppRadius.lg),
            bottomStart: Radius.circular(m.mine ? AppRadius.lg : 4),
            bottomEnd: Radius.circular(m.mine ? 4 : AppRadius.lg),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(m.text, style: context.text.bodyMedium?.copyWith(color: m.mine ? context.scheme.onPrimary : null)),
            const SizedBox(height: 2),
            Text(Fmt.time(m.time),
                style: context.text.labelSmall?.copyWith(color: m.mine ? context.scheme.onPrimary.withValues(alpha: 0.7) : null)),
          ],
        ),
      ),
    );
  }
}
