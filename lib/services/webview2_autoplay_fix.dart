import 'dart:ffi' hide Size;
import 'package:ffi/ffi.dart';

/// Calls the Win32 API SetEnvironmentVariableW directly via FFI — Dart's
/// own Platform.environment is READ-ONLY, there's no pure-Dart way to set
/// a process environment variable, and this specific one
/// (WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS) is exactly what WebView2 reads
/// to configure its underlying Chromium instance — specifically to skip
/// the "no audio autoplay without a real user click" restriction that
/// otherwise makes a headless/invisible YouTube player stay silent.
///
/// TIMING IS CRITICAL: this must run BEFORE WebView2's shared browser
/// environment is created for the FIRST time in this process — once that
/// environment exists, its launch arguments are locked in and changing
/// this variable later has no effect. That's why this is called as the
/// VERY FIRST thing in main(), before WidgetsFlutterBinding.ensureInitialized()
/// even — an earlier version called this from inside RoomChatScreen's
/// initState instead, which may have been too late if webview_windows
/// (or any plugin using WebView2) had already initialized something
/// earlier in this same process's lifetime.
///
/// NOT independently verified end-to-end here (no real Windows/WebView2
/// runtime in the sandbox this was written in) — the approach matches
/// Microsoft's documented WebView2 autoplay workaround, but if audio is
/// STILL silent after this change, the remaining candidates are: (a)
/// WebView2 Runtime version too old to respect this flag, or (b) a
/// stricter policy enforced by Group Policy / MDM on the machine, neither
/// of which this app can work around from the client side alone.
void allowWebView2AutoplayWithSound() {
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setEnvironmentVariable = kernel32.lookupFunction<
        Int32 Function(Pointer<Utf16> name, Pointer<Utf16> value),
        int Function(Pointer<Utf16> name, Pointer<Utf16> value)>('SetEnvironmentVariableW');

    final namePtr = 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS'.toNativeUtf16();
    final valuePtr = '--autoplay-policy=no-user-gesture-required'.toNativeUtf16();
    setEnvironmentVariable(namePtr, valuePtr);
    calloc.free(namePtr);
    calloc.free(valuePtr);
  } catch (e) {
    // ignore: avoid_print
    print('[allowWebView2AutoplayWithSound] Failed to set environment variable: $e');
  }
}
