import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/mediapipe_detection_service.dart';
import '../services/notification_service.dart';
import '../widgets/detection_overlay.dart';

/// ローカル推論画面（F-PHN-001）
/// スマホカメラ映像に対してMediaPipe/TFLite on-device推論を実行する
class LocalDetectionScreen extends StatefulWidget {
  const LocalDetectionScreen({super.key});

  @override
  State<LocalDetectionScreen> createState() => _LocalDetectionScreenState();
}

class _LocalDetectionScreenState extends State<LocalDetectionScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _modelReady = false;
  String? _initError;

  List<Detection> _detections = [];
  double _inferenceMs = 0;
  bool _notifyEnabled = true;
  double _confidenceThreshold = 0.5;
  DateTime? _lastNotifiedAt;

  final _detector = MediapipeDetectionService();
  static const _processingInterval = Duration(milliseconds: 300); // ~3fps
  Timer? _processingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _initModel();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw Exception('カメラが見つかりません');

      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium, // 処理負荷を抑えるため medium を使用
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (mounted) setState(() => _isInitialized = true);

      _startProcessing();
    } catch (e) {
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  Future<void> _initModel() async {
    try {
      await _detector.initialize();
      if (mounted) setState(() => _modelReady = true);
    } catch (e) {
      if (mounted) {
        setState(() => _initError = 'モデル初期化失敗: $e\nassets/models/efficientdet_lite0.tflite を配置してください');
      }
    }
  }

  void _startProcessing() {
    _processingTimer = Timer.periodic(_processingInterval, (_) async {
      if (!_modelReady || _isProcessing || _cameraController == null) return;

      _isProcessing = true;
      final stopwatch = Stopwatch()..start();
      try {
        final image = await _cameraController!.takePicture();
        final bytes = await image.readAsBytes();
        final detections = await _detector.detectFromBytes(
          bytes,
          confidenceThreshold: _confidenceThreshold,
        );

        stopwatch.stop();
        if (mounted) {
          setState(() {
            _detections = detections;
            _inferenceMs = stopwatch.elapsedMilliseconds.toDouble();
          });
        }

        // 通知（過剰通知を防ぐため10秒間隔）
        if (_notifyEnabled && detections.isNotEmpty) {
          final now = DateTime.now();
          if (_lastNotifiedAt == null ||
              now.difference(_lastNotifiedAt!).inSeconds >= 10) {
            final best = detections.reduce(
                (a, b) => a.score > b.score ? a : b);
            await NotificationService.instance.notifyLocalDetection(
                best.label, best.score);
            _lastNotifiedAt = now;
          }
        }
      } catch (_) {
        // フレーム取得失敗は無視
      } finally {
        _isProcessing = false;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _processingTimer?.cancel();
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('ローカル推論'),
        actions: [
          // 通知ON/OFF
          IconButton(
            icon: Icon(
              _notifyEnabled ? Icons.notifications_active : Icons.notifications_off,
              color: _notifyEnabled ? Colors.yellow : Colors.grey,
            ),
            onPressed: () =>
                setState(() => _notifyEnabled = !_notifyEnabled),
            tooltip: '通知切り替え',
          ),
          // しきい値スライダーボタン
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showThresholdDialog,
            tooltip: '信頼度しきい値',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_initError!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _initCamera, child: const Text('再試行')),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _cameraController == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('カメラを初期化中...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // カメラプレビュー
        CameraPreview(_cameraController!),

        // 検知結果オーバーレイ（BBox + ラベル）
        if (_detections.isNotEmpty)
          DetectionOverlay(detections: _detections),

        // 推論情報オーバーレイ
        Positioned(
          top: 8,
          left: 8,
          child: _InferenceInfoOverlay(
            modelReady: _modelReady,
            inferenceMs: _inferenceMs,
            detectionCount: _detections.length,
            threshold: _confidenceThreshold,
          ),
        ),
      ],
    );
  }

  void _showThresholdDialog() {
    double tempThreshold = _confidenceThreshold;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('信頼度しきい値'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${(tempThreshold * 100).toStringAsFixed(0)}%'),
              Slider(
                value: tempThreshold,
                min: 0.1,
                max: 0.95,
                divisions: 17,
                onChanged: (v) => setDialogState(() => tempThreshold = v),
              ),
              const Text(
                '値を低くすると検知感度が上がりますが\n誤検知が増える可能性があります',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                setState(() => _confidenceThreshold = tempThreshold);
                Navigator.pop(context);
              },
              child: const Text('適用'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _processingTimer?.cancel();
    _cameraController?.dispose();
    _detector.dispose();
    super.dispose();
  }
}

class _InferenceInfoOverlay extends StatelessWidget {
  final bool modelReady;
  final double inferenceMs;
  final int detectionCount;
  final double threshold;

  const _InferenceInfoOverlay({
    required this.modelReady,
    required this.inferenceMs,
    required this.detectionCount,
    required this.threshold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                modelReady ? Icons.memory : Icons.hourglass_empty,
                color: modelReady ? Colors.green : Colors.yellow,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                modelReady ? 'EfficientDet-Lite0' : 'モデル読み込み中',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          if (inferenceMs > 0)
            Text(
              '${inferenceMs.toStringAsFixed(0)}ms | '
              '$detectionCount 件 | '
              'conf>${(threshold * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
