import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class ForumScreen extends ConsumerWidget {
  const ForumScreen({super.key});

  void _newPost(BuildContext context, WidgetRef ref) {
    final title = TextEditingController();
    final body = TextEditingController();
    showAppSheet(
      context,
      title: 'Start a discussion',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: body, maxLines: 5,
              decoration: const InputDecoration(labelText: "What's on your mind?", alignLabelWithHint: true)),
          const SizedBox(height: AppSpacing.lg),
          Builder(
            builder: (sheetContext) => FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                final ok = await runAction(sheetContext, () async {
                  await ref.read(actionsProvider).createPost(title.text.trim(), body.text.trim());
                  return true;
                });
                if (ok == true && sheetContext.mounted) Navigator.pop(sheetContext);
              },
              child: const Text('Post'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forum')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'forum',
        onPressed: () => _newPost(context, ref),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New post'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(forumProvider.future),
        child: AsyncView<List<ForumPost>>(
          value: ref.watch(forumProvider),
          onRetry: () => ref.invalidate(forumProvider),
          data: (posts) => posts.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.forum_outlined, title: 'No discussions yet')])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
                  itemCount: posts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) {
                    final p = posts[i];
                    return AppCard(
                      onTap: () => context.push(Routes.forumPost(p.id)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AuthorRow(post: p),
                          const SizedBox(height: AppSpacing.md),
                          Text(p.title, style: context.text.titleSmall),
                          const SizedBox(height: AppSpacing.xs),
                          Text(p.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              StatusChip(label: p.tag, tone: Tone.primary),
                              const Spacer(),
                              Icon(p.liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined, size: 16,
                                  color: p.liked ? context.scheme.primary : context.palette.textMuted),
                              Text(' ${p.likes}', style: context.text.bodySmall),
                              const SizedBox(width: AppSpacing.md),
                              Icon(Icons.chat_bubble_outline_rounded, size: 16, color: context.palette.textMuted),
                              Text(' ${p.repliesCount}', style: context.text.bodySmall),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  const _AuthorRow({required this.post});

  final ForumPost post;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppAvatar(name: post.author, size: 36),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(post.author, style: context.text.titleSmall),
              Text('${post.unit} · ${Fmt.relative(post.time)}', style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class ForumPostScreen extends ConsumerStatefulWidget {
  const ForumPostScreen({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<ForumPostScreen> createState() => _ForumPostScreenState();
}

class _ForumPostScreenState extends ConsumerState<ForumPostScreen> {
  final _reply = TextEditingController();

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final ok = await runAction(context, () async {
      await ref.read(actionsProvider).reply(widget.postId, text);
      return true;
    });
    if (ok == true) {
      _reply.clear();
      if (mounted) FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.watch(forumPostProvider(widget.postId));
    final replies = ref.watch(forumRepliesProvider(widget.postId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discussion'),
        actions: [
          if (post.value != null)
            IconButton(
              onPressed: () => runAction(context, () => ref.read(actionsProvider).like(widget.postId)),
              icon: Icon(post.value!.liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined),
            ),
        ],
      ),
      body: AsyncView<ForumPost>(
        value: post,
        onRetry: () => ref.invalidate(forumPostProvider(widget.postId)),
        data: (p) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: AppSpacing.screenAll,
                children: [
                  _AuthorRow(post: p),
                  const SizedBox(height: AppSpacing.lg),
                  Text(p.title, style: context.text.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text(p.body, style: context.text.bodyLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text('${p.likes} likes', style: context.text.bodySmall),
                  SectionHeader(title: '${replies.value?.length ?? p.repliesCount} replies'),
                  AsyncView<List<ForumReply>>(
                    value: replies,
                    compact: true,
                    data: (list) => Column(
                      children: [
                        for (final r in list) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppAvatar(name: r.author, size: 32),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(color: context.palette.surfaceAlt, borderRadius: AppRadius.fieldRadius),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${r.author} · ${Fmt.relative(r.time)}', style: context.text.labelMedium),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(r.body, style: context.text.bodyMedium),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (p.isLocked)
              Padding(padding: AppSpacing.screenAll, child: Text('This discussion is locked.', style: context.text.bodySmall))
            else
              MessageComposer(controller: _reply, hint: 'Write a reply…', onSend: _send),
          ],
        ),
      ),
    );
  }
}
