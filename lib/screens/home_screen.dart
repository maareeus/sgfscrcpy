import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/device.dart';
import '../models/mirror_options.dart';
import '../models/reverse_rule.dart';
import '../services/reverse_config.dart';
import '../services/scrcpy_service.dart';
import '../services/scrcpy_updater.dart';
import '../widgets/device_card.dart';
import '../widgets/launch_options_dialog.dart';
import '../widgets/reverse_ports_dialog.dart';
import '../widgets/wireless_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrcpyService _service = ScrcpyService();
  final ScrcpyUpdater _updater = ScrcpyUpdater();
  final ReverseConfigStore _reverseStore = ReverseConfigStore();

  /// Serials whose persisted reverse rules were already applied this session.
  final Set<String> _reverseApplied = {};

  bool _loading = true;
  EnvironmentStatus? _env;
  List<Device> _devices = [];
  String? _error;

  /// Serial -> OS pid of scrcpy sessions this app launched.
  final Map<String, int> _sessions = {};

  /// Serial -> last options used, so the dialog remembers per-device choices.
  final Map<String, MirrorOptions> _lastOptions = {};

  /// Watches launched sessions so cards reset when the user closes scrcpy.
  Timer? _livenessTimer;

  // Update state.
  ReleaseInfo? _latest;
  bool _updateAvailable = false;
  bool _installing = false;
  double? _installProgress;
  String? _installStatus;

  /// Detected package manager on macOS/Linux (null on Windows / none found).
  PackageManager? _packageManager;

  @override
  void initState() {
    super.initState();
    _livenessTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pruneDeadSessions(),
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _service.ensureAdbServer();
    await _service.loadPersistedPath();
    await _reverseStore.load();
    if (!Platform.isWindows) {
      _packageManager = await _service.detectPackageManager();
    }
    await _refresh();
  }

  @override
  void dispose() {
    _livenessTimer?.cancel();
    super.dispose();
  }

  /// Removes sessions whose scrcpy process has exited (window closed).
  Future<void> _pruneDeadSessions() async {
    if (_sessions.isEmpty) return;
    final dead = <String>[];
    for (final entry in _sessions.entries) {
      if (!await _service.isRunning(entry.value)) dead.add(entry.key);
    }
    if (dead.isNotEmpty && mounted) {
      setState(() => dead.forEach(_sessions.remove));
    }
  }

  Future<void> _checkForUpdate() async {
    final env = _env;
    if (env == null) return;
    try {
      final latest = await _updater.fetchLatest();
      final newer = env.scrcpyInstalled &&
          ScrcpyUpdater.compareVersions(latest.version, env.scrcpyVersion) > 0;
      if (!mounted) return;
      setState(() {
        _latest = latest;
        _updateAvailable = newer;
      });
    } catch (_) {
      // Update check is best-effort; ignore network failures silently.
    }
  }

  /// Windows: download + extract the official build. macOS/Linux: run the
  /// package manager if it needs no elevation (Homebrew), otherwise fall back.
  Future<void> _installUpdate() async {
    if (Platform.isWindows) {
      await _installWindows();
    } else {
      await _installUnix();
    }
  }

  Future<void> _installWindows() async {
    final latest = _latest;
    if (latest == null) return;
    setState(() {
      _installing = true;
      _installProgress = null;
      _installStatus = 'Starting…';
    });
    try {
      final exePath = await _updater.installWindows(latest, (progress, status) {
        if (!mounted) return;
        setState(() {
          _installProgress = progress;
          _installStatus = status;
        });
      });
      _service.useInstalledScrcpy(exePath);
      await _service.persistPath(exePath);
      if (!mounted) return;
      setState(() {
        _installing = false;
        _updateAvailable = false;
      });
      _showSnack('scrcpy ${latest.tag} installed');
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _installing = false);
      _showSnack('Install failed: $e', isError: true);
    }
  }

  Future<void> _installUnix() async {
    final pm = _packageManager;

    // No manager, or one that needs sudo: we can't run it safely in-app.
    if (pm == null || !pm.canAutoRun) {
      await launchUrl(
        Uri.parse('https://github.com/Genymobile/scrcpy/blob/master/doc/'),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    // Homebrew: run it, stream nothing but show a spinner.
    setState(() {
      _installing = true;
      _installProgress = null;
      _installStatus = 'Running ${pm.command}…';
    });
    try {
      final result = await _service.runBrewInstall();
      if (!mounted) return;
      setState(() => _installing = false);
      if (result.exitCode == 0) {
        _showSnack('scrcpy installed via ${pm.name}');
        await _refresh();
      } else {
        _showSnack(
          'Install failed: ${result.stderr.toString().trim()}',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _installing = false);
      _showSnack('Install failed: $e', isError: true);
    }
  }

  Future<void> _copyInstallCommand() async {
    final pm = _packageManager;
    if (pm == null) return;
    await Clipboard.setData(ClipboardData(text: pm.command));
    _showSnack('Command copied — paste it in a terminal');
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final env = await _service.checkEnvironment();
      List<Device> devices = [];
      if (env.adbInstalled) {
        devices = await _service.listDevices();
      }
      if (!mounted) return;
      final liveSerials = devices.map((d) => d.serial).toSet();
      _sessions.removeWhere((serial, _) => !liveSerials.contains(serial));
      _reverseApplied.removeWhere((s) => !liveSerials.contains(s));
      setState(() {
        _env = env;
        _devices = devices;
        _loading = false;
      });
      _applyReverseRules(devices);
      _checkForUpdate();
    } on ScrcpyException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.details == null ? e.message : '${e.message}\n${e.details}';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openWirelessDialog() async {
    final connected = await showDialog<bool>(
      context: context,
      builder: (_) => WirelessDialog(service: _service),
    );
    if (connected == true) await _refresh();
  }

  Future<void> _enableWireless(Device device) async {
    _showSnack('Enabling Wi-Fi for ${device.displayName}…');
    try {
      final hostPort = await _service.enableWirelessFromUsb(device);
      if (!mounted) return;
      _showSnack('Connected at $hostPort — you can unplug the cable');
      await _refresh();
    } on ScrcpyException catch (e) {
      if (!mounted) return;
      _showSnack(
        e.details == null ? e.message : '${e.message} (${e.details})',
        isError: true,
      );
    }
  }

  /// Reapplies persisted reverse rules for freshly connected ready devices.
  Future<void> _applyReverseRules(List<Device> devices) async {
    for (final device in devices) {
      if (!device.isReady || _reverseApplied.contains(device.serial)) continue;
      final rules = _reverseStore.rulesFor(device.serial);
      if (rules.isEmpty) continue;
      for (final rule in rules) {
        try {
          await _service.applyReverse(device.serial, rule);
        } catch (_) {}
      }
      _reverseApplied.add(device.serial);
    }
  }

  Future<void> _openReverseDialog(Device device) async {
    final result = await showDialog<List<ReverseRule>>(
      context: context,
      builder: (_) => ReversePortsDialog(
        device: device,
        initial: _reverseStore.rulesFor(device.serial),
        onLoadActive: () => _service.listReverse(device.serial),
        onReapply: (rule) => _service.applyReverse(device.serial, rule),
      ),
    );
    if (result == null) return;

    final previous = _reverseStore.rulesFor(device.serial).toSet();
    final current = result.toSet();
    for (final removed in previous.difference(current)) {
      try {
        await _service.removeReverse(device.serial, removed);
      } catch (_) {}
    }
    for (final rule in current) {
      try {
        await _service.applyReverse(device.serial, rule);
      } catch (_) {}
    }
    await _reverseStore.setRules(device.serial, result);
    _reverseApplied.add(device.serial);
    if (mounted) {
      setState(() {}); // refresh the card's rule-count badge
      _showSnack('Reverse ports saved (${result.length})');
    }
  }

  Future<void> _openLaunchDialog(Device device) async {
    final options = await showDialog<MirrorOptions>(
      context: context,
      builder: (_) => LaunchOptionsDialog(
        device: device,
        initial: _lastOptions[device.serial] ?? MirrorOptions.defaults,
        onListPackages: (thirdPartyOnly) =>
            _service.listPackages(device.serial, thirdPartyOnly: thirdPartyOnly),
      ),
    );
    if (options == null) return; // cancelled
    _lastOptions[device.serial] = options;
    await _launch(device, options);
  }

  Future<void> _launch(Device device, MirrorOptions options) async {
    try {
      final pid = await _service.startMirror(device, options);
      if (!mounted) return;
      setState(() => _sessions[device.serial] = pid);
      _showSnack('Mirroring ${device.displayName}…');
    } on ScrcpyException catch (e) {
      if (!mounted) return;
      _showSnack(
        e.details == null ? e.message : '${e.message} (${e.details})',
        isError: true,
      );
    }
  }

  void _stop(Device device) {
    final pid = _sessions[device.serial];
    if (pid != null) {
      _service.stopMirror(pid);
    }
    setState(() => _sessions.remove(device.serial));
    _showSnack('Stopped ${device.displayName}');
  }

  void _showSnack(String message, {bool isError = false}) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? theme.colorScheme.error : theme.colorScheme.surfaceContainerHighest,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                env: _env,
                loading: _loading,
                onRefresh: _loading ? null : _refresh,
                onWireless: _openWirelessDialog,
              ),
              if (_updateAvailable && _latest != null) ...[
                const SizedBox(height: 18),
                _UpdateBanner(
                  tag: _latest!.tag,
                  installing: _installing,
                  progress: _installProgress,
                  status: _installStatus,
                  onInstall: _installing ? null : _installUpdate,
                ),
              ],
              const SizedBox(height: 28),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _MessageState(
        icon: Icons.error_outline,
        iconColor: Theme.of(context).colorScheme.error,
        title: 'Something went wrong',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _refresh,
      );
    }

    final env = _env;
    if (env != null && !env.isReady) {
      final canAutoInstall = Platform.isWindows
          ? _latest != null
          : (_packageManager?.canAutoRun ?? false);
      return _EnvironmentError(
        env: env,
        onRetry: _refresh,
        canAutoInstall: canAutoInstall,
        installLabel: Platform.isWindows
            ? 'Install scrcpy'
            : 'Install with ${_packageManager?.name ?? ''}',
        manualCommand:
            (!Platform.isWindows && !(_packageManager?.canAutoRun ?? false))
                ? _packageManager?.command
                : null,
        installing: _installing,
        progress: _installProgress,
        status: _installStatus,
        onInstall: _installUpdate,
        onCopyCommand: _copyInstallCommand,
      );
    }

    if (_devices.isEmpty) {
      return _MessageState(
        icon: Icons.usb_off,
        iconColor: Colors.white38,
        title: 'No devices connected',
        message:
            'Plug in an Android device with USB debugging enabled, or pair it over Wi-Fi, then refresh.',
        actionLabel: 'Refresh',
        onAction: _refresh,
      );
    }

    return SingleChildScrollView(
      child: Wrap(
        spacing: 20,
        runSpacing: 20,
        children: [
          for (final device in _devices)
            DeviceCard(
              device: device,
              mirroring: _sessions.containsKey(device.serial),
              onLaunch: () => _openLaunchDialog(device),
              onStop: () => _stop(device),
              onEnableWireless:
                  device.isReady && !device.isWireless
                      ? () => _enableWireless(device)
                      : null,
              onReversePorts:
                  device.isReady ? () => _openReverseDialog(device) : null,
              reverseCount: _reverseStore.rulesFor(device.serial).length,
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final EnvironmentStatus? env;
  final bool loading;
  final VoidCallback? onRefresh;
  final VoidCallback? onWireless;

  const _Header({
    required this.env,
    required this.loading,
    this.onRefresh,
    this.onWireless,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withValues(alpha: 0.6),
              ],
            ),
          ),
          child: const Icon(Icons.cast, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SgfScrcpy',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              env?.scrcpyVersion ?? 'Simple GUI for Scrcpy',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: onWireless,
          icon: const Icon(Icons.wifi, size: 18),
          label: const Text('Wi-Fi'),
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: onRefresh,
          icon: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
      ],
    );
  }
}

/// Banner shown when a newer scrcpy release is available.
class _UpdateBanner extends StatelessWidget {
  final String tag;
  final bool installing;
  final double? progress;
  final String? status;
  final VoidCallback? onInstall;

  const _UpdateBanner({
    required this.tag,
    required this.installing,
    required this.progress,
    required this.status,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionLabel = Platform.isWindows ? 'Update now' : 'Download';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.system_update_alt, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  installing
                      ? (status ?? 'Installing…')
                      : 'scrcpy $tag is available',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (installing) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (installing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton.icon(
              onPressed: onInstall,
              icon: const Icon(Icons.download, size: 18),
              label: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}

/// Shown when scrcpy and/or adb are not installed.
class _EnvironmentError extends StatelessWidget {
  final EnvironmentStatus env;
  final VoidCallback onRetry;

  /// True when we can offer a one-click auto-install
  /// (Windows download, or a no-sudo package manager like Homebrew).
  final bool canAutoInstall;
  final String installLabel;

  /// A copy-paste install command shown when auto-install isn't possible
  /// (e.g. a Linux package manager that needs sudo).
  final String? manualCommand;
  final bool installing;
  final double? progress;
  final String? status;
  final VoidCallback? onInstall;
  final VoidCallback? onCopyCommand;

  const _EnvironmentError({
    required this.env,
    required this.onRetry,
    required this.canAutoInstall,
    required this.installLabel,
    required this.manualCommand,
    required this.installing,
    required this.progress,
    required this.status,
    required this.onInstall,
    required this.onCopyCommand,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.build_circle_outlined,
                size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 20),
            Text(
              'Setup required',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _CheckRow(
              label: 'scrcpy',
              ok: env.scrcpyInstalled,
              detail: env.scrcpyVersion,
            ),
            const SizedBox(height: 8),
            _CheckRow(
              label: 'adb (Android Platform Tools)',
              ok: env.adbInstalled,
              detail: env.adbVersion,
            ),
            const SizedBox(height: 20),
            Text(
              canAutoInstall
                  ? 'SgfScrcpy can install a self-contained scrcpy build (adb included) for you.'
                  : manualCommand != null
                      ? 'Run this command to install scrcpy, then hit Retry:'
                      : 'Install scrcpy and adb, make sure they are on your PATH, then retry.\n'
                          'See github.com/Genymobile/scrcpy for instructions.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            if (manualCommand != null && !canAutoInstall) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: SelectableText(
                        manualCommand!,
                        style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onCopyCommand,
                      tooltip: 'Copy',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy, size: 18),
                    ),
                  ],
                ),
              ),
            ],
            if (installing) ...[
              const SizedBox(height: 20),
              Text(
                status ?? 'Installing…',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: progress, minHeight: 6),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canAutoInstall && !installing) ...[
                  FilledButton.icon(
                    onPressed: onInstall,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(installLabel),
                  ),
                  const SizedBox(width: 12),
                ],
                OutlinedButton.icon(
                  onPressed: installing ? null : onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool ok;
  final String? detail;

  const _CheckRow({required this.label, required this.ok, this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.cancel,
          color: ok ? const Color(0xFF2ECC71) : theme.colorScheme.error,
          size: 20,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (ok && detail != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Generic centered state used for empty / error screens.
class _MessageState extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _MessageState({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: iconColor),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
