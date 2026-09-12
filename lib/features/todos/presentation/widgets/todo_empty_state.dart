import 'package:flutter/material.dart';

import '../../../../core/theme/app_shapes.dart';

/// The placeholder shown when the list has nothing to display.
///
/// Takes its copy from the caller rather than deciding for itself, because the
/// same layout serves four different situations: no todos at all, nothing left
/// to do, no completed items, and no search results.
///
/// Layout note: this is deliberately scrollable and drop-in-height rather than a
/// plain centred [Column]. On a phone with the keyboard open the list can be left
/// with barely 140 logical pixels of height, which is less than the artwork plus
/// two lines of text; a fixed [Column] overflows there and paints the yellow and
/// black warning stripes. The desktop and web targets never shrink that far, so
/// the problem only appears on a real device.
class TodoEmptyState extends StatelessWidget {
  const TodoEmptyState({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Height below which the decorative icon is dropped.
  ///
  /// Chosen so the icon survives a normal phone in portrait but disappears as
  /// soon as the keyboard takes the space, leaving the message readable instead
  /// of scrolling a decorative square into view.
  static const double _artworkMinHeight = 220;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // A parent could hand down an unbounded height; in that case there is
        // nothing to fill, so no minimum is imposed.
        final double minHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 0;
        final bool showArtwork = minHeight >= _artworkMinHeight;

        return SingleChildScrollView(
          child: ConstrainedBox(
            // Fills the viewport when there is room, so [Center] can centre the
            // content; once there is not, the box is free to grow and the scroll
            // view takes over instead of overflowing.
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(showArtwork ? 32 : 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (showArtwork) ...<Widget>[
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh,
                            borderRadius:
                                AppShapes.radius(AppShapes.extraLarge),
                          ),
                          child: Icon(
                            icon,
                            size: 40,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      Text(
                        title,
                        style: text.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        body,
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
