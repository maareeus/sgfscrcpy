import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/mirror_options.dart';

/// A dialog to configure scrcpy options before launching a mirror session.
/// Returns the chosen [MirrorOptions] via `Navigator.pop`, or null if cancelled.
class LaunchOptionsDialog extends StatefulWidget {
  final Device device;
  final MirrorOptions initial;

  /// Fetches installed packages for the device (thirdPartyOnly toggle).
  final Future<List<String>> Function(bool thirdPartyOnly) onListPackages;

  const LaunchOptionsDialog({
    super.key,
    required this.device,
    required this.initial,
    required this.onListPackages,
  });

  @override
  State<LaunchOptionsDialog> createState() => _LaunchOptionsDialogState();
}

class _LaunchOptionsDialogState extends State<LaunchOptionsDialog> {
  late MirrorOptions _o = widget.initial;

  final _resolutionController = TextEditingController();
  final _dpiController = TextEditingController();
  final _startAppController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _resolutionController.text = widget.initial.virtualDisplayResolution ?? '';
    _dpiController.text = widget.initial.virtualDisplayDpi?.toString() ?? '';
    _startAppController.text = widget.initial.startAppPackage ?? '';
  }

  @override
  void dispose() {
    _resolutionController.dispose();
    _dpiController.dispose();
    _startAppController.dispose();
    super.dispose();
  }

  Future<void> _pickApp() async {
    final pkg = await showDialog<String>(
      context: context,
      builder: (_) => _PackagePickerDialog(onList: widget.onListPackages),
    );
    if (pkg != null && mounted) {
      setState(() => _startAppController.text = pkg);
    }
  }

  /// Applies a tablet-friendly virtual display: 1080p at 180 DPI (≈960dp wide,
  /// which triggers large-screen/two-pane layouts) with a UHID keyboard.
  void _applyTabletPreset() {
    setState(() {
      _o = _o.copyWith(
        virtualDisplay: true,
        virtualDisplayResolution: '1920x1080',
        virtualDisplayDpi: 180,
        keyboardMode: 'uhid',
      );
      _resolutionController.text = '1920x1080';
      _dpiController.text = '180';
    });
  }

  void _start() {
    // Fold text fields into the options.
    final res = _resolutionController.text.trim();
    final dpi = int.tryParse(_dpiController.text.trim());
    final app = _startAppController.text.trim();
    final result = _o.copyWith(
      virtualDisplayResolution: res.isEmpty ? null : res,
      clearResolution: res.isEmpty,
      virtualDisplayDpi: dpi,
      clearDpi: dpi == null,
      startAppPackage: app.isEmpty ? null : app,
      clearStartApp: app.isEmpty,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.tune, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.device.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sectionLabel(theme, 'Video'),
              _dropdown<int?>(
                label: 'Max size',
                value: _o.maxSize,
                items: const {
                  null: 'Auto',
                  1024: '1024 px',
                  1280: '1280 px',
                  1920: '1920 px',
                },
                onChanged: (v) => setState(() => _o = _o.copyWith(
                      maxSize: v,
                      clearMaxSize: v == null,
                    )),
              ),
              _dropdown<int?>(
                label: 'Bitrate',
                value: _o.videoBitrateMbps,
                items: const {
                  null: 'Auto',
                  4: '4 Mbps',
                  8: '8 Mbps',
                  16: '16 Mbps',
                  32: '32 Mbps',
                },
                onChanged: (v) => setState(() => _o = _o.copyWith(
                      videoBitrateMbps: v,
                      clearBitrate: v == null,
                    )),
              ),
              _dropdown<int?>(
                label: 'Max FPS',
                value: _o.maxFps,
                items: const {
                  null: 'Auto',
                  30: '30',
                  60: '60',
                  120: '120',
                },
                onChanged: (v) => setState(() => _o = _o.copyWith(
                      maxFps: v,
                      clearMaxFps: v == null,
                    )),
              ),
              const SizedBox(height: 8),
              _sectionLabel(theme, 'Behavior'),
              _switch('Fullscreen', _o.fullscreen,
                  (v) => setState(() => _o = _o.copyWith(fullscreen: v))),
              _switch('Keep device awake', _o.stayAwake,
                  (v) => setState(() => _o = _o.copyWith(stayAwake: v))),
              _switch('Turn device screen off', _o.turnScreenOff,
                  (v) => setState(() => _o = _o.copyWith(turnScreenOff: v))),
              _switch('Show touches', _o.showTouches,
                  (v) => setState(() => _o = _o.copyWith(showTouches: v))),
              _switch('Forward audio', _o.audioEnabled,
                  (v) => setState(() => _o = _o.copyWith(audioEnabled: v))),
              _dropdown<String?>(
                label: 'Keyboard',
                value: _o.keyboardMode,
                items: const {
                  null: 'Default (SDK)',
                  'uhid': 'Physical (UHID)',
                  'aoa': 'Physical (AOA)',
                  'disabled': 'Disabled',
                },
                onChanged: (v) => setState(() => _o = _o.copyWith(
                      keyboardMode: v,
                      clearKeyboardMode: v == null,
                    )),
              ),
              Text(
                'Use UHID for reliable typing on a virtual display.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 8),
              _sectionLabel(theme, 'Virtual display'),
              Text(
                'Runs a separate Android screen (scrcpy 3.0+, Android 11+).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.tablet_mac, size: 18),
                  label: const Text('Tablet preset (1080p · 180dpi)'),
                  onPressed: _applyTabletPreset,
                ),
              ),
              _switch(
                'Enable virtual display',
                _o.virtualDisplay,
                (v) => setState(() {
                  // Default to UHID keyboard when turning on a virtual display,
                  // since the SDK keyboard often fails to type there.
                  _o = _o.copyWith(
                    virtualDisplay: v,
                    keyboardMode: v && _o.keyboardMode == null
                        ? 'uhid'
                        : _o.keyboardMode,
                  );
                }),
              ),
              if (_o.virtualDisplay) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _textField(
                        _resolutionController,
                        'Resolution',
                        'e.g. 1920x1080',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _textField(_dpiController, 'DPI', 'e.g. 240'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _textField(
                        _startAppController,
                        'Launch app (package)',
                        'e.g. com.android.chrome',
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _pickApp,
                      tooltip: 'Pick installed app',
                      icon: const Icon(Icons.apps),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Leave resolution empty to match the device. Package optional.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Start'),
        ),
      ],
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox.shrink(),
            items: [
              for (final entry in items.entries)
                DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (v) => onChanged(v as T),
          ),
        ],
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label,
    String hint,
  ) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// A searchable list of installed packages, returning the chosen one.
class _PackagePickerDialog extends StatefulWidget {
  final Future<List<String>> Function(bool thirdPartyOnly) onList;

  const _PackagePickerDialog({required this.onList});

  @override
  State<_PackagePickerDialog> createState() => _PackagePickerDialogState();
}

class _PackagePickerDialogState extends State<_PackagePickerDialog> {
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _thirdPartyOnly = true;
  String? _error;
  List<String> _all = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.onList(_thirdPartyOnly);
      if (!mounted) return;
      setState(() {
        _all = list;
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

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _all
        : _all.where((p) => p.toLowerCase().contains(_query)).toList();

    return AlertDialog(
      title: const Text('Pick an app'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Filter packages…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            Row(
              children: [
                Switch(
                  value: _thirdPartyOnly,
                  onChanged: _loading
                      ? null
                      : (v) {
                          setState(() => _thirdPartyOnly = v);
                          _load();
                        },
                ),
                const Text('User apps only'),
                const Spacer(),
                if (!_loading)
                  Text(
                    '${filtered.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(child: _buildList(filtered)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildList(List<String> filtered) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (filtered.isEmpty) {
      return const Center(child: Text('No packages found'));
    }
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final pkg = filtered[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.android, size: 20),
          title: Text(pkg, style: const TextStyle(fontSize: 13)),
          onTap: () => Navigator.of(context).pop(pkg),
        );
      },
    );
  }
}
