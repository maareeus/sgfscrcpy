import 'package:flutter_test/flutter_test.dart';

import 'package:sgf_scrcpy/models/device.dart';

void main() {
  group('Device.parseLine', () {
    test('parses a ready device with model and product', () {
      final device = Device.parseLine(
        '1234ABCD  device product:sunfish model:Pixel_4a device:sunfish',
      );
      expect(device, isNotNull);
      expect(device!.serial, '1234ABCD');
      expect(device.isReady, isTrue);
      expect(device.model, 'Pixel_4a');
      expect(device.displayName, 'Pixel 4a');
      expect(device.isWireless, isFalse);
    });

    test('detects wireless devices by port in serial', () {
      final device = Device.parseLine('192.168.1.42:5555  device');
      expect(device!.isWireless, isTrue);
    });

    test('flags unauthorized devices', () {
      final device = Device.parseLine('9999XYZ  unauthorized');
      expect(device!.isReady, isFalse);
      expect(device.isUnauthorized, isTrue);
    });

    test('ignores the header line', () {
      expect(Device.parseLine('List of devices attached'), isNull);
    });

    test('ignores blank lines', () {
      expect(Device.parseLine('   '), isNull);
    });
  });
}
