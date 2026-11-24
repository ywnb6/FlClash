import 'dart:io';

/// Times the TCP handshake to a node's own endpoint, the way a client outside
/// the tunnel sees it: the measurement covers reaching the server and nothing
/// that happens once traffic goes through it.
class TcpPing {
  static const timeout = Duration(seconds: 3);

  /// Milliseconds, or null when the endpoint refused or timed out.
  static Future<int?> measure(String addr) async {
    final endpoint = _parse(addr);
    if (endpoint == null) return null;
    Socket? socket;
    final watch = Stopwatch()..start();
    try {
      socket = await Socket.connect(
        endpoint.host,
        endpoint.port,
        timeout: timeout,
      );
      watch.stop();
      final millis = watch.elapsedMilliseconds;
      return millis <= 0 ? 1 : millis;
    } catch (_) {
      return null;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  static ({String host, int port})? _parse(String addr) {
    if (addr.isEmpty) return null;
    final separator = addr.lastIndexOf(':');
    if (separator <= 0) return null;
    var host = addr.substring(0, separator).trim();
    final port = int.tryParse(addr.substring(separator + 1).trim());
    if (port == null || port <= 0 || port > 65535) return null;
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (host.isEmpty) return null;
    return (host: host, port: port);
  }

  /// Whether this delay came from a dial rather than a routed request.
  static bool canMeasure(String addr) => _parse(addr) != null;
}
