/// A persistent `adb reverse` mapping for a device.
///
/// `adb reverse tcp:<devicePort> tcp:<pcPort>`: a socket the device opens on
/// `127.0.0.1:<devicePort>` is tunnelled to `127.0.0.1:<pcPort>` on the PC.
class ReverseRule {
  final int devicePort;
  final int pcPort;

  const ReverseRule(this.devicePort, this.pcPort);

  Map<String, dynamic> toJson() => {'device': devicePort, 'pc': pcPort};

  factory ReverseRule.fromJson(Map<String, dynamic> json) =>
      ReverseRule(json['device'] as int, json['pc'] as int);

  @override
  bool operator ==(Object other) =>
      other is ReverseRule &&
      other.devicePort == devicePort &&
      other.pcPort == pcPort;

  @override
  int get hashCode => Object.hash(devicePort, pcPort);
}
