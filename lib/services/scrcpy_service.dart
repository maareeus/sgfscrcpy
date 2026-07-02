import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/device.dart';
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

  /// Launches scrcpy for [device] as a detached process (no console window,
  /// survives GUI close). Returns the OS process id so the caller can track
  /// and later stop the session. Throws [ScrcpyException] on failure.
  Future<int> startMirror(Device device) async {
    if (!device.isReady) {
      throw ScrcpyException(
        'Device "${device.displayName}" is not ready (${device.statusLabel}).',
      );
    }
    final exe = await _resolve('scrcpy');
    if (exe == null) {
      throw ScrcpyException('"scrcpy" not found on PATH.');
    }
    final args = ['--serial', device.serial];

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
