import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../domain/entities/todo_stats.dart';

/// Progress summary above the list.
///
/// Stateless by design: it renders whatever [stats] it is handed, so the page
/// stays in charge of loading and error states and this widget never has to
/// guess what to show.
class TodoSummaryHeader extends StatelessWidget {
  const TodoSummaryHeader({required this.stats, super.key});

  final TodoStats stats;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Text(
                    AppStrings.activeCount(stats.active),
                    style: text.headlineSmall,
                  ),
                ),
                Text(
                  AppStrings.progressValue(stats.completed, stats.total),
                  style: text.titleMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // The bar animates on the effects spring: a progress fill is an
            // in-place property change, so it should settle without overshoot
            // rather than bouncing past 100%.
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: stats.progress),
              duration: AppMotion.effectsSlow.duration,
              curve: AppMotion.effectsSlow.curve,
              builder: (BuildContext context, double value, Widget? child) {
                return ClipRRect(
                  borderRadius: AppShapes.radius(AppShapes.full),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: colors.surfaceContainerHighest,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _StatChip(
                  icon: Icons.task_alt,
                  label: AppStrings.navCompleted,
                  value: stats.completed,
                  background: colors.secondaryContainer,
                  foreground: colors.onSecondaryContainer,
                ),
                if (stats.overdue > 0)
                  _StatChip(
                    icon: Icons.schedule,
                    label: AppStrings.dueOverdue,
                    value: stats.overdue,
                    background: colors.errorContainer,
                    foreground: colors.onErrorContainer,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact `icon label value` pill.
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppShapes.radius(AppShapes.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: text.labelLarge?.copyWith(color: foreground),
          ),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: text.labelLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
