import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The one column every list and form screen lays its content in: the
/// whole width on a phone, less a [gutter] on each side, and never wider
/// than [maxWidth] — centred, with the rest of a wide window left empty.
///
/// It hands its [builder] the padding that does it rather than wrapping the
/// content in a narrower box, so a scroll view keeps the whole window: the
/// wheel scrolls it wherever the pointer is, and its scrollbar sits at the
/// window's edge, not in the middle of the screen.
class ContentColumn extends StatelessWidget {
  const ContentColumn({
    super.key,
    required this.builder,
    this.top = gutter,
    this.bottom = gutter,
  });

  /// The widest the content grows: three party cards side by side, the
  /// statistics in two columns.
  static const maxWidth = 960.0;

  /// The least space on each side, a phone's margin.
  static const gutter = 16.0;

  /// Builds the content with [padding]: [top] and [bottom] as given, the
  /// sides what centres [maxWidth] in the width available.
  final Widget Function(BuildContext context, EdgeInsets padding) builder;

  final double top;
  final double bottom;

  /// The space on each side in [width]: [gutter], or more past [maxWidth].
  static double inset(double width) => math.max(gutter, (width - maxWidth) / 2);

  /// The content's own width in [width].
  static double contentWidth(double width) =>
      math.max(0, width - 2 * inset(width));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = inset(constraints.maxWidth);
      return builder(context, EdgeInsets.fromLTRB(side, top, side, bottom));
    },
  );
}

/// [children] in rows of up to [maxColumns], each at least [minWidth] wide,
/// [spacing] apart: one column on a phone, more on a wide screen.
///
/// Rows rather than a `GridView`: a grid tile needs a height decided before
/// its content is laid out, and any fixed one is too short at a large
/// system font size. A row takes its tallest child's height and stretches
/// the others to it, so the children must not hold a `LayoutBuilder`
/// (`IntrinsicHeight`).
class ContentGrid extends StatelessWidget {
  const ContentGrid({
    super.key,
    required this.children,
    this.minWidth = 300,
    this.maxColumns = 3,
    this.spacing = 12,
    this.runSpacing = 10,
  });

  final List<Widget> children;
  final double minWidth;
  final int maxColumns;
  final double spacing;
  final double runSpacing;

  /// How many columns of [minWidth] fit [width].
  static int columnsFor(
    double width, {
    double minWidth = 300,
    int maxColumns = 3,
    double spacing = 12,
  }) => ((width + spacing) ~/ (minWidth + spacing)).clamp(1, maxColumns);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = columnsFor(
        constraints.maxWidth,
        minWidth: minWidth,
        maxColumns: maxColumns,
        spacing: spacing,
      );
      if (columns == 1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0) SizedBox(height: runSpacing),
              child,
            ],
          ],
        );
      }
      final rows = (children.length + columns - 1) ~/ columns;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var row = 0; row < rows; row++) ...[
            if (row > 0) SizedBox(height: runSpacing),
            ContentGrid.row(
              children.skip(row * columns).take(columns).toList(),
              columns: columns,
              spacing: spacing,
            ),
          ],
        ],
      );
    },
  );

  /// One row of [columns] cells holding [children], each as tall as the
  /// tallest; the cells past the children stay empty, so the children keep
  /// a column's width.
  static Widget row(
    List<Widget> children, {
    required int columns,
    double spacing = 12,
  }) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var column = 0; column < columns; column++) ...[
          if (column > 0) SizedBox(width: spacing),
          Expanded(
            child: column < children.length
                ? children[column]
                : const SizedBox.shrink(),
          ),
        ],
      ],
    ),
  );
}
