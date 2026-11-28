import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum ProbeOutcome {
  reached,
  slow,
  timeout,
  refused,
  failed,
}

class ProbeResult {
  const ProbeResult({
    required this.method,
    required this.target,
    required this.outcome,
    this.milliseconds,
    this.detail,
  });

  final ProbeMethod method;
  final String target;
  final ProbeOutcome outcome;
  final int? milliseconds;
  final String? detail;

  bool get ok => outcome == ProbeOutcome.reached || outcome == ProbeOutcome.slow;
}

enum ProbeMethod {
  tcp,
  icmp,
  connect,
}

extension ProbeMethodLabel on ProbeMethod {
  String get label => switch (this) {
    ProbeMethod.tcp => 'TCP',
    ProbeMethod.icmp => 'ICMP',
    ProbeMethod.connect => 'CONNECT',
  };

  int get defaultPort => switch (this) {
    ProbeMethod.tcp => 443,
    ProbeMethod.icmp => 0,
    ProbeMethod.connect => 443,
  };

  bool get usesPort => this != ProbeMethod.icmp;
}

({String host, int port}) parseProbeTarget(String input, ProbeMethod method) {
  var text = input.trim();
  if (text.isEmpty) return (host: '', port: method.defaultPort);
  final uri = Uri.tryParse(
    text.contains('://') ? text : 'http://$text',
  );
  final host = uri?.host ?? text;
  final port = uri?.hasPort == true ? uri!.port : method.defaultPort;
  return (host: host, port: port);
}

/// ICMP runs through the system ping: a Dart socket cannot send an echo
/// request without root.
class ConnectivityProbe {
  const ConnectivityProbe();

  static const _pingTimeout = Duration(seconds: 4);

  Future<ProbeResult> run({
    required ProbeMethod method,
    required String input,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final target = parseProbeTarget(input, method);
    if (target.host.isEmpty) {
      return ProbeResult(
        method: method,
        target: input,
        outcome: ProbeOutcome.failed,
        detail: 'empty',
      );
    }
    return switch (method) {
      ProbeMethod.tcp => _tcp(target.host, target.port, timeout),
      ProbeMethod.icmp => _icmp(target.host),
      ProbeMethod.connect => _connect(target.host, target.port, timeout),
    };
  }

  Future<ProbeResult> _tcp(String host, int port, Duration timeout) async {
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      watch.stop();
      socket.destroy();
      return ProbeResult(
        method: ProbeMethod.tcp,
        target: '$host:$port',
        outcome: ProbeOutcome.reached,
        milliseconds: watch.elapsedMilliseconds,
      );
    } on SocketException catch (error) {
      watch.stop();
      return ProbeResult(
        method: ProbeMethod.tcp,
        target: '$host:$port',
        outcome: _outcomeOf(error),
        milliseconds: watch.elapsedMilliseconds,
        detail: error.osError?.message ?? error.message,
      );
    } catch (error) {
      watch.stop();
      return ProbeResult(
        method: ProbeMethod.tcp,
        target: '$host:$port',
        outcome: ProbeOutcome.failed,
        detail: error.toString(),
      );
    }
  }

  Future<ProbeResult> _icmp(String host) async {
    final watch = Stopwatch()..start();
    try {
      final result = await Process.run(
        'ping',
        ['-c', '1', '-W', '3', host],
      ).timeout(_pingTimeout);
      watch.stop();
      final output = '${result.stdout}${result.stderr}';
      final match = RegExp(r'time[=<]\s*([\d.]+)\s*ms').firstMatch(output);
      final elapsed = match == null
          ? watch.elapsedMilliseconds
          : (double.tryParse(match.group(1)!) ?? 0).round();
      if (result.exitCode == 0) {
        return ProbeResult(
          method: ProbeMethod.icmp,
          target: host,
          outcome: ProbeOutcome.reached,
          milliseconds: elapsed,
        );
      }
      return ProbeResult(
        method: ProbeMethod.icmp,
        target: host,
        outcome: ProbeOutcome.timeout,
        detail: _firstLine(output),
      );
    } on TimeoutException {
      return ProbeResult(
        method: ProbeMethod.icmp,
        target: host,
        outcome: ProbeOutcome.timeout,
      );
    } catch (error) {
      return ProbeResult(
        method: ProbeMethod.icmp,
        target: host,
        outcome: ProbeOutcome.failed,
        detail: 'ping unavailable',
      );
    }
  }

  Future<ProbeResult> _connect(String host, int port, Duration timeout) async {
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.write(
        'CONNECT $host:$port HTTP/1.1\r\nHost: $host:$port\r\n\r\n',
      );
      await socket.flush();
      final response = await socket
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .first
          .timeout(timeout);
      watch.stop();
      socket.destroy();
      final reached = response.contains(' 200');
      return ProbeResult(
        method: ProbeMethod.connect,
        target: '$host:$port',
        outcome: reached ? ProbeOutcome.reached : ProbeOutcome.failed,
        milliseconds: watch.elapsedMilliseconds,
        detail: reached ? null : _firstLine(response),
      );
    } on SocketException catch (error) {
      watch.stop();
      return ProbeResult(
        method: ProbeMethod.connect,
        target: '$host:$port',
        outcome: _outcomeOf(error),
        milliseconds: watch.elapsedMilliseconds,
        detail: error.osError?.message ?? error.message,
      );
    } catch (error) {
      watch.stop();
      return ProbeResult(
        method: ProbeMethod.connect,
        target: '$host:$port',
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
