import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/detection_event.dart';
import '../services/frigate_api_service.dart';
import '../widgets/event_card.dart';

/// 検知イベント一覧画面（F-PHN-002）
/// Frigate Events APIを定期ポーリングしてイベント履歴を表示する
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<DetectionEvent> _events = [];
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  String? _selectedLabel;
  Timer? _pollingTimer;
  DateTime? _lastUpdated;

  static const _pollingInterval = Duration(seconds: 30);
  static const _labels = ['person', 'bird', 'cat', 'dog'];

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _pollingTimer = Timer.periodic(_pollingInterval, (_) => _loadEvents());
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final events = await FrigateApiService.instance.getEvents(
        label: _selectedLabel,
        limit: 100,
      );
      if (mounted) {
        setState(() {
          _events = events;
          _lastUpdated = DateTime.now();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('イベント一覧'),
        actions: [
          if (_lastUpdated != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '更新: ${DateFormat('HH:mm:ss').format(_lastUpdated!)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEvents,
            tooltip: '更新',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _LabelFilterBar(
            labels: _labels,
            selected: _selectedLabel,
            onSelected: (label) {
              setState(() => _selectedLabel = label);
              _loadEvents();
            },
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text('イベントを取得できませんでした'),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_errorMessage!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            FilledButton(onPressed: _loadEvents, child: const Text('再試行')),
          ],
        ),
      );
    }

    if (_events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _selectedLabel != null
                  ? '$_selectedLabel のイベントはありません'
                  : 'イベントはまだありません',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView.builder(
        itemCount: _events.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, index) {
          return EventCard(event: _events[index]);
        },
      ),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}

class _LabelFilterBar extends StatelessWidget {
  final List<String> labels;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _LabelFilterBar({
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _FilterChip(
            label: 'すべて',
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          ...labels.map((l) => _FilterChip(
                label: l,
                isSelected: selected == l,
                onTap: () => onSelected(l),
              )),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
