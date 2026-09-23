/// Central place for the backend server address.
///
/// EVERY OTHER FILE imports this instead of hardcoding "localhost:8000" —
/// that matters because "localhost" only means anything on the developer's
/// own machine. Once this app is installed on someone else's computer, it
/// needs to point at your REAL server's address instead.
///
/// Before building the installer for distribution:
///   1. Deploy the backend (the `citychat` FastAPI project) to a real
///      server with a public domain or IP — it can't stay on your laptop.
///   2. Set up HTTPS/WSS (TLS) in front of it — see citychat's README,
///      section on production security. Never ship `ws://`/`http://`
///      (unencrypted) pointed at a public server.
///   3. Change [apiBaseUrl] and [socketUrl] below to that real address.
///   4. Rebuild: flutter build windows --release
///   5. Re-package with Inno Setup (installer/windows/setup.iss)
///
/// Until you've done steps 1-3, this app only works on the same machine
/// the backend is running on — that's fine for your own testing, but
/// installing it on someone else's computer won't connect to anything.
class AppConfig {
  // TODO: replace with your real server before distributing to users, e.g.:
  //   static const String serverBaseUrl = 'https://api.batamchitchat.com';
  //   static const String socketUrl = 'wss://api.batamchitchat.com';
  static const String serverBaseUrl = 'http://localhost:8000';
  static const String socketUrl = 'ws://localhost:8000';

  static const String apiBaseUrl = '$serverBaseUrl/api';
}
