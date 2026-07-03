# In-app viewer (Approach A)

Goal: render the device screen **inside** SgfScrcpy instead of the standalone
scrcpy window, so we own the UI, the window title and the icon.

This means becoming a scrcpy client: run `scrcpy-server` on the device and
handle its stream ourselves.

## Phases

### Phase 1 — Connection & demux ✅ (this branch)
- Locate `scrcpy-server` (next to scrcpy), push to the device.
- Reverse adb tunnel (`localabstract:scrcpy_<scid>` → local TCP).
- Start the server via `app_process` with `video=true audio=false control=true`.
- Accept the video + control sockets.
- Parse the handshake: dummy byte, 64-byte device name, codec metadata
  (`fourcc` + width + height), then the packet loop (12-byte header:
  `pts` u64 with config/keyframe flags + `len` u32, followed by payload).
- Diagnostic screen: live codec/resolution/FPS/bitrate/packet counters.

Implemented in `lib/services/scrcpy_server_client.dart` and
`lib/screens/viewer_screen.dart`.

> Status: needs validation against a real device. The server protocol is
> version-specific (targeting scrcpy 3.x).

### Phase 2 — Decode & render (the hard part)
Decode the H.264/H.265 packets and paint them into a Flutter `Texture`.
No pure-Dart decoder exists, so this needs native decoders per platform via a
platform channel + external textures:
- Windows: Media Foundation / D3D11
- macOS: VideoToolbox
- Linux: FFmpeg (libavcodec) or VA-API

Feed config packets (SPS/PPS) first, then frames; map decoder output to a
texture id rendered by `Texture(textureId: ...)`.

### Phase 3 — Input & control
Send touch/key/scroll/clipboard events on the control socket (scrcpy binary
control message format), mapping Flutter pointer/keyboard events. Enables the
custom window to actually drive the device.

### Phase 4 — Polish
Custom per-app icon/title, resize handling, audio (optional), recording,
multiple simultaneous viewers.

## Notes
- Keep the standalone scrcpy launch path as the default; the in-app viewer is
  opt-in (beta checkbox) until Phase 2/3 land.
- References: QtScrcpy, ws-scrcpy, and the scrcpy server protocol docs.
