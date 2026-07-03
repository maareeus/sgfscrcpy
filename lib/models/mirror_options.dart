/// User-configurable scrcpy launch options for a single mirror session.
class MirrorOptions {
  // Video
  final int? maxSize; // px, longest edge (--max-size)
  final int? videoBitrateMbps; // Mbps (--video-bit-rate)
  final int? maxFps; // (--max-fps)

  // Window / behavior
  final bool fullscreen;
  final bool stayAwake;
  final bool turnScreenOff;
  final bool showTouches;

  /// scrcpy keyboard mode: null (default/sdk), 'uhid', 'aoa', 'disabled'.
  /// 'uhid' is required for reliable typing on a virtual display.
  final String? keyboardMode;

  // Audio (scrcpy forwards audio by default on Android 11+)
  final bool audioEnabled;

  // Recording
  final String? recordPath; // when set, --record <path>

  // Virtual display (--new-display, scrcpy 3.0+, Android 11+)
  final bool virtualDisplay;
  final String? virtualDisplayResolution; // e.g. "1920x1080"
  final int? virtualDisplayDpi;
  final String? startAppPackage; // --start-app=<pkg>, launches app on the display

  const MirrorOptions({
    this.maxSize,
    this.videoBitrateMbps,
    this.maxFps,
    this.fullscreen = false,
    this.stayAwake = false,
    this.turnScreenOff = false,
    this.showTouches = false,
    this.keyboardMode,
    this.audioEnabled = true,
    this.recordPath,
    this.virtualDisplay = false,
    this.virtualDisplayResolution,
    this.virtualDisplayDpi,
    this.startAppPackage,
  });

  static const MirrorOptions defaults = MirrorOptions();

  MirrorOptions copyWith({
    int? maxSize,
    bool clearMaxSize = false,
    int? videoBitrateMbps,
    bool clearBitrate = false,
    int? maxFps,
    bool clearMaxFps = false,
    bool? fullscreen,
    bool? stayAwake,
    bool? turnScreenOff,
    bool? showTouches,
    String? keyboardMode,
    bool clearKeyboardMode = false,
    bool? audioEnabled,
    String? recordPath,
    bool clearRecordPath = false,
    bool? virtualDisplay,
    String? virtualDisplayResolution,
    bool clearResolution = false,
    int? virtualDisplayDpi,
    bool clearDpi = false,
    String? startAppPackage,
    bool clearStartApp = false,
  }) {
    return MirrorOptions(
      maxSize: clearMaxSize ? null : (maxSize ?? this.maxSize),
      videoBitrateMbps:
          clearBitrate ? null : (videoBitrateMbps ?? this.videoBitrateMbps),
      maxFps: clearMaxFps ? null : (maxFps ?? this.maxFps),
      fullscreen: fullscreen ?? this.fullscreen,
      stayAwake: stayAwake ?? this.stayAwake,
      turnScreenOff: turnScreenOff ?? this.turnScreenOff,
      showTouches: showTouches ?? this.showTouches,
      keyboardMode:
          clearKeyboardMode ? null : (keyboardMode ?? this.keyboardMode),
      audioEnabled: audioEnabled ?? this.audioEnabled,
      recordPath: clearRecordPath ? null : (recordPath ?? this.recordPath),
      virtualDisplay: virtualDisplay ?? this.virtualDisplay,
      virtualDisplayResolution: clearResolution
          ? null
          : (virtualDisplayResolution ?? this.virtualDisplayResolution),
      virtualDisplayDpi: clearDpi ? null : (virtualDisplayDpi ?? this.virtualDisplayDpi),
      startAppPackage:
          clearStartApp ? null : (startAppPackage ?? this.startAppPackage),
    );
  }

  /// Builds the scrcpy argument list for [serial] from these options.
  List<String> toArgs(String serial) {
    final args = <String>['--serial', serial];

    if (maxSize != null) args.addAll(['--max-size', '$maxSize']);
    if (videoBitrateMbps != null) {
      args.addAll(['--video-bit-rate', '${videoBitrateMbps}M']);
    }
    if (maxFps != null) args.addAll(['--max-fps', '$maxFps']);

    if (fullscreen) args.add('--fullscreen');
    if (stayAwake) args.add('--stay-awake');
    if (turnScreenOff) args.add('--turn-screen-off');
    if (showTouches) args.add('--show-touches');
    if (keyboardMode != null && keyboardMode!.isNotEmpty) {
      args.add('--keyboard=$keyboardMode');
    }
    if (!audioEnabled) args.add('--no-audio');

    if (recordPath != null && recordPath!.isNotEmpty) {
      args.addAll(['--record', recordPath!]);
    }

    if (virtualDisplay) {
      final res = virtualDisplayResolution?.trim() ?? '';
      final dpi = virtualDisplayDpi;
      final value = StringBuffer(res);
      if (dpi != null) value.write('/$dpi');
      final v = value.toString();
      args.add(v.isEmpty ? '--new-display' : '--new-display=$v');
      if (startAppPackage != null && startAppPackage!.trim().isNotEmpty) {
        final pkg = startAppPackage!.trim();
        args.add('--start-app=$pkg');
        // scrcpy can't show the app's icon, but we can at least title the
        // window/taskbar entry with the package name.
        args.addAll(['--window-title', pkg]);
      }
    }

    return args;
  }
}
