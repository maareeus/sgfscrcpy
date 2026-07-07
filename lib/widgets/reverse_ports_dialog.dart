import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../models/reverse_rule.dart';

/// Edits the persistent `adb reverse` rules for a device.
/// Pops the new list of rules, or null if cancelled.
class ReversePortsDialog extends StatefulWidget {
  final Device device;
  final List<ReverseRule> initial;

  /// Reads the currently-active `adb reverse` mappings for the device.
  final Future<List<ReverseRule>> Function() onLoadActive;

  /// Reapplies (or applies) a single rule to adb.
  final Future<void> Function(ReverseRule rule) onReapply;

  const ReversePortsDialog({
    super.key,
    required this.device,
    required this.initial,
    required this.onLoadActive,
    required this.onReapply,
  });

  @override
  State<ReversePortsDialog> createState() => _ReversePortsDialogState();
}

class _ReversePortsDialogState extends State<ReversePortsDialog> {
  late final List<ReverseRule> _rules = List.of(widget.initial);
  final _deviceController = TextEditingController();
  final _pcController = TextEditingController();

  List<ReverseRule>? _active;
  bool _loadingActive = true;

  @override
  void initState() {
    super.initState();
    _refreshActive();
  }

  @override
  void dispose() {
    _deviceController.dispose();
    _pcController.dispose();
    super.dispose();
  }

  Future<void> _refreshActive() async {
    setState(() => _loadingActive = true);
    try {
      final active = await widget.onLoadActive();
      if (!mounted) return;
      setState(() {
        _active = active;
        _loadingActive = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _active = const [];
        _loadingActive = false;
      });
    }
  }

  Future<void> _reapplyMissing() async {
    final active = _active?.toSet() ?? {};
    final missing = _rules.where((r) => !active.contains(r)).toList();
    if (missing.isEmpty) return;
    for (final rule in missing) {
      try {
        await widget.onReapply(rule);
      } catch (_) {}
    }
    await _refreshActive();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reapplied ${missing.length} rule(s)')),
      );
    }
  }

  /// Adds the rule currently typed in the fields, if valid. Returns false when
  /// the fields hold partial/invalid input that shouldn't be silently dropped.
  bool _commitPending() {
    final deviceText = _deviceController.text.trim();
    final pcText = _pcController.text.trim();
    if (deviceText.isEmpty && pcText.isEmpty) return true; // nothing pending
    final device = int.tryParse(deviceText);
    final pc = int.tryParse(pcText);
    if (device == null || pc == null || device <= 0 || pc <= 0) return false;
    setState(() {
      _rules.removeWhere((r) => r.devicePort == device); // one rule per port
      _rules.add(ReverseRule(device, pc));
      _deviceController.clear();
      _pcController.clear();
    });
    return true;
  }

  void _add() {
    if (!_commitPending()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both a device port and a PC port')),
      );
    }
  }

  void _save() {
    if (!_commitPending()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both a device port and a PC port')),
      );
      return;
    }
    Navigator.of(context).pop(_rules);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings_ethernet, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Reverse ports — ${widget.device.displayName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The device reaches your PC at 127.0.0.1:<device port>, tunnelled '
              'to your PC port. Saved per device and reapplied on connect.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 14),
            if (_rules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No rules yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.4),
                    )),
              )
            else
              ..._rules.map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.swap_horiz, size: 20),
                    title: Text('device tcp:${r.devicePort}  →  PC tcp:${r.pcPort}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => setState(() => _rules.remove(r)),
                    ),
                  )),
            const Divider(),
            _ActiveRulesPanel(
              loading: _loadingActive,
              active: _active,
              configured: _rules,
              onRefresh: _refreshActive,
              onReapplyMissing: _reapplyMissing,
            ),
            const Divider(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _deviceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Device port',
                      hintText: '8080',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                Expanded(
                  child: TextField(
                    controller: _pcController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'PC port',
                      hintText: '8080',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add rule',
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save & apply'),
        ),
      ],
    );
  }
}

/// Read-only view of `adb reverse --list` output, cross-referenced with the
/// configured rules so the user can see which mappings are actually live.
class _ActiveRulesPanel extends StatelessWidget {
  final bool loading;
  final List<ReverseRule>? active;
  final List<ReverseRule> configured;
  final VoidCallback onRefresh;
  final VoidCallback onReapplyMissing;

  const _ActiveRulesPanel({
    required this.loading,
    required this.active,
    required this.configured,
    required this.onRefresh,
    required this.onReapplyMissing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeSet = active?.toSet() ?? {};
    final configuredSet = configured.toSet();
    final missingCount =
        configuredSet.difference(activeSet).length; // configured but not live
    final extras = activeSet.difference(configuredSet); // live but not saved

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Currently active in adb',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const Spacer(),
            if (missingCount > 0)
              TextButton.icon(
                onPressed: onReapplyMissing,
                icon: const Icon(Icons.replay, size: 16),
                label: Text('Reapply $missingCount'),
              ),
            IconButton(
              onPressed: loading ? null : onRefresh,
              visualDensity: VisualDensity.compact,
              tooltip: 'Refresh',
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (loading && active == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Loading…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          )
        else if (active == null || active!.isEmpty)
          Text(
            'No live mappings for this device.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.5),
            ),
          )
        else
          ...active!.map((rule) {
            final saved = configuredSet.contains(rule);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    saved ? Icons.check_circle : Icons.info_outline,
                    size: 16,
                    color: saved
                        ? const Color(0xFF2ECC71)
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'device tcp:${rule.devicePort}  →  PC tcp:${rule.pcPort}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (!saved) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(not saved)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        if (extras.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${extras.length} live mapping(s) not in your saved rules.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
    );
  }
}
