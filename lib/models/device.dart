/// Represents a single Android device reported by `adb devices -l`.
class Device {
  final String serial;

  /// Connection state: `device`, `unauthorized`, `offline`, etc.
  final String state;

  /// Human-friendly model name (e.g. "Pixel_7"), parsed from `model:` field.
  final String? model;

  /// Marketing/product name parsed from `product:` field.
  final String? product;

  /// True when connected over TCP/IP (serial contains a `:` port).
  final bool isWireless;

  const Device({
    required this.serial,
    required this.state,
    this.model,
    this.product,
    this.isWireless = false,
  });

  bool get isReady => state == 'device';
  bool get isUnauthorized => state == 'unauthorized';
  bool get isOffline => state == 'offline';

  /// Best available display name.
  String get displayName {
    if (model != null && model!.isNotEmpty) {
      return model!.replaceAll('_', ' ');
    }
    if (product != null && product!.isNotEmpty) {
      return product!.replaceAll('_', ' ');
    }
    return serial;
  }

  String get statusLabel {
    switch (state) {
      case 'device':
        return 'Ready';
      case 'unauthorized':
        return 'Unauthorized';
      case 'offline':
        return 'Offline';
      case 'no permissions':
        return 'No permissions';
      default:
        return state;
    }
  }

  /// Parses one line of `adb devices -l` output.
  /// Example: `1234ABCD  device product:sunfish model:Pixel_4a device:sunfish`
  static Device? parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('List of devices')) return null;
    if (trimmed.startsWith('*')) return null; // adb daemon messages

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) return null;

    final serial = parts[0];
    final state = parts[1];

    String? model;
    String? product;
    for (final part in parts.skip(2)) {
      if (part.startsWith('model:')) {
        model = part.substring('model:'.length);
      } else if (part.startsWith('product:')) {
        product = part.substring('product:'.length);
      }
    }

    return Device(
      serial: serial,
      state: state,
      model: model,
      product: product,
      isWireless: serial.contains(':'),
    );
  }
}
