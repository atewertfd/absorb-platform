import 'package:flutter/material.dart';

/// One day of listening for the stats charts.
class ChartDay {
  final String label;
  final String dateKey;
  final double seconds;
  const ChartDay({required this.label, required this.dateKey, required this.seconds});
}

/// Line chart over the chart range. Colors are passed in because
/// CustomPainters can't read Theme.of(context).
class StatsLineChart extends StatelessWidget {
  final List<ChartDay> data;
  final String todayKey;
  final double animValue;
  final Color lineColor;
  final Color labelColor;
  final Color todayColor;
  final String Function(double seconds) formatValue;
  final int selectedIndex;
  final void Function(int index)? onDaySelected;

  const StatsLineChart({
    super.key,
    required this.data,
    required this.todayKey,
    required this.animValue,
    required this.lineColor,
    required this.labelColor,
    required this.todayColor,
    required this.formatValue,
    this.selectedIndex = -1,
    this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final dense = data.length > 10;
    return Column(children: [
      LayoutBuilder(builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onDaySelected == null || data.length < 2
              ? null
              : (details) {
                  final i = (details.localPosition.dx /
                          constraints.maxWidth *
                          (data.length - 1))
                      .round()
                      .clamp(0, data.length - 1);
                  onDaySelected!(i);
                },
          child: SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: _LinePainter(
                values: data.map((d) => d.seconds).toList(),
                animValue: animValue,
                lineColor: lineColor,
                labelColor: labelColor,
                formatValue: formatValue,
                selectedIndex: selectedIndex,
              ),
            ),
          ),
        );
      }),
      const SizedBox(height: 8),
      Row(
        children: [
          for (var i = 0; i < data.length; i++)
            Expanded(
              child: Text(
                dense ? (i % 5 == 0 ? data[i].label : '') : data[i].label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: data[i].dateKey == todayKey
                      ? todayColor.withValues(alpha: 0.8)
                      : labelColor.withValues(alpha: 0.25),
                  fontSize: 10,
                  fontWeight:
                      data[i].dateKey == todayKey ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final double animValue;
  final Color lineColor;
  final Color labelColor;
  final String Function(double seconds) formatValue;
  final int selectedIndex;

  _LinePainter({
    required this.values,
    required this.animValue,
    required this.lineColor,
    required this.labelColor,
    required this.formatValue,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = values.fold(0.0, (a, b) => a > b ? a : b);
    final scale = maxVal > 0 ? maxVal : 1.0;
    const topPad = 18.0;
    final plotHeight = size.height - topPad;

    Offset pointAt(int i) {
      final x = values.length == 1
          ? size.width / 2
          : i * size.width / (values.length - 1);
      final y = topPad + plotHeight - (values[i] / scale * plotHeight * animValue);
      return Offset(x, y);
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p = pointAt(i);
      path.lineTo(p.dx, p.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.18),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final dotPaint = Paint()..color = lineColor;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      canvas.drawCircle(pointAt(i), values.length > 10 ? 1.8 : 2.6, dotPaint);
    }

    if (selectedIndex >= 0 && selectedIndex < values.length) {
      final p = pointAt(selectedIndex);
      canvas.drawLine(
        Offset(p.dx, topPad),
        Offset(p.dx, size.height),
        Paint()
          ..color = labelColor.withValues(alpha: 0.2)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 5, Paint()..color = lineColor.withValues(alpha: 0.25));
      canvas.drawCircle(p, 3.2, Paint()..color = lineColor);
    } else if (maxVal > 0) {
      final peak = values.indexOf(maxVal);
      final p = pointAt(peak);
      final tp = TextPainter(
        text: TextSpan(
          text: formatValue(maxVal),
          style: TextStyle(
            color: labelColor.withValues(alpha: 0.45),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (p.dx - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, (p.dy - tp.height - 4).clamp(0.0, size.height)));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values ||
      old.animValue != animValue ||
      old.lineColor != lineColor ||
      old.labelColor != labelColor ||
      old.selectedIndex != selectedIndex;
}

/// GitHub-style contribution heatmap of the last 53 weeks of listening.
/// Horizontally scrollable with a fixed cell size so it stays readable;
/// starts scrolled to the most recent weeks.
class StatsHeatmap extends StatelessWidget {
  final Map<String, double> dailySeconds;
  final Color fillColor;
  final Color emptyColor;
  final Color labelColor;
  final String lessLabel;
  final String moreLabel;
  final List<String> dayLabels;
  final String? selectedKey;
  final void Function(String dateKey, double seconds)? onDaySelected;

  const StatsHeatmap({
    super.key,
    required this.dailySeconds,
    required this.fillColor,
    required this.emptyColor,
    required this.labelColor,
    required this.lessLabel,
    required this.moreLabel,
    this.dayLabels = const [],
    this.selectedKey,
    this.onDaySelected,
  });

  static const _weeks = 53;
  static const _gap = 2.0;
  static const _cell = 11.0;
  static const _labelHeight = 14.0;

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final monday = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - 1));
    final start = monday.subtract(const Duration(days: 7 * (_weeks - 1)));

    var maxVal = 0.0;
    var selW = -1;
    var selD = -1;
    final levels = List<List<double>>.generate(_weeks, (_) => List.filled(7, -1));
    for (var w = 0; w < _weeks; w++) {
      for (var d = 0; d < 7; d++) {
        final date = start.add(Duration(days: w * 7 + d));
        if (date.isAfter(today)) continue;
        final key = _dateKey(date);
        final v = dailySeconds[key] ?? 0;
        levels[w][d] = v;
        if (v > maxVal) maxVal = v;
        if (key == selectedKey) {
          selW = w;
          selD = d;
        }
      }
    }

    final monthLabels = <int, String>{};
    var lastMonth = -1;
    for (var w = 0; w < _weeks; w++) {
      final date = start.add(Duration(days: w * 7));
      if (date.month != lastMonth) {
        lastMonth = date.month;
        monthLabels[w] = _monthShort(date.month);
      }
    }

    final gridWidth = _weeks * _cell + (_weeks - 1) * _gap;
    final gridHeight = 7 * _cell + 6 * _gap;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (dayLabels.length == 7)
          Padding(
            padding: const EdgeInsets.only(top: _labelHeight, right: 4),
            child: Column(children: [
              for (var d = 0; d < 7; d++)
                SizedBox(
                  height: _cell + (d < 6 ? _gap : 0),
                  child: d.isEven
                      // Tiny chart labels in fixed rows: cap the zoom.
                      ? MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: Text(dayLabels[d],
                          style: TextStyle(
                              fontSize: 7,
                              height: 1.2,
                              color: labelColor.withValues(alpha: 0.35))))
                      : null,
                ),
            ]),
          ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: onDaySelected == null
                  ? null
                  : (details) {
                      final x = details.localPosition.dx;
                      final y = details.localPosition.dy - _labelHeight;
                      if (y < 0) return;
                      final w = x ~/ (_cell + _gap);
                      final d = y ~/ (_cell + _gap);
                      if (w < 0 || w >= _weeks || d < 0 || d > 6) return;
                      final v = levels[w][d];
                      if (v < 0) return;
                      final date = start.add(Duration(days: w * 7 + d));
                      onDaySelected!(_dateKey(date), v);
                    },
              child: SizedBox(
                width: gridWidth,
                height: gridHeight + _labelHeight,
                child: CustomPaint(
                  painter: _HeatmapPainter(
                    levels: levels,
                    maxVal: maxVal,
                    cell: _cell,
                    fillColor: fillColor,
                    emptyColor: emptyColor,
                    labelColor: labelColor,
                    monthLabels: monthLabels,
                    selectedWeek: selW,
                    selectedDay: selD,
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text(lessLabel,
            style: TextStyle(fontSize: 9, color: labelColor.withValues(alpha: 0.4))),
        const SizedBox(width: 4),
        for (final alpha in [0.0, 0.3, 0.55, 0.8, 1.0])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: alpha == 0.0
                    ? emptyColor
                    : fillColor.withValues(alpha: alpha),
              ),
            ),
          ),
        const SizedBox(width: 4),
        Text(moreLabel,
            style: TextStyle(fontSize: 9, color: labelColor.withValues(alpha: 0.4))),
      ]),
    ]);
  }

  static String _monthShort(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[month - 1];
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<List<double>> levels;
  final double maxVal;
  final double cell;
  final Color fillColor;
  final Color emptyColor;
  final Color labelColor;
  final Map<int, String> monthLabels;
  final int selectedWeek;
  final int selectedDay;

  _HeatmapPainter({
    required this.levels,
    required this.maxVal,
    required this.cell,
    required this.fillColor,
    required this.emptyColor,
    required this.labelColor,
    required this.monthLabels,
    required this.selectedWeek,
    required this.selectedDay,
  });

  static const _gap = StatsHeatmap._gap;
  static const _labelHeight = StatsHeatmap._labelHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (final entry in monthLabels.entries) {
      final tp = TextPainter(
        text: TextSpan(
          text: entry.value,
          style: TextStyle(fontSize: 8, color: labelColor.withValues(alpha: 0.35)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(entry.key * (cell + _gap), 0));
    }

    for (var w = 0; w < levels.length; w++) {
      for (var d = 0; d < 7; d++) {
        final v = levels[w][d];
        if (v < 0) continue;
        if (v <= 0) {
          paint.color = emptyColor;
        } else {
          final ratio = maxVal > 0 ? v / maxVal : 0.0;
          final alpha = ratio <= 0.25
              ? 0.3
              : ratio <= 0.5
                  ? 0.55
                  : ratio <= 0.75
                      ? 0.8
                      : 1.0;
          paint.color = fillColor.withValues(alpha: alpha);
        }
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            w * (cell + _gap),
            _labelHeight + d * (cell + _gap),
            cell,
            cell,
          ),
          Radius.circular(cell / 4),
        );
        canvas.drawRRect(rect, paint);
        if (w == selectedWeek && d == selectedDay) {
          canvas.drawRRect(
            rect,
            Paint()
              ..color = labelColor.withValues(alpha: 0.9)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.levels != levels ||
      old.maxVal != maxVal ||
      old.cell != cell ||
      old.fillColor != fillColor ||
      old.selectedWeek != selectedWeek ||
      old.selectedDay != selectedDay;
}
