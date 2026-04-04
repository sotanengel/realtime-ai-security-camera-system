import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/detection_event.dart';

const _hostKey = 'frigate_host';
const _defaultHost = 'http://192.168.1.100:5000';

/// Frigate REST API のラッパーサービス
class FrigateApiService {
  FrigateApiService._();

  static FrigateApiService? _instance;
  static FrigateApiService get instance =>
      _instance ??= FrigateApiService._();

  final _client = http.Client();

  /// 保存済みのFrigateホストURLを取得する
  static Future<String> getSavedHost() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_hostKey) ?? _defaultHost;
  }

  /// FrigateホストURLを保存する
  static Future<void> saveHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host.trim().replaceAll(RegExp(r'/$'), ''));
  }

  /// 最新のイベント一覧を取得する（F-020, F-021）
  Future<List<DetectionEvent>> getEvents({
    String? camera,
    String? label,
    int limit = 50,
    bool hasSnapshot = true,
  }) async {
    final host = await getSavedHost();
    final params = <String, String>{
      'limit': limit.toString(),
      'has_snapshot': hasSnapshot ? '1' : '0',
    };
    if (camera != null) params['camera'] = camera;
    if (label != null) params['label'] = label;

    final uri = Uri.parse('$host/api/events').replace(queryParameters: params);
    final response = await _client.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Frigate API エラー: ${response.statusCode}');
    }

    final List<dynamic> json = jsonDecode(response.body);
    return json.map((e) => DetectionEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// スナップショット画像のURLを返す
  String snapshotUrl(String host, String eventId) =>
      '$host/api/events/$eventId/snapshot.jpg';

  /// スナップショット画像バイトを取得する
  Future<Uint8List?> getSnapshot(String eventId) async {
    final host = await getSavedHost();
    final url = '$host/api/events/$eventId/snapshot.jpg';
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  /// go2rtcのHLS URLを返す（ライブ映像表示用）
  String hlsStreamUrl(String go2rtcHost, String streamName) =>
      '$go2rtcHost/api/stream.m3u8?src=$streamName';

  /// Frigateの動作状態を確認する（NF-012: 接続断検知）
  Future<bool> healthCheck() async {
    final host = await getSavedHost();
    try {
      final response = await _client
          .get(Uri.parse('$host/api/version'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
