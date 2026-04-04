import 'package:flutter/material.dart';

import '../services/mediapipe_detection_service.dart';

/// カメラプレビュー上に検知結果を重ねて表示するウィジェット
class DetectionOverlay extends StatelessWidget {
  final List<Detection> detections;

  const DetectionOverlay({super.key, required this.detections});

  static const _labelColors = {
    'person': Colors.red,
    'bird': Colors.blue,
    'cat': Colors.orange,
    'dog': Colors.green,
  };

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DetectionPainter(detections: detections),
      child: const SizedBox.expand(),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  final List<Detection> detections;

  _DetectionPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    for (final det in detections) {
      final color = _boxColor(det.label);
      final rect = Rect.fromLTRB(
        det.boundingBox.left * size.width,
        det.boundingBox.top * size.height,
        det.boundingBox.right * size.width,
        det.boundingBox.bottom * size.height,
      );

      // バウンディングボックス
      final boxPaint = Paint()
        ..color = color.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRect(rect, boxPaint);

      // ラベル背景
      final labelText = '${det.label} ${(det.score * 100).toStringAsFixed(0)}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = Rect.fromLTWH(
        rect.left,
        rect.top - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );

      canvas.drawRect(
        labelRect,
        Paint()..color = color.withOpacity(0.85),
      );

      textPainter.paint(canvas, Offset(rect.left + 4, rect.top - textPainter.height - 2));
    }
  }

  Color _boxColor(String label) {
    const colors = {
      'person': Colors.red,
      'bird': Colors.blue,
      'cat': Colors.orange,
      'dog': Colors.green,
    };
    return colors[label] ?? Colors.purple;
  }

  @override
  bool shouldRepaint(_DetectionPainter oldDelegate) =>
      oldDelegate.detections != detections;
}
