import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// How a node was reached, or why it was not.
enum ProbeOutcome { reached, timeout, refused, failed }

enum ProbeMethod { tcp, connect }

extension ProbeMethodLabel on ProbeMethod {
  String get label => switch (this) {
    ProbeMethod.tcp => 'TCP',
    ProbeMethod.connect => 'CONNECT',
  };
}

class NodeProbeResult {
  const NodeProbeResult({
    required this.method,
    required this.outcome,
    this.milliseconds,
    this.detail,
  });

  final ProbeMethod method;
  final ProbeOutcome outcome;
  final int? milliseconds;
  final String? detail;

  bool get ok => outcome == ProbeOutcome.reached;
}

/// Splits a node's `host:port`, tolerating a bare host.
({String host, int port}) splitNodeAddr(String addr, {int fallback = 443}) {
  final text = addr.trim();
  if (text.isEmpty) return (host: '', port: fallback);
  final index = text.lastIndexOf(':');
  if (index <= 0) return (host: text, port: fallback);
  final port = int.tryParse(text.substring(index + 1));
  if (port == null) return (host: text, port: fallback);
  final host = text.substring(0, index);
  return (host: host.replaceAll(RegExp(r'^\[|\]$'), ''), port: port);
}

/// Probes the node's own endpoint rather than a URL it proxies, which is what
/// a user means by "is this node reachable".
class NodeProbe {
  const NodeProbe();

  static const _pingTimeout = Duration(seconds: 4);

  Future<NodeProbeResult> tcp(
    String addr, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final target = splitNodeAddr(addr);
    if (target.host.isEmpty) {
      return const NodeProbeResult(
        method: ProbeMethod.tcp,
        outcome: ProbeOutcome.failed,
        detail: 'no address',
      );
    }
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        target.host,
        target.port,
        timeout: timeout,
      );
      watch.stop();
      socket.destroy();
      return NodeProbeResult(
        method: ProbeMethod.tcp,
        outcome: ProbeOutcome.reached,
        milliseconds: watch.elapsedMilliseconds,
      );
    } on SocketException catch (error) {
      watch.stop();
      return NodeProbeResult(
        method: ProbeMethod.tcp,
        outcome: _outcomeOf(error),
        milliseconds: watch.elapsedMilliseconds,
        detail: error.osError?.message ?? error.message,
      );
    } catch (error) {
      return NodeProbeResult(
        method: ProbeMethod.tcp,
        outcome: ProbeOutcome.failed,
        detail: error.toString(),
      );
    }
  }

  Future<NodeProbeResult> connect(
    String addr, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final target = splitNodeAddr(addr);
    if (target.host.isEmpty) {
      return const NodeProbeResult(
        method: ProbeMethod.connect,
        outcome: ProbeOutcome.failed,
        detail: 'no address',
      );
    }
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        target.host,
        target.port,
        timeout: timeout,
      );
      socket.write(
        'CONNECT ${target.host}:${target.port} HTTP/1.1\r\n'
        'Host: ${target.host}:${target.port}\r\n\r\n',
      );
      await socket.flush();
      final response = await socket
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .first
          .timeout(timeout);
      watch.stop();
      socket.destroy();
      final ok = response.contains(' 200');
      return NodeProbeResult(
        method: ProbeMethod.connect,
        outcome: ok ? ProbeOutcome.reached : ProbeOutcome.failed,
        milliseconds: watch.elapsedMilliseconds,
        detail: ok ? null : _firstLine(response),
      );
    } on SocketException catch (error) {
      watch.stop();
      return NodeProbeResult(
        method: ProbeMethod.connect,
        outcome: _outcomeOf(error),
        milliseconds: watch.elapsedMilliseconds,
        detail: error.osError?.message ?? error.message,
      );
    } catch (error) {
      watch.stop();
      return NodeProbeResult(
        method: ProbeMethod.connect,
        outcome: ProbeOutcome.failed,
        detail: error.toString(),
      );
    }
  }

  ProbeOutcome _outcomeOf(SocketException error) {
    final code = error.osError?.errorCode;
    if (code == 111 || code == 61 || code == 10061) {
      return ProbeOutcome.refused;
    }
    if (code == 110 || code == 60 || code == 10060) {
      return ProbeOutcome.timeout;
    }
    final message = (error.osError?.message ?? error.message).toLowerCase();
    if (message.contains('refused')) return ProbeOutcome.refused;
    if (message.contains('timed out') || message.contains('timeout')) {
      return ProbeOutcome.timeout;
    }
    return ProbeOutcome.failed;
  }

  String? _firstLine(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}
