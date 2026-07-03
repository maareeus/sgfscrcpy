import 'package:flutter/material.dart';

import '../services/scrcpy_service.dart';

/// Dialog to connect to a device over Wi-Fi: direct connect, or pair first
/// (Android 11+ Wireless debugging). Pops `true` if something connected.
class WirelessDialog extends StatefulWidget {
  final ScrcpyService service;

  const WirelessDialog({super.key, required this.service});

  @override
  State<WirelessDialog> createState() => _WirelessDialogState();
}

class _WirelessDialogState extends State<WirelessDialog> {
  final _connectController = TextEditingController(text: ':5555');
  final _pairController = TextEditingController();
  final _codeController = TextEditingController();

  bool _busy = false;
  String? _message;
  bool _messageIsError = false;
  bool _connectedSomething = false;

  @override
  void dispose() {
    _connectController.dispose();
    _pairController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _setMessage(String m, {bool error = false}) {
    setState(() {
      _message = m;
      _messageIsError = error;
    });
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final out = await action();
      _setMessage(out);
    } on ScrcpyException catch (e) {
      _setMessage(e.details == null ? e.message : '${e.message}\n${e.details}',
          error: true);
    } catch (e) {
      _setMessage(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final host = _connectController.text.trim();
    if (host.isEmpty || host.startsWith(':')) {
      _setMessage('Enter an address like 192.168.1.42:5555', error: true);
      return;
    }
    await _run(() async {
      final out = await widget.service.connectWireless(host);
      _connectedSomething = true;
      return out;
    });
  }

  Future<void> _pair() async {
    final host = _pairController.text.trim();
    final code = _codeController.text.trim();
    if (host.isEmpty || code.isEmpty) {
      _setMessage('Enter the pairing address and code', error: true);
      return;
    }
    await _run(() => widget.service.pairWireless(host, code));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.wifi, size: 22),
          SizedBox(width: 10),
          Text('Connect over Wi-Fi'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Connect',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _connectController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        hintText: '192.168.1.42:5555',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _busy ? null : _connect,
                    child: const Text('Connect'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Pair (Android 11+)',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 4),
              Text(
                'On the phone: Developer options → Wireless debugging → '
                'Pair device with pairing code.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pairController,
                decoration: const InputDecoration(
                  labelText: 'Pairing address',
                  hintText: '192.168.1.42:37115',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Pairing code',
                        hintText: '123456',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _pair,
                    child: const Text('Pair'),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_messageIsError
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_message!),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_connectedSomething),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
