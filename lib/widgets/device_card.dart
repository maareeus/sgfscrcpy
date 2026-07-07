import 'package:flutter/material.dart';

import '../models/device.dart';

/// A modern, tappable card representing a single device.
class DeviceCard extends StatefulWidget {
  final Device device;
  final VoidCallback onLaunch;

  /// True when this app has an active scrcpy session for the device.
  final bool mirroring;

  /// Called when the user stops an active session.
  final VoidCallback onStop;

  /// Called to switch a USB device to wireless; null hides the action.
  final VoidCallback? onEnableWireless;

  /// Called to edit persistent adb reverse rules; null hides the action.
  final VoidCallback? onReversePorts;

  /// Number of configured reverse rules (shown as a small badge).
  final int reverseCount;

  const DeviceCard({
    super.key,
    required this.device,
    required this.onLaunch,
    required this.mirroring,
    required this.onStop,
    this.onEnableWireless,
    this.onReversePorts,
    this.reverseCount = 0,
  });

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  bool _hovered = false;

  Color get _statusColor {
    final d = widget.device;
    if (widget.mirroring) return const Color(0xFF6C5CE7);
    if (d.isReady) return const Color(0xFF2ECC71);
    if (d.isUnauthorized) return const Color(0xFFF1C40F);
    return const Color(0xFFE74C3C);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = widget.device;
    final mirroring = widget.mirroring;
    final enabled = device.isReady && !mirroring;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: device.isReady
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 220,
        transform: _hovered && enabled
            ? (Matrix4.identity()..translateByDouble(0.0, -4.0, 0.0, 1.0))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surfaceContainerHighest,
              theme.colorScheme.surface,
            ],
          ),
          border: Border.all(
            color: _hovered && enabled
                ? theme.colorScheme.primary.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.06),
            width: 1.2,
          ),
          boxShadow: _hovered && enabled
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: enabled ? widget.onLaunch : null,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          device.isWireless
                              ? Icons.wifi_tethering
                              : Icons.smartphone,
                          color: theme.colorScheme.primary,
                          size: 26,
                        ),
                      ),
                      const Spacer(),
                      if (widget.onReversePorts != null)
                        IconButton(
                          onPressed: widget.onReversePorts,
                          tooltip: widget.reverseCount > 0
                              ? 'Reverse ports (${widget.reverseCount})'
                              : 'Reverse ports',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.settings_ethernet,
                            size: 20,
                            color: widget.reverseCount > 0
                                ? theme.colorScheme.primary
                                : Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      if (widget.onEnableWireless != null)
                        IconButton(
                          onPressed: widget.onEnableWireless,
                          tooltip: 'Switch to Wi-Fi',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.wifi,
                            size: 20,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      const SizedBox(width: 4),
                      _StatusDot(color: _statusColor),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    device.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    device.serial,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        mirroring ? 'Mirroring' : device.statusLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: mirroring
                              ? theme.colorScheme.primary
                              : _statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (mirroring)
                        IconButton(
                          onPressed: widget.onStop,
                          tooltip: 'Stop mirroring',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.stop_circle,
                            color: Color(0xFFE74C3C),
                            size: 30,
                          ),
                        )
                      else
                        AnimatedOpacity(
                          opacity: device.isReady ? 1 : 0.3,
                          duration: const Duration(milliseconds: 160),
                          child: Icon(
                            Icons.play_circle_fill,
                            color: theme.colorScheme.primary,
                            size: 30,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
        ],
      ),
    );
  }
}
