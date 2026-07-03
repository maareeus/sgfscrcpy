import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/mirror_options.dart';
import 'scrcpy_service.dart';
import 'win_process.dart' as win;

/// Metadata received at the start of the video stream.
class VideoStreamInfo {
  final String deviceName;
  final String codec; // fourcc, e.g. "h264", "h265", "av01"
  final int width;
  final int height;

  VideoStreamInfo({
    required this.deviceName,
    required this.codec,
    required this.width,
    required this.height,
  });
}

/// A single encoded video packet from the scrcpy stream.
class VideoPacket {
  final int pts; // microseconds (config packets carry no real pts)
  final bool isConfig; // codec config (SPS/PPS)
  final bool isKeyFrame;
  final Uint8List data;

  VideoPacket({
    required this.pts,
    required this.isConfig,
    required this.isKeyFrame,
    required this.data,
  });
}

/// A minimal scrcpy client that runs `scrcpy-server` on the device and reads
/// the encoded video stream over a reverse adb tunnel.
///
/// Phase 1: this connects, performs the handshake and demuxes packets. It does
/// NOT decode video yet — that is the next phase (native decoders per OS).
/// Tested against scrcpy 3.x; the protocol is version-specific.
class ScrcpyServerClient {
  final ScrcpyService service;
  final String serial;
  final String version; // e.g. "3.3.4"
  final MirrorOptions options;

  // Callbacks.
  final void Function(VideoStreamInfo info)? onInfo;
  final void Function(VideoPacket packet)? onPacket;
  final void Function(String message)? onLog;
  final void Function(Object error)? onError;
  final void Function()? onClosed;

  ScrcpyServerClient({
    required this.service,
    required this.serial,
    required this.version,
    required this.options,
    this.onInfo,
    this.onPacket,
    this.onLog,
    this.onError,
    this.onClosed,
  });

  static const _deviceJarPath = '/data/local/tmp/sgfscrcpy-server.jar';

  late final String _scid =
      (Random().nextInt(0x7FFFFFFF) | 1).toRadixString(16).padLeft(8, '0');
  String get _socketName => 'scrcpy_$_scid';

  String? _adb;
  ServerSocket? _listener;
  Socket? _videoSocket;
  Socket? _controlSocket;
  Process? _serverProcess; // non-Windows
  int _serverPid = 0; // Windows
  bool _stopped = false;

  /// Starts the server and begins streaming. Completes once the handshake is
  /// done (video info received); packets then arrive via [onPacket].
  Future<void> start() async {
    _adb = await service.adbPath();
    if (_adb == null) throw ScrcpyException('"adb" not found on PATH.');
    final jar = await service.serverJarPath();
    if (jar == null) {
      throw ScrcpyException('scrcpy-server jar not found next to scrcpy.');
    }

    onLog?.call('Pushing server ($version)…');
    final push = await Process.run(
      _adb!,
      ['-s', serial, 'push', jar, _deviceJarPath],
      runInShell: false,
    );
    if (push.exitCode != 0) {
      throw ScrcpyException('adb push failed.',
          details: push.stderr.toString().trim());
    }

    // Listen locally, then map the device's abstract socket to us (reverse).
    _listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = _listener!.port;
    onLog?.call('Listening on 127.0.0.1:$port');

    final reverse = await Process.run(
      _adb!,
      ['-s', serial, 'reverse', 'localabstract:$_socketName', 'tcp:$port'],
      runInShell: false,
    );
    if (reverse.exitCode != 0) {
      throw ScrcpyException('adb reverse failed.',
          details: reverse.stderr.toString().trim());
    }

    // Collect the sockets the server connects back with (video, then control).
    final socketsFuture = _acceptSockets();

    _startServer();

    await socketsFuture.timeout(const Duration(seconds: 12), onTimeout: () {
      throw ScrcpyException('Timed out waiting for the device to connect.');
    });

    await _readHandshakeAndStream();
  }

  Future<void> _acceptSockets() async {
    final it = StreamIterator(_listener!);
    // First connection: video. Second: control (audio is disabled).
    if (!await it.moveNext()) throw ScrcpyException('No video connection.');
    _videoSocket = it.current;
    onLog?.call('Video socket connected.');
    // Control is enabled, so a second connection follows the video one.
    if (!await it.moveNext()) throw ScrcpyException('No control connection.');
    _controlSocket = it.current;
    onLog?.call('Control socket connected.');
    await it.cancel();
  }

