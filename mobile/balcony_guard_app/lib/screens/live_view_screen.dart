import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import '../services/frigate_api_service.dart';

/// ライブ映像確認画面（F-001, F-002, F-003）
/// go2rtc の HLS ストリームを VLC プレーヤーで表示する
class LiveViewScreen extends StatefulWidget {
  const LiveViewScreen({super.key});

  @override
  State<LiveViewScreen> createState() => _LiveViewScreenState();
}

class _LiveViewScreenState extends State<LiveViewScreen> {
  VlcPlayerController? _vlcController;
  bool _isLoading = true;
  bool _hasError = false;
  String _streamUrl = '';

  // go2rtc のデフォルトポート（1984）を使用
  // HLS URL: http://<host>:1984/api/stream.m3u8?src=<streamName>
  final _streamNames = ['balcony_sub', 'balcony_main'];
  int _currentStreamIndex = 0;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final host = await FrigateApiService.getSavedHost();
      // go2rtcのポートをホストから推定（Frigateホスト:5000 → go2rtc:1984）
      final go2rtcHost = host.replaceAll(':5000', ':1984');
      _streamUrl = '$go2rtcHost/api/stream.m3u8?src=${_streamNames[_currentStreamIndex]}';

      _vlcController?.dispose();
      _vlcController = VlcPlayerController.network(
        _streamUrl,
        hwAcc: HwAcc.full,
        autoPlay: true,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions([
            VlcAdvancedOptions.networkCaching(3000),
            VlcAdvancedOptions.liveCaching(3000),
          ]),
        ),
      );

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _switchStream() {
    _currentStreamIndex = (_currentStreamIndex + 1) % _streamNames.length;
    _initPlayer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'ライブ映像: ${_streamNames[_currentStreamIndex]}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.switch_video),
            onPressed: _switchStream,
            tooltip: 'ストリーム切り替え',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initPlayer,
            tooltip: '再接続',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('ストリームに接続中...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    if (_hasError || _vlcController == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.grey, size: 64),
            const SizedBox(height: 16),
            const Text('ストリームに接続できません',
                style: TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            Text(_streamUrl,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _initPlayer,
              icon: const Icon(Icons.refresh),
              label: const Text('再接続'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: VlcPlayer(
          controller: _vlcController!,
          aspectRatio: 16 / 9,
          placeholder:
              const Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _vlcController?.dispose();
    super.dispose();
  }
}
