import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../models/reverse_rule.dart';

/// Edits the persistent `adb reverse` rules for a device.
/// Pops the new list of rules, or null if cancelled.
class ReversePortsDialog extends StatefulWidget {
  final Device device;
  final List<ReverseRule> initial;

  const ReversePortsDialog({
    super.key,
    required this.device,
    required this.initial,
  });

  @override
  State<ReversePortsDialog> createState() => _ReversePortsDialogState();
}

class _ReversePortsDialogState extends State<ReversePortsDialog> {
  late final List<ReverseRule> _rules = List.of(widget.initial);
  final _deviceController = TextEditingController();
  final _pcController = TextEditingController();

  @override
  void dispose() {
    _deviceController.dispose();
    _pcController.dispose();
    super.dispose();
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
