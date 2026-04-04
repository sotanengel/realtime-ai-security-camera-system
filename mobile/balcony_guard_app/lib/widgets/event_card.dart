import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/detection_event.dart';
import '../services/frigate_api_service.dart';

/// 検知イベントカードウィジェット（イベント一覧画面で使用）
class EventCard extends StatefulWidget {
  final DetectionEvent event;

  const EventCard({super.key, required this.event});

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  String? _host;

  @override
  void initState() {
    super.initState();
    FrigateApiService.getSavedHost().then((h) {
      if (mounted) setState(() => _host = h);
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final timeStr =
        DateFormat('MM/dd HH:mm:ss').format(event.startDateTime);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // サムネイル
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _host != null && event.hasSnapshot
                    ? Image.network(
                        FrigateApiService.instance.snapshotUrl(_host!, event.id),
                        width: 80,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _PlaceholderThumb(event: event),
                      )
                    : _PlaceholderThumb(event: event),
              ),
              const SizedBox(width: 12),
              // イベント情報
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${event.labelEmoji} ${event.label}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        _ScoreBadge(score: event.score),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeStr,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                    if (event.currentZones.isNotEmpty)
                      Text(
                        '📍 ${event.currentZones.join(", ")}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                    Text(
                      '📷 ${event.camera}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (event.hasClip)
                const Icon(Icons.videocam, color: Colors.blue, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EventDetailSheet(event: widget.event, host: _host),
    );
  }
}

class _PlaceholderThumb extends StatelessWidget {
  final DetectionEvent event;
  const _PlaceholderThumb({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(event.labelEmoji, style: const TextStyle(fontSize: 28)),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final double score;
  const _ScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).toStringAsFixed(0);
    final color = score >= 0.8
        ? Colors.green
        : score >= 0.6
            ? Colors.orange
            : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        '$pct%',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _EventDetailSheet extends StatelessWidget {
  final DetectionEvent event;
  final String? host;

  const _EventDetailSheet({required this.event, required this.host});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Text(
              '${event.labelEmoji} ${event.label}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 16),
          if (host != null && event.hasSnapshot)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                FrigateApiService.instance.snapshotUrl(host!, event.id),
                fit: BoxFit.contain,
              ),
            ),
          const SizedBox(height: 16),
          _DetailRow('カメラ', event.camera),
          _DetailRow(
            '日時',
            DateFormat('yyyy/MM/dd HH:mm:ss').format(event.startDateTime),
          ),
          _DetailRow('信頼度', '${(event.score * 100).toStringAsFixed(1)}%'),
          if (event.currentZones.isNotEmpty)
            _DetailRow('ゾーン', event.currentZones.join(', ')),
          if (event.area != null)
            _DetailRow('エリア', '${event.area} px²'),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
