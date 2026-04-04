import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// 検知結果を表すデータクラス
class Detection {
  final String label;
  final double score;
  final Rect boundingBox; // 正規化座標 (0.0 〜 1.0)

  const Detection({
    required this.label,
    required this.score,
    required this.boundingBox,
  });
}

/// MediaPipe / TFLite on-device 物体検知サービス（F-PHN-001）
///
/// モデルは assets/models/ に配置してください。
/// 推奨モデル: EfficientDet-Lite0（COCO, TFLite量子化版）
///   ダウンロード: https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite0/int8/1/efficientdet_lite0.tflite
///   assets/models/efficientdet_lite0.tflite として配置する
class MediapipeDetectionService {
  static const _modelPath = 'assets/models/efficientdet_lite0.tflite';
  static const _inputSize = 320; // EfficientDet-Lite0 の入力サイズ

  /// ベランダ監視で追跡するクラス（COCOラベル）
  static const _targetLabels = {'person', 'bird', 'cat', 'dog'};

  Interpreter? _interpreter;
  bool _isInitialized = false;

  /// インタープリタを初期化する
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);
      _isInitialized = true;
      debugPrint('[MediapipeDetectionService] モデル初期化完了: $_modelPath');
    } catch (e) {
      debugPrint('[MediapipeDetectionService] モデル初期化失敗: $e');
      debugPrint('  → assets/models/efficientdet_lite0.tflite を配置してください');
      rethrow;
    }
  }

  /// カメラフレームに対して推論を実行する
  Future<List<Detection>> detectFromCameraImage(
    CameraImage cameraImage, {
    double confidenceThreshold = 0.5,
  }) async {
    if (!_isInitialized || _interpreter == null) return [];

    final imageBytes = _convertCameraImageToBytes(cameraImage);
    if (imageBytes == null) return [];

    return _runInference(imageBytes, confidenceThreshold);
  }

  /// 静止画（JPEG バイト）に対して推論を実行する
  Future<List<Detection>> detectFromBytes(
    Uint8List jpegBytes, {
    double confidenceThreshold = 0.5,
  }) async {
    if (!_isInitialized || _interpreter == null) return [];

    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) return [];

    final resized = img.copyResize(decoded, width: _inputSize, height: _inputSize);
    final inputBytes = _imageToInputBytes(resized);
    return _runInference(inputBytes, confidenceThreshold);
  }

  List<Detection> _runInference(Uint8List inputBytes, double threshold) {
    final interpreter = _interpreter!;

    final input = inputBytes.buffer.asUint8List();
    final inputTensor = input.reshape([1, _inputSize, _inputSize, 3]);

    // EfficientDet-Lite0 の出力テンソル
    // [boxes, classes, scores, num_detections]
    final outputBoxes = List.generate(1, (_) => List.generate(25, (_) => List.filled(4, 0.0)));
    final outputClasses = List.generate(1, (_) => List.filled(25, 0.0));
    final outputScores = List.generate(1, (_) => List.filled(25, 0.0));
    final outputNumDetections = [0.0];

    final outputs = {
      0: outputBoxes,
      1: outputClasses,
      2: outputScores,
      3: outputNumDetections,
    };

    interpreter.runForMultipleInputs([inputTensor], outputs);

    final numDet = outputNumDetections[0].toInt();
    final detections = <Detection>[];

    for (int i = 0; i < numDet; i++) {
      final score = outputScores[0][i];
      if (score < threshold) continue;

      final classId = outputClasses[0][i].toInt();
      final label = _cocoIdToLabel(classId);
      if (!_targetLabels.contains(label)) continue;

      final box = outputBoxes[0][i];
      detections.add(Detection(
        label: label,
        score: score,
        boundingBox: Rect.fromLTRB(
          box[1].clamp(0.0, 1.0), // x_min
          box[0].clamp(0.0, 1.0), // y_min
          box[3].clamp(0.0, 1.0), // x_max
          box[2].clamp(0.0, 1.0), // y_max
        ),
      ));
    }

    return detections;
  }

  Uint8List? _convertCameraImageToBytes(CameraImage cameraImage) {
    try {
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _yuv420ToRgb(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _bgra8888ToRgb(cameraImage);
      }
    } catch (e) {
      debugPrint('[MediapipeDetectionService] フレーム変換エラー: $e');
    }
    return null;
  }

  Uint8List _yuv420ToRgb(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final rgb = Uint8List(_inputSize * _inputSize * 3);

    final yPlane = image.planes[0].bytes;
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;

    final scaleX = width / _inputSize;
    final scaleY = height / _inputSize;

    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final srcX = (x * scaleX).toInt().clamp(0, width - 1);
        final srcY = (y * scaleY).toInt().clamp(0, height - 1);

        final yVal = yPlane[srcY * width + srcX] & 0xFF;
        final uvX = srcX ~/ 2;
        final uvY = srcY ~/ 2;
        final uvIndex = uvY * (width ~/ 2) + uvX;
        final uVal = (uPlane[uvIndex] & 0xFF) - 128;
        final vVal = (vPlane[uvIndex] & 0xFF) - 128;

        final r = (yVal + 1.370705 * vVal).clamp(0, 255).toInt();
        final g = (yVal - 0.698001 * vVal - 0.337633 * uVal).clamp(0, 255).toInt();
        final b = (yVal + 1.732446 * uVal).clamp(0, 255).toInt();

        final idx = (y * _inputSize + x) * 3;
        rgb[idx] = r;
        rgb[idx + 1] = g;
        rgb[idx + 2] = b;
      }
    }
    return rgb;
  }

  Uint8List _bgra8888ToRgb(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final bytes = image.planes[0].bytes;
    final rgb = Uint8List(_inputSize * _inputSize * 3);

    final scaleX = width / _inputSize;
    final scaleY = height / _inputSize;

    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final srcX = (x * scaleX).toInt().clamp(0, width - 1);
        final srcY = (y * scaleY).toInt().clamp(0, height - 1);
        final srcIdx = (srcY * width + srcX) * 4;
        final idx = (y * _inputSize + x) * 3;
        rgb[idx] = bytes[srcIdx + 2]; // R
        rgb[idx + 1] = bytes[srcIdx + 1]; // G
        rgb[idx + 2] = bytes[srcIdx]; // B
      }
    }
    return rgb;
  }

  Uint8List _imageToInputBytes(img.Image image) {
    final rgb = Uint8List(_inputSize * _inputSize * 3);
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = image.getPixel(x, y);
        final idx = (y * _inputSize + x) * 3;
        rgb[idx] = pixel.r.toInt();
        rgb[idx + 1] = pixel.g.toInt();
        rgb[idx + 2] = pixel.b.toInt();
      }
    }
    return rgb;
  }

  String _cocoIdToLabel(int cocoId) {
    const cocoLabels = {
      0: 'person',
      14: 'bird',
      15: 'cat',
      16: 'dog',
    };
    return cocoLabels[cocoId] ?? 'unknown';
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
