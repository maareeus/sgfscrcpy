import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/mirror_options.dart';

/// A dialog to configure scrcpy options before launching a mirror session.
/// Returns the chosen [MirrorOptions] via `Navigator.pop`, or null if cancelled.
class LaunchOptionsDialog extends StatefulWidget {
  final Device device;
  final MirrorOptions initial;

  const LaunchOptionsDialog({
    super.key,
    required this.device,
    required this.initial,
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
              const SizedBox(height: 8),
              _sectionLabel(theme, 'Virtual display'),
              Text(
                'Runs a separate Android screen (scrcpy 3.0+, Android 11+).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              _switch('Enable virtual display', _o.virtualDisplay,
                  (v) => setState(() => _o = _o.copyWith(virtualDisplay: v))),
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
                _textField(
                  _startAppController,
                  'Launch app (package)',
                  'e.g. com.android.chrome',
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
