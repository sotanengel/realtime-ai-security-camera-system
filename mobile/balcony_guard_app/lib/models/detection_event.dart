import 'dart:convert';

/// Frigate Events API のレスポンスに対応するデータモデル（D-004）
class DetectionEvent {
  final String id;
  final String camera;
  final String label;
  final double score;
  final double startTime;
  final double? endTime;
  final List<int>? box;
  final int? area;
  final List<String> currentZones;
  final bool hasClip;
  final bool hasSnapshot;

  const DetectionEvent({
    required this.id,
    required this.camera,
    required this.label,
    required this.score,
    required this.startTime,
    this.endTime,
    this.box,
    this.area,
    required this.currentZones,
    required this.hasClip,
    required this.hasSnapshot,
  });

  factory DetectionEvent.fromJson(Map<String, dynamic> json) {
    final rawBox = json['box'] as List<dynamic>?;
    return DetectionEvent(
      id: json['id'] as String? ?? '',
      camera: json['camera'] as String? ?? '',
      label: json['label'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      startTime: (json['start_time'] as num?)?.toDouble() ?? 0.0,
      endTime: (json['end_time'] as num?)?.toDouble(),
      box: rawBox?.map((e) => (e as num).toInt()).toList(),
      area: json['area'] as int?,
      currentZones: (json['current_zones'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      hasClip: json['has_clip'] as bool? ?? false,
      hasSnapshot: json['has_snapshot'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'camera': camera,
        'label': label,
        'score': score,
        'start_time': startTime,
        'end_time': endTime,
        'box': box,
        'area': area,
        'current_zones': currentZones,
        'has_clip': hasClip,
        'has_snapshot': hasSnapshot,
      };

  /// イベント発生日時を DateTime に変換する
  DateTime get startDateTime =>
      DateTime.fromMillisecondsSinceEpoch((startTime * 1000).toInt());

  /// ラベルに対応する絵文字を返す（UI表示用）
  String get labelEmoji {
    switch (label) {
      case 'person':
        return '🧍';
      case 'bird':
        return '🐦';
      case 'cat':
        return '🐱';
      case 'dog':
        return '🐕';
      default:
        return '📦';
    }
  }
}
