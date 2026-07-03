import 'dart:async';

import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/mirror_options.dart';
import '../services/scrcpy_server_client.dart';
import '../services/scrcpy_service.dart';

/// In-app viewer (Phase 1 — diagnostic).
///
/// Connects to scrcpy-server and shows live stream info and throughput. Video
/// decoding/rendering is the next phase; for now this proves the pipeline works
/// so the mirror can eventually live inside our own window (custom icon/UI).
class ViewerScreen extends StatefulWidget {
  final ScrcpyService service;
  final Device device;
  final String version;
  final MirrorOptions options;

  const ViewerScreen({
    super.key,
    required this.service,
    required this.device,
    required this.version,
    required this.options,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  ScrcpyServerClient? _client;
  VideoStreamInfo? _info;
  String? _error;
  final List<String> _logs = [];

  int _packets = 0;
  int _keyFrames = 0;
  int _bytes = 0;
  double _fps = 0;
  double _mbps = 0;

  int _windowPackets = 0;
  int _windowBytes = 0;
  Timer? _rateTimer;

  @override
  void initState() {
    super.initState();
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _fps = _windowPackets.toDouble();
        _mbps = _windowBytes * 8 / 1e6;
        _windowPackets = 0;
        _windowBytes = 0;
      });
    });
    _connect();
  }

  @override
  void dispose() {
    _rateTimer?.cancel();
    _client?.stop();
    super.dispose();
  }

  void _log(String m) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, m);
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  Future<void> _connect() async {
    final client = ScrcpyServerClient(
      service: widget.service,
      serial: widget.device.serial,
      version: widget.version,
      options: widget.options,
      onInfo: (info) => setState(() => _info = info),
      onPacket: (p) {
        _packets++;
        _bytes += p.data.length;
        _windowPackets++;
        _windowBytes += p.data.length;
        if (p.isKeyFrame) _keyFrames++;
      },
      onLog: _log,
      onError: (e) => setState(() => _error = e.toString()),
      onClosed: () => _log('Connection closed.'),
    );
    _client = client;
    try {
      await client.start();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Viewer (beta) — ${widget.device.displayName}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!),
              ),
            const SizedBox(height: 12),
            _StatGrid(
              info: _info,
              packets: _packets,
              keyFrames: _keyFrames,
              bytes: _bytes,
              fps: _fps,
              mbps: _mbps,
            ),
            const SizedBox(height: 20),
            Text('Log', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (_, i) => Text(
                    _logs[i],
                    style: const TextStyle(
                        fontFamily: 'Consolas', fontSize: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Phase 1: stream is being demuxed but not yet decoded. '
              'Video rendering comes next.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  final VideoStreamInfo? info;
  final int packets;
  final int keyFrames;
  final int bytes;
  final double fps;
  final double mbps;

  const _StatGrid({
    required this.info,
    required this.packets,
    required this.keyFrames,
    required this.bytes,
    required this.fps,
    required this.mbps,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _stat(context, 'Status', info == null ? 'Connecting…' : 'Streaming'),
        _stat(context, 'Codec', info?.codec ?? '—'),
        _stat(context, 'Resolution',
            info == null ? '—' : '${info!.width}×${info!.height}'),
        _stat(context, 'Packets', '$packets'),
        _stat(context, 'Key frames', '$keyFrames'),
        _stat(context, 'FPS', fps.toStringAsFixed(0)),
        _stat(context, 'Bitrate', '${mbps.toStringAsFixed(1)} Mbps'),
        _stat(context, 'Total', '${(bytes / 1048576).toStringAsFixed(1)} MB'),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.5),
              )),
          const SizedBox(height: 6),
          Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
