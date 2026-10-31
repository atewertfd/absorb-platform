import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Extra room [height] worth of text needs at the user's text size: zero at
/// the normal size (and smaller), so layouts sized in fixed pixels only grow
/// when the text inside them does. Fork helper (Absorb Plus) for upstream
/// layouts that reserve a fixed height for labels.
double textScaleRoom(BuildContext context, double height) =>
    math.max(0, MediaQuery.textScalerOf(context).scale(height) - height);

/// A fixed-column grid whose cells get [labelRoom] extra height under the
/// size [childAspectRatio] (or [mainAxisExtent]) gives them, for the labels
/// below each cover. With bigger text the labels need more than the ratio
/// leaves, and a plain ratio would push them out of the cell.
class LabelRoomGridDelegate extends SliverGridDelegateWithFixedCrossAxisCount {
  const LabelRoomGridDelegate({
    required super.crossAxisCount,
    super.mainAxisSpacing,
    super.crossAxisSpacing,
    super.childAspectRatio,
    super.mainAxisExtent,
    this.labelRoom = 0,
  });

  final double labelRoom;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final base = super.getLayout(constraints);
    if (labelRoom <= 0 || base is! SliverGridRegularTileLayout) return base;
    return SliverGridRegularTileLayout(
      crossAxisCount: base.crossAxisCount,
      mainAxisStride: base.mainAxisStride + labelRoom,
      crossAxisStride: base.crossAxisStride,
      childMainAxisExtent: base.childMainAxisExtent + labelRoom,
      childCrossAxisExtent: base.childCrossAxisExtent,
      reverseCrossAxis: base.reverseCrossAxis,
    );
  }

  @override
  bool shouldRelayout(SliverGridDelegateWithFixedCrossAxisCount oldDelegate) =>
      super.shouldRelayout(oldDelegate) ||
      oldDelegate is! LabelRoomGridDelegate ||
      oldDelegate.labelRoom != labelRoom;
}

/// How many lines of [fontSize] text (line height [lineHeight] times the
/// font size) fit in [maxHeight] at the user's text size, from 1 to [max].
/// For multi-line labels in boxes that can be shorter than [max] lines:
/// asking for more lines than fit cuts the last one in half instead of
/// ending it with an ellipsis.
int linesThatFit(
  BuildContext context,
  double maxHeight, {
  required double fontSize,
  required double lineHeight,
  required int max,
}) {
  if (!maxHeight.isFinite) return max;
  final line = MediaQuery.textScalerOf(context).scale(fontSize) * lineHeight;
  return (maxHeight / line).floor().clamp(1, max);
}
