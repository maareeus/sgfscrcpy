// Windows-only process helpers using Win32 FFI.
//
// Dart's `Process.start(..., mode: detached)` spawns a visible console window
// on Windows for console-subsystem executables (like scrcpy.exe). We call
// CreateProcessW directly with CREATE_NO_WINDOW to launch it silently, and
// query liveness with OpenProcess/GetExitCodeProcess.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const int _createNoWindow = 0x08000000;
const int _stillActive = 259;
const int _processQueryLimitedInformation = 0x1000;

/// Launches [executable] with [args] with no console window.
/// Returns the new process id, or 0 on failure.
int launchNoWindow(String executable, List<String> args) {
  // Build a properly quoted command line.
  final buffer = StringBuffer('"$executable"');
  for (final arg in args) {
    buffer.write(' "$arg"');
  }
  final commandLine = buffer.toString().toNativeUtf16();
  final startupInfo = calloc<STARTUPINFO>();
  startupInfo.ref.cb = sizeOf<STARTUPINFO>();
  final processInfo = calloc<PROCESS_INFORMATION>();

  try {
    final ok = CreateProcess(
      nullptr, // lpApplicationName
      commandLine, // lpCommandLine (mutable)
      nullptr, // lpProcessAttributes
      nullptr, // lpThreadAttributes
      FALSE, // bInheritHandles
      _createNoWindow, // dwCreationFlags
      nullptr, // lpEnvironment
      nullptr, // lpCurrentDirectory
      startupInfo,
      processInfo,
    );
    if (ok == 0) return 0;

    final pid = processInfo.ref.dwProcessId;
    // We don't need the handles; scrcpy runs independently.
    CloseHandle(processInfo.ref.hProcess);
    CloseHandle(processInfo.ref.hThread);
    return pid;
  } finally {
    malloc.free(commandLine);
    calloc.free(startupInfo);
    calloc.free(processInfo);
  }
}

/// Returns true if a process with [pid] is currently running.
bool isProcessRunning(int pid) {
  final handle = OpenProcess(_processQueryLimitedInformation, FALSE, pid);
  if (handle == 0) return false;
  final exitCode = calloc<Uint32>();
  try {
    final ok = GetExitCodeProcess(handle, exitCode);
    if (ok == 0) return false;
    return exitCode.value == _stillActive;
  } finally {
    CloseHandle(handle);
    calloc.free(exitCode);
  }
}

/// Terminates a process by pid. Safe to call on a dead pid.
void terminateProcess(int pid) {
  final handle = OpenProcess(0x0001 /* PROCESS_TERMINATE */, FALSE, pid);
  if (handle == 0) return;
  try {
    TerminateProcess(handle, 0);
  } finally {
    CloseHandle(handle);
  }
}
