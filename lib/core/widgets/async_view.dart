import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/context_ext.dart';
import 'skeleton.dart';
import 'common.dart';

/// Renders an [AsyncValue]: spinner while loading, error with retry, or [data].
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry, this.compact = false, this.skeleton});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  /// Smaller loading/error UI for use inside cards and sections.
  final bool compact;

  /// Custom loading placeholder (defaults to a skeleton list, or skeleton lines when [compact]).
  final Widget? skeleton;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      // Skeleton placeholders instead of spinners, so the screen keeps its shape while loading.
      loading: () => skeleton ?? (compact ? const SkeletonLines() : const SkeletonList()),
      error: (e, _) => compact
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: context.palette.danger, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.toString(), style: context.text.bodySmall)),
                  if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            )
          : EmptyState(
              icon: Icons.cloud_off_rounded,
              title: "Couldn't load",
              message: e.toString(),
              action: onRetry == null ? null : 'Retry',
              onAction: onRetry,
            ),
    );
  }
}

/// Runs a write action, shows its error (or [success]) as a snackbar. Returns null on failure.
Future<T?> runAction<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final result = await action();
    if (success != null && context.mounted) context.showSnack(success);
    return result;
  } catch (e) {
    if (context.mounted) context.showSnack(e.toString());
    return null;
  }
}

/// Pull-to-refresh wrapper that re-fetches [provider].
class RefreshList extends ConsumerWidget {
  const RefreshList({super.key, required this.onRefresh, required this.child});

  final Future<void> Function(WidgetRef ref) onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      RefreshIndicator(onRefresh: () => onRefresh(ref), child: child);
}
