import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/frigate_api_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isConnected = false;
  bool _isChecking = false;
  final _hostController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHost();
  }

  Future<void> _loadHost() async {
    final host = await FrigateApiService.getSavedHost();
    _hostController.text = host;
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() => _isChecking = true);
    final ok = await FrigateApiService.instance.healthCheck();
    if (mounted) {
      setState(() {
        _isConnected = ok;
        _isChecking = false;
      });
    }
  }

  Future<void> _saveHost() async {
    await FrigateApiService.saveHost(_hostController.text);
    _checkConnection();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Balcony Guard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
            tooltip: '設定',
          ),
        ],
      ),
      body: Column(
        children: [
          // 接続状態バナー（NF-012: 接続断検知）
          _ConnectionStatusBanner(
            isConnected: _isConnected,
            isChecking: _isChecking,
            onRetry: _checkConnection,
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(16),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _NavCard(
                  icon: Icons.videocam,
                  title: 'ライブ映像',
                  subtitle: 'go2rtc HLSストリーム',
                  color: Colors.blue,
                  onTap: () => context.go('/live'),
                ),
                _NavCard(
                  icon: Icons.event_note,
                  title: 'イベント一覧',
                  subtitle: '検知履歴・スナップショット',
                  color: Colors.orange,
                  onTap: () => context.go('/events'),
                ),
                _NavCard(
                  icon: Icons.camera_enhance,
                  title: 'ローカル検知',
                  subtitle: 'on-device MediaPipe推論',
                  color: Colors.green,
                  onTap: () => context.go('/detect'),
                ),
                _NavCard(
                  icon: Icons.security,
                  title: 'Frigate UI',
                  subtitle: 'ブラウザで開く',
                  color: Colors.purple,
                  onTap: () async {
                    // TODO: url_launcherでFrigate UIをブラウザで開く
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Frigate 接続設定'),
        content: TextField(
          controller: _hostController,
          decoration: const InputDecoration(
            labelText: 'Frigate ホストURL',
            hintText: 'http://192.168.1.100:5000',
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              _saveHost();
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }
}

class _ConnectionStatusBanner extends StatelessWidget {
  final bool isConnected;
  final bool isChecking;
  final VoidCallback onRetry;

  const _ConnectionStatusBanner({
    required this.isConnected,
    required this.isChecking,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isChecking) {
      return const LinearProgressIndicator();
    }
    if (isConnected) {
      return Container(
        color: Colors.green.shade800,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Frigate に接続中', style: TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        color: Colors.red.shade800,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Frigate に接続できません  タップで再試行',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 36),
              const Spacer(),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
