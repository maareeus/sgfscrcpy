import 'dart:io';
import 'dart:typed_data';

import 'scrcpy_server_client.dart';

/// Serves the demuxed H.264 Annex-B stream over a local HTTP endpoint so a
/// player (mpv via media_kit) can decode and render it.
///
/// A newly connected client is fed the latest codec config (SPS/PPS) and then
/// packets starting from the next key frame, so decoding can begin cleanly.
class LiveStreamServer {
  HttpServer? _server;
  HttpResponse? _sink;
  bool _waitingForKeyFrame = true;
  Uint8List? _config;

  int get port => _server?.port ?? 0;

  /// The URL a player should open. `.h264` helps the demuxer probe the format.
  String get url => 'http://127.0.0.1:$port/live.h264';

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handleRequest);
  }

  void _handleRequest(HttpRequest request) {
    final response = request.response;
    response.headers.set(HttpHeaders.contentTypeHeader, 'video/h264');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.bufferOutput = false;

    _sink = response;
    _waitingForKeyFrame = true;

    // Send known config immediately; the key frame will follow.
    final config = _config;
    if (config != null) {
      _safeAdd(response, config);
    }

    response.done.then((_) => _clearSink(response)).catchError((_) {
      _clearSink(response);
    });
  }

  void _clearSink(HttpResponse response) {
    if (identical(_sink, response)) _sink = null;
  }

  /// Feeds a demuxed packet to the connected player (if any).
  void addPacket(VideoPacket packet) {
    if (packet.isConfig) {
      _config = packet.data;
    }

    final sink = _sink;
    if (sink == null) return;

    if (_waitingForKeyFrame) {
      if (packet.isConfig) {
        _safeAdd(sink, packet.data);
        return;
      }
      if (!packet.isKeyFrame) return; // skip until a key frame
      _waitingForKeyFrame = false;
    }
    _safeAdd(sink, packet.data);
  }

  void _safeAdd(HttpResponse response, List<int> bytes) {
    try {
      response.add(bytes);
    } catch (_) {
      _clearSink(response);
    }
  }

  Future<void> stop() async {
    _sink = null;
    await _server?.close(force: true);
    _server = null;
  }
}
