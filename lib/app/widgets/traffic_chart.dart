import 'dart:math' as math;

import 'package:flutter/material.dart';

class TrafficChart extends StatelessWidget {
  const TrafficChart({
    super.key,
    required this.values,
    required this.color,
    this.height = 54,
  });
  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _TrafficPainter(List.of(values), color)),
    ),
  );
}

class _TrafficPainter extends CustomPainter {
  _TrafficPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0) return;
    final maxValue = values.fold(1.0, math.max);
    final points = values.length == 1 ? [0.0, values.first] : values;
    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i * size.width / (points.length - 1);
      final y = size.height - 4 - (points[i] / maxValue) * (size.height - 12);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        final previousX = (i - 1) * size.width / (points.length - 1);
        final previousY =
            size.height - 4 - (points[i - 1] / maxValue) * (size.height - 12);
        final middleX = (previousX + x) / 2;
        line.cubicTo(middleX, previousY, middleX, y, x, y);
      }
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: .10));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_TrafficPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
