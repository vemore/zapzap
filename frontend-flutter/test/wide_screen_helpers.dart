import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/widgets/content_column.dart';

/// The windows each screen's `wide screen` group lays it out in: a laptop
/// or a landscape tablet, a desktop monitor, and a portrait tablet — the
/// width `GameScreen.wideBreakpoint` starts the wide board at.
const wideScreens = <String, Size>{
  '1280×800': Size(1280, 800),
  '1920×1080': Size(1920, 1080),
  '800×1280': Size(800, 1280),
};

/// The text scales of the `wide screen` groups: a desktop browser's zoom
/// rarely goes past 150 %.
const wideTextScales = [1.0, 1.5];

/// Each of [finder]'s widgets lies inside the content column of a window
/// [windowWidth] wide ([ContentColumn]).
void expectInContentColumn(
  WidgetTester tester,
  Finder finder, {
  required double windowWidth,
}) {
  const slack = 0.5;
  final inset = ContentColumn.inset(windowWidth);
  final elements = finder.evaluate().toList();
  expect(elements, isNotEmpty, reason: 'nothing found by $finder');
  for (final element in elements) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    expect(
      rect.left >= inset - slack && rect.right <= windowWidth - inset + slack,
      isTrue,
      reason:
          '$rect is outside the content column '
          '[$inset, ${windowWidth - inset}] of a $windowWidth px window',
    );
  }
}

/// The rect that holds every widget [finder] finds.
Rect unionRect(WidgetTester tester, Finder finder) => finder
    .evaluate()
    .map((element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    })
    .reduce((a, b) => a.expandToInclude(b));
