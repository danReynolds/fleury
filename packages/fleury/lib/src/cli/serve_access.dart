import 'dart:io' show InternetAddress;
import 'dart:math' show Random;

/// Whether [host] binds `fleury serve` to this machine only.
bool isLoopbackServeHost(String host) {
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
  final parsed = InternetAddress.tryParse(host);
  return parsed != null && parsed.isLoopback;
}

/// A fresh 128-bit secret, hex-encoded, for a network bind given no
/// `--token`. The wire carries full app control, so a session reachable from
/// the network never runs without one.
String generateServeToken([Random? random]) {
  final source = random ?? Random.secure();
  final digits = StringBuffer();
  for (var i = 0; i < 16; i++) {
    digits.write(source.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return digits.toString();
}

/// The token a `fleury serve` bound to [host] requires: [token] when given,
/// otherwise a generated one for a network bind, and none on loopback.
String? resolveServeToken({
  required String host,
  String? token,
  Random? random,
}) => token ?? (isLoopbackServeHost(host) ? null : generateServeToken(random));

/// Whether [presented] equals [expected], compared in time that does not
/// depend on where the two first differ.
bool serveTokenMatches(String expected, String? presented) {
  if (presented == null || presented.length != expected.length) return false;
  var difference = 0;
  for (var i = 0; i < expected.length; i++) {
    difference |= expected.codeUnitAt(i) ^ presented.codeUnitAt(i);
  }
  return difference == 0;
}

/// The URL a browser opens to reach `fleury serve`. The served page forwards
/// its own `token` query parameter to the WebSocket, so the URL is all a user
/// needs.
String serveBrowserUrl(String host, int port, String? token) {
  final authority = host.contains(':') && !host.startsWith('[')
      ? '[$host]'
      : host;
  final base = 'http://$authority:$port';
  return token == null
      ? base
      : '$base/?token=${Uri.encodeQueryComponent(token)}';
}
