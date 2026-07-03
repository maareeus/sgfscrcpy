import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/device.dart';
import '../models/mirror_options.dart';
import '../services/live_stream_server.dart';
import '../services/scrcpy_server_client.dart';
import '../services/scrcpy_service.dart';

/// In-app viewer (Phase 2): decodes and renders the mirror inside our window.
///
/// The scrcpy stream is demuxed by [ScrcpyServerClient], re-served locally by
/// [LiveStreamServer], and decoded/rendered by mpv (media_kit).
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
  final Player _player = Player(
    configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn),
  );
  late final VideoController _controller = VideoController(_player);
  final LiveStreamServer _stream = LiveStreamServer();
  ScrcpyServerClient? _client;
  StreamSubscription? _logSub;

  VideoStreamInfo? _info;
  String? _error;
  bool _showLog = false;
  final List<String> _logs = [];
  int _packets = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _client?.stop();
    _stream.stop();
    _player.dispose();
    super.dispose();
  }

  void _log(String m) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, m);
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  Future<void> _start() async {
    try {
      await _stream.start();

      _logSub = _player.stream.log.listen((l) => _log('[mpv] ${l.text}'));

      // Configure mpv for low-latency live playback of a raw H.264 elementary
      // stream (no container, so force the demuxer and minimize probing).
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('profile', 'low-latency');
        await platform.setProperty('cache', 'no');
        await platform.setProperty('untimed', 'yes');
        await platform.setProperty('demuxer', 'lavf');
        await platform.setProperty('demuxer-lavf-format', 'h264');
        await platform.setProperty('demuxer-lavf-o', 'probesize=32');
        await platform.setProperty('video-latency-hacks', 'yes');
      }

      final client = ScrcpyServerClient(
        service: widget.service,
        serial: widget.device.serial,
        version: widget.version,
        options: widget.options,
        onInfo: (info) {
          setState(() => _info = info);
          // Start playback once we know a stream is coming.
          _player.open(Media(_stream.url), play: true);
        },
        onPacket: (p) {
          _packets++;
          _stream.addPacket(p);
        },
        onLog: _log,
        onError: (e) => setState(() => _error = e.toString()),
        onClosed: () => _log('Connection closed.'),
      );
      _client = client;
      await client.start();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${widget.device.displayName} (beta)'),
        actions: [
          IconButton(
            tooltip: 'Diagnostics',
            icon: Icon(_showLog ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () => setState(() => _showLog = !_showLog),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _error != null
                ? _errorView(theme)
                : Video(controller: _controller, fit: BoxFit.contain),
          ),
          if (_showLog)
            Positioned(
              right: 12,
              top: 12,
              width: 360,
              bottom: 12,
              child: _diagnostics(theme),
            ),
        ],
      ),
    );
  }

  Widget _errorView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _diagnostics(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _info == null
                ? 'Connecting…'
                : '${_info!.codec} ${_info!.width}×${_info!.height} · $_packets pkts',
            style: theme.textTheme.labelMedium,
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (_, i) => Text(
                _logs[i],
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
