import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../domain/entities/todo_stats.dart';

/// One-line progress summary above the list.
///
/// This used to be a card carrying a headline count, a full-width progress bar
/// and two chips — roughly a sixth of a phone screen, saying the same numbers
/// the navigation bar was already showing as badges. What is left is the part
/// that is not said twice: how much is still open, how far along the whole list
/// is, and whether anything has slipped past its date.
class TodoSummaryHeader extends StatelessWidget {
  const TodoSummaryHeader({required this.stats, super.key});

  final TodoStats stats;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      // Small: this is a caption for the list, not a panel above it.
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
      child: Row(
        children: <Widget>[
          // Flexible, not fixed: at a large accessibility text scale the count
          // is what gives way, rather than the row overflowing off the edge.
          Flexible(
            child: Text(
              AppStrings.activeCount(stats.active),
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (stats.overdue > 0) ...<Widget>[
            const SizedBox(width: 10),
            _OverduePill(count: stats.overdue),
          ],
          const SizedBox(width: 14),
          Expanded(
            child: _ProgressBar(value: stats.progress, color: colors.primary),
          ),
          const SizedBox(width: 10),
          Text(
            AppStrings.progressValue(stats.completed, stats.total),
            style: text.labelMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Slim progress bar.
///
/// Animates on the effects spring: a progress fill is an in-place property
/// change, so it should settle without overshoot rather than bouncing past 100%.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: AppMotion.effectsSlow.duration,
      curve: AppMotion.effectsSlow.curve,
      builder: (BuildContext context, double animated, Widget? child) {
        return ClipRRect(
          borderRadius: AppShapes.radius(AppShapes.full),
          child: LinearProgressIndicator(
            value: animated,
            minHeight: 6,
            color: color,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        );
      },
    );
  }
}

/// The "something is late" marker, shown only when there is something late.
class _OverduePill extends StatelessWidget {
  const _OverduePill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: AppShapes.radius(AppShapes.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.schedule, size: 14, color: colors.onErrorContainer),
          const SizedBox(width: 4),
          Text(
            '${AppStrings.dueOverdue} $count',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
