import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/device.dart';
import '../models/mirror_options.dart';
import 'win_process.dart' as win;

/// A detected OS package manager that can install scrcpy.
class PackageManager {
  final String name;
  final String command;

  /// True when the command needs no elevation and we can run it in-app.
  final bool canAutoRun;

  const PackageManager(this.name, this.command, this.canAutoRun);
}

/// Thrown when a required external tool (scrcpy / adb) is missing or fails.
class ScrcpyException implements Exception {
  final String message;

  /// Optional stderr/stdout captured from the failing process.
  final String? details;

  ScrcpyException(this.message, {this.details});

  @override
  String toString() => message;
}

/// Result of probing the local environment for scrcpy and adb.
class EnvironmentStatus {
  final bool scrcpyInstalled;
  final String? scrcpyVersion;
  final bool adbInstalled;
  final String? adbVersion;

  const EnvironmentStatus({
    required this.scrcpyInstalled,
    this.scrcpyVersion,
    required this.adbInstalled,
    this.adbVersion,
  });

  bool get isReady => scrcpyInstalled && adbInstalled;
}

/// Wraps the `scrcpy` and `adb` command line tools.
///
/// All processes are launched with the tool's *fully resolved* path and
/// `runInShell: false`, so no `cmd.exe`/terminal window is ever spawned on
/// Windows. Mirror processes are started detached so they outlive the GUI.
class ScrcpyService {
  /// Caches resolved absolute paths (and misses as `null`) per executable name.
  final Map<String, String?> _pathCache = {};

  /// Absolute path override for scrcpy (set after an in-app install).
  String? _scrcpyOverride;

  /// Absolute path override for adb (a sibling of the installed scrcpy).
  String? _adbOverride;

