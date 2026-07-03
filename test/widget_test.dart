import 'package:flutter_test/flutter_test.dart';

import 'package:sgf_scrcpy/models/device.dart';
import 'package:sgf_scrcpy/models/mirror_options.dart';

void main() {
  group('MirrorOptions.toArgs', () {
    test('defaults only pass the serial', () {
      expect(MirrorOptions.defaults.toArgs('ABC'), ['--serial', 'ABC']);
    });

    test('maps video and behavior options to flags', () {
      const o = MirrorOptions(
        maxSize: 1024,
        videoBitrateMbps: 8,
        maxFps: 60,
        fullscreen: true,
        stayAwake: true,
        audioEnabled: false,
      );
      final args = o.toArgs('ABC');
      expect(args, containsAllInOrder(['--max-size', '1024']));
      expect(args, containsAllInOrder(['--video-bit-rate', '8M']));
      expect(args, containsAllInOrder(['--max-fps', '60']));
      expect(args, contains('--fullscreen'));
      expect(args, contains('--stay-awake'));
      expect(args, contains('--no-audio'));
    });

    test('virtual display with resolution, dpi and start app', () {
      const o = MirrorOptions(
        virtualDisplay: true,
        virtualDisplayResolution: '1920x1080',
        virtualDisplayDpi: 240,
        startAppPackage: 'com.android.chrome',
      );
      final args = o.toArgs('ABC');
      expect(args, contains('--new-display=1920x1080/240'));
      expect(args, contains('--start-app=com.android.chrome'));
    });

    test('virtual display with no resolution uses bare flag', () {
      const o = MirrorOptions(virtualDisplay: true);
      expect(o.toArgs('ABC'), contains('--new-display'));
    });
  });

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