  void _startServer() {
    // scrcpy 3.x server options, passed as key=value after the version arg.
    final opts = <String>[
      'log_level=info',
      'audio=false',
      'video=true',
      'control=true',
      'tunnel_forward=false',
      'scid=$_scid',
      'clipboard_autosync=false',
    ];
    if (options.maxSize != null) opts.add('max_size=${options.maxSize}');
    if (options.videoBitrateMbps != null) {
      opts.add('video_bit_rate=${options.videoBitrateMbps! * 1000000}');
    }
    if (options.maxFps != null) opts.add('max_fps=${options.maxFps}');

    final args = <String>[
      '-s', serial, 'shell',
      'CLASSPATH=$_deviceJarPath',
      'app_process', '/', 'com.genymobile.scrcpy.Server',
      version,
      ...opts,
    ];
    onLog?.call('Starting server: ${opts.join(' ')}');

    if (Platform.isWindows) {
      // Avoid a console window; we rely on the socket, not stdout, for data.
      _serverPid = win.launchNoWindow(_adb!, args);
      if (_serverPid == 0) {
        throw ScrcpyException('Failed to start scrcpy-server.');
      }
    } else {
      Process.start(_adb!, args, runInShell: false).then((p) {
        _serverProcess = p;
        p.stderr.transform(utf8.decoder).listen((l) => onLog?.call(l.trim()));
      });
    }
  }

  Future<void> _readHandshakeAndStream() async {
    final reader = _ByteReader(_videoSocket!);

    // Dummy byte sent to detect early connection errors.
    await reader.readExactly(1);

    // 64-byte device name (null-padded).
    final nameBytes = await reader.readExactly(64);
    final nul = nameBytes.indexOf(0);
    final deviceName =
        utf8.decode(nameBytes.sublist(0, nul < 0 ? 64 : nul), allowMalformed: true);

    // Codec metadata: fourcc (4) + width (4) + height (4), big-endian.
    final meta = await reader.readExactly(12);
    final codec = ascii.decode(meta.sublist(0, 4)).replaceAll('\x00', '').trim();
    final md = ByteData.sublistView(meta);
    final width = md.getUint32(4, Endian.big);
    final height = md.getUint32(8, Endian.big);

    onInfo?.call(VideoStreamInfo(
      deviceName: deviceName,
      codec: codec,
      width: width,
      height: height,
    ));
    onLog?.call('Stream: $codec ${width}x$height ($deviceName)');

    // Frame loop: 12-byte header (pts u64 + len u32), then payload.
    while (!_stopped) {
      final header = await reader.readExactly(12);
      final hd = ByteData.sublistView(header);
      final rawPts = hd.getUint64(0, Endian.big);
      final len = hd.getUint32(8, Endian.big);
      final isConfig = (header[0] & 0x80) != 0;
      final isKeyFrame = (header[0] & 0x40) != 0;
      final pts = rawPts & 0x3FFFFFFFFFFFFFFF;
      final data = await reader.readExactly(len);
      onPacket?.call(VideoPacket(
        pts: pts,
        isConfig: isConfig,
        isKeyFrame: isKeyFrame,
        data: data,
      ));
    }
  }

  /// Stops streaming and cleans up the tunnel and server process.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _videoSocket?.close();
    } catch (_) {}
    try {
      await _controlSocket?.close();
    } catch (_) {}
    try {
      await _listener?.close();
    } catch (_) {}

    if (Platform.isWindows) {
      if (_serverPid != 0) win.terminateProcess(_serverPid);
    } else {
      _serverProcess?.kill();
    }

    if (_adb != null) {
      await Process.run(
        _adb!,
        ['-s', serial, 'reverse', '--remove', 'localabstract:$_socketName'],
        runInShell: false,
      ).catchError((_) => ProcessResult(0, 0, '', ''));
    }
    onClosed?.call();
  }
}

/// Reads exact byte counts from a socket stream, buffering as needed.
class _ByteReader {
  final List<int> _buffer = [];
  int _cursor = 0;
  bool _done = false;
  Object? _error;
  Completer<void>? _waiter;
  late final StreamSubscription<Uint8List> _sub;

  _ByteReader(Stream<Uint8List> stream) {
    _sub = stream.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _signal();
      },
      onError: (e) {
        _error = e;
        _signal();
      },
      onDone: () {
        _done = true;
        _signal();
      },
    );
  }

  void _signal() {
    _waiter?.complete();
    _waiter = null;
  }

  Future<Uint8List> readExactly(int n) async {
    while (_buffer.length - _cursor < n) {
      if (_error != null) throw _error!;
      if (_done) throw const SocketException('scrcpy stream closed');
      _waiter = Completer<void>();
      await _waiter!.future;
    }
    final out = Uint8List.fromList(_buffer.sublist(_cursor, _cursor + n));
    _cursor += n;
    if (_cursor > (1 << 20)) {
      _buffer.removeRange(0, _cursor);
      _cursor = 0;
    }
    return out;
  }

  Future<void> close() => _sub.cancel();
}