  /// Points scrcpy (and, if present, a sibling adb) at an installed build.
  void useInstalledScrcpy(String scrcpyExePath) {
    _scrcpyOverride = scrcpyExePath;
    final dir = File(scrcpyExePath).parent.path;
    final adb = File('$dir/${Platform.isWindows ? 'adb.exe' : 'adb'}');
    _adbOverride = adb.existsSync() ? adb.path : null;
    _pathCache.clear();
  }

  Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/scrcpy_path.txt');
  }

  /// Loads a previously installed scrcpy path so it survives app restarts.
  Future<void> loadPersistedPath() async {
    try {
      final file = await _configFile();
      if (file.existsSync()) {
        final path = file.readAsStringSync().trim();
        if (path.isNotEmpty && File(path).existsSync()) {
          useInstalledScrcpy(path);
        }
      }
    } catch (_) {}
  }

  /// Remembers an installed scrcpy path for future sessions.
  Future<void> persistPath(String path) async {
    try {
      final file = await _configFile();
      await file.writeAsString(path);
    } catch (_) {}
  }

  /// Detects an available package manager that can install scrcpy.
  /// Prefers Homebrew (no elevation required).
  Future<PackageManager?> detectPackageManager() async {
    if (await _resolve('brew') != null) {
      return const PackageManager('Homebrew', 'brew install scrcpy', true);
    }
    if (Platform.isMacOS) return null;
    const candidates = [
      ['apt', 'sudo apt install -y scrcpy'],
      ['dnf', 'sudo dnf install -y scrcpy'],
      ['pacman', 'sudo pacman -S --noconfirm scrcpy'],
      ['zypper', 'sudo zypper install -y scrcpy'],
      ['snap', 'sudo snap install scrcpy'],
    ];
    for (final c in candidates) {
      if (await _resolve(c[0]) != null) {
        return PackageManager(c[0], c[1], false);
      }
    }
    return null;
  }

  /// Runs `brew install scrcpy` and returns the process result.
  Future<ProcessResult> runBrewInstall() {
    return Process.run('brew', ['install', 'scrcpy'], runInShell: false);
  }

  /// Resolves an executable name to its absolute path via `where` (Windows)
  /// or `which` (Unix). Returns null when not found on PATH.
  Future<String?> _resolve(String name) async {
    if (name == 'scrcpy' && _scrcpyOverride != null) return _scrcpyOverride;
    if (name == 'adb' && _adbOverride != null) return _adbOverride;
    if (_pathCache.containsKey(name)) return _pathCache[name];

    final finder = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await Process.run(finder, [name], runInShell: false);
      if (result.exitCode == 0) {
        final line = result.stdout.toString().split('\n').first.trim();
        _pathCache[name] = line.isEmpty ? null : line;
      } else {
        _pathCache[name] = null;
      }
    } catch (_) {
      _pathCache[name] = null;
    }
    return _pathCache[name];
  }

  /// Runs [name] with [args] (resolving its full path first).
  /// Throws [ScrcpyException] if the executable cannot be found.
  Future<ProcessResult> _run(String name, List<String> args) async {
    final exe = await _resolve(name);
    if (exe == null) {
      throw ScrcpyException('"$name" not found on PATH.');
    }
    try {
      return await Process.run(exe, args, runInShell: false);
    } on ProcessException catch (e) {
      throw ScrcpyException('Failed to run "$name".', details: e.message);
    }
  }

  /// Detects whether scrcpy and adb are installed and reachable on PATH.
  Future<EnvironmentStatus> checkEnvironment() async {
    String? scrcpyVersion;
    bool scrcpyOk = false;
    if (await _resolve('scrcpy') != null) {
      try {
        final result = await _run('scrcpy', ['--version']);
        final out = '${result.stdout}${result.stderr}'.trim();
        scrcpyVersion = out.split('\n').first.trim();
        scrcpyOk = out.toLowerCase().contains('scrcpy');
      } on ScrcpyException {
        scrcpyOk = false;
      }
    }

    String? adbVersion;
    bool adbOk = false;
    if (await _resolve('adb') != null) {
      try {
        final result = await _run('adb', ['version']);
        if (result.exitCode == 0) {
          adbVersion = result.stdout.toString().split('\n').first.trim();
          adbOk = true;
        }
      } on ScrcpyException {
        adbOk = false;
      }
    }

    return EnvironmentStatus(
      scrcpyInstalled: scrcpyOk,
      scrcpyVersion: scrcpyVersion,
      adbInstalled: adbOk,
      adbVersion: adbVersion,
    );
  }

  /// Returns the list of currently connected devices via `adb devices -l`.
  Future<List<Device>> listDevices() async {
    final result = await _run('adb', ['devices', '-l']);
    if (result.exitCode != 0) {
      throw ScrcpyException(
        'Failed to query devices from adb.',
        details: result.stderr.toString().trim(),
      );
    }

    final lines = result.stdout.toString().split('\n');
    final devices = <Device>[];
    for (final line in lines) {
      final device = Device.parseLine(line);
      if (device != null) devices.add(device);
    }
    return devices;
  }

  /// Ensures the adb daemon is running before any `Process.run(adb ...)` call.
  ///
  /// On Windows, letting an adb client auto-start the daemon hangs Dart's
  /// `Process.run` forever: the forked daemon inherits the stdout pipe so it
  /// never reaches EOF. We start it detached (no inherited pipes) and wait for
  /// port 5037 to accept connections.
  Future<void> ensureAdbServer() async {
    final adb = await _resolve('adb');
    if (adb == null) return;

    if (Platform.isWindows) {
      win.launchNoWindow(adb, ['start-server']);
    } else {
      await Process.run(adb, ['start-server'], runInShell: false);
      return;
    }

    for (var i = 0; i < 50; i++) {
      try {
        final s = await Socket.connect(
          InternetAddress.loopbackIPv4,
          5037,
          timeout: const Duration(milliseconds: 200),
        );
        await s.close();
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  /// Connects to a wireless device at `host:port` (`adb connect`).
  Future<String> connectWireless(String hostPort) async {
    await ensureAdbServer();
    final result = await _run('adb', ['connect', hostPort]);
    final out = '${result.stdout}${result.stderr}'.trim();
    if (out.toLowerCase().contains('cannot') ||
        out.toLowerCase().contains('failed') ||
        out.toLowerCase().contains('unable')) {
      throw ScrcpyException('Connection failed.', details: out);
    }
    return out;
  }

  /// Pairs with an Android 11+ device using its Wireless-debugging pairing
  /// `host:port` and 6-digit code (`adb pair`).
  Future<String> pairWireless(String hostPort, String code) async {
    await ensureAdbServer();
    final result = await _run('adb', ['pair', hostPort, code]);
    final out = '${result.stdout}${result.stderr}'.trim();
    if (!out.toLowerCase().contains('successfully')) {
      throw ScrcpyException('Pairing failed.', details: out);
    }
    return out;
  }

  /// Disconnects a wireless device (`adb disconnect`).
  Future<void> disconnectWireless(String hostPort) async {
    await _run('adb', ['disconnect', hostPort]);
  }

  /// Switches a USB-connected [device] to wireless: enables TCP/IP mode,
  /// discovers its Wi-Fi IP and connects to it. Returns the `host:port`.
  Future<String> enableWirelessFromUsb(Device device) async {
    // Read the Wi-Fi IP while still on USB.
    final ipResult = await _run(
      'adb',
      ['-s', device.serial, 'shell', 'ip', '-o', '-4', 'addr', 'show', 'wlan0'],
    );
    final match =
        RegExp(r'inet (\d+\.\d+\.\d+\.\d+)').firstMatch(ipResult.stdout.toString());
    if (match == null) {
      throw ScrcpyException(
        'Could not find the device Wi-Fi IP. Is Wi-Fi on?',
        details: ipResult.stdout.toString().trim(),
      );
    }
    final ip = match.group(1)!;

    final tcpip = await _run('adb', ['-s', device.serial, 'tcpip', '5555']);
    if (tcpip.exitCode != 0) {
      throw ScrcpyException('Failed to enable TCP/IP mode.',
          details: tcpip.stderr.toString().trim());
    }

    // adbd restarts in TCP mode; give it a moment before connecting.
    await Future.delayed(const Duration(milliseconds: 1500));
    return connectWireless('$ip:5555');
  }

  /// Lists installed package names on [serial] via `adb shell pm list packages`.
  /// When [thirdPartyOnly] is true, system apps are excluded (`-3`).
  Future<List<String>> listPackages(
    String serial, {
    bool thirdPartyOnly = true,
  }) async {
    final args = ['-s', serial, 'shell', 'pm', 'list', 'packages'];
    if (thirdPartyOnly) args.add('-3');
    final result = await _run('adb', args);
    if (result.exitCode != 0) {
      throw ScrcpyException(
        'Failed to list packages.',
        details: result.stderr.toString().trim(),
      );
    }
    final packages = <String>[];
    for (final line in result.stdout.toString().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('package:')) {
        packages.add(trimmed.substring('package:'.length).trim());
      }
    }
    packages.sort();
    return packages;
  }

  /// Launches scrcpy for [device] as a detached process (no console window,
  /// survives GUI close). Returns the OS process id so the caller can track
  /// and later stop the session. Throws [ScrcpyException] on failure.
  Future<int> startMirror(Device device, [MirrorOptions? options]) async {
    if (!device.isReady) {
      throw ScrcpyException(
        'Device "${device.displayName}" is not ready (${device.statusLabel}).',
      );
    }
    final exe = await _resolve('scrcpy');
    if (exe == null) {
      throw ScrcpyException('"scrcpy" not found on PATH.');
    }
    final args = (options ?? MirrorOptions.defaults).toArgs(device.serial);

    if (Platform.isWindows) {
      // Launch via Win32 CreateProcess with CREATE_NO_WINDOW so no console
      // window ever appears (Dart's detached mode spawns one on Windows).
      final pid = win.launchNoWindow(exe, args);
      if (pid == 0) {
        throw ScrcpyException('Could not launch scrcpy.');
      }
      return pid;
    }

    try {
      final process = await Process.start(
        exe,
        args,
        runInShell: false,
        mode: ProcessStartMode.detached,
      );
      return process.pid;
    } on ProcessException catch (e) {
      throw ScrcpyException('Could not launch scrcpy.', details: e.message);
    }
  }

  /// Returns true if a mirror process with [pid] is still alive.
  Future<bool> isRunning(int pid) async {
    if (Platform.isWindows) {
      return win.isProcessRunning(pid);
    }
    try {
      final result = await Process.run('kill', ['-0', '$pid']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Stops a running mirror session by killing its process id.
  /// Safe to call on an already-dead pid.
  void stopMirror(int pid) {
    if (Platform.isWindows) {
      win.terminateProcess(pid);
    } else {
      Process.killPid(pid, ProcessSignal.sigterm);
    }
  }
}
