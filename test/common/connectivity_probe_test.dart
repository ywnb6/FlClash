import 'package:fl_clash/common/connectivity_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseProbeTarget', () {
    test('a bare host takes the method default port', () {
      final target = parseProbeTarget('example.com', ProbeMethod.tcp);
      expect(target.host, 'example.com');
      expect(target.port, 443);
    });

    test('an explicit port wins over the default', () {
      final target = parseProbeTarget('example.com:8443', ProbeMethod.tcp);
      expect(target.host, 'example.com');
      expect(target.port, 8443);
    });

    test('a full url contributes host and port', () {
      final target = parseProbeTarget(
        'https://example.com:2053/path',
        ProbeMethod.tcp,
      );
      expect(target.host, 'example.com');
      expect(target.port, 2053);
    });

    test('surrounding spaces are dropped', () {
      final target = parseProbeTarget('  example.com  ', ProbeMethod.tcp);
      expect(target.host, 'example.com');
    });

    test('an empty input stays empty', () {
      final target = parseProbeTarget('', ProbeMethod.tcp);
      expect(target.host, isEmpty);
    });

    test('icmp keeps the address and carries no port', () {
      final target = parseProbeTarget('1.1.1.1', ProbeMethod.icmp);
      expect(target.host, '1.1.1.1');
      expect(target.port, 0);
    });
  });

  group('ProbeMethod', () {
    test('every method has a label', () {
      for (final method in ProbeMethod.values) {
        expect(method.label, isNotEmpty);
      }
    });

    test('only icmp omits the port', () {
      expect(ProbeMethod.tcp.usesPort, isTrue);
      expect(ProbeMethod.connect.usesPort, isTrue);
      expect(ProbeMethod.icmp.usesPort, isFalse);
    });
  });

  group('ProbeResult', () {
    test('reached and slow both count as ok', () {
      const reached = ProbeResult(
        method: ProbeMethod.tcp,
        target: 'a:1',
        outcome: ProbeOutcome.reached,
        milliseconds: 12,
      );
      const slow = ProbeResult(
        method: ProbeMethod.tcp,
        target: 'a:1',
        outcome: ProbeOutcome.slow,
        milliseconds: 900,
      );
      expect(reached.ok, isTrue);
      expect(slow.ok, isTrue);
    });

    test('a timeout or a refusal is not ok', () {
      for (final outcome in [
        ProbeOutcome.timeout,
        ProbeOutcome.refused,
        ProbeOutcome.failed,
      ]) {
        final result = ProbeResult(
          method: ProbeMethod.tcp,
          target: 'a:1',
          outcome: outcome,
        );
        expect(result.ok, isFalse);
      }
    });
  });

  group('ConnectivityProbe', () {
    test('an empty target fails without touching the network', () async {
      final result = await const ConnectivityProbe().run(
        method: ProbeMethod.tcp,
        input: '   ',
      );
      expect(result.outcome, ProbeOutcome.failed);
      expect(result.detail, 'empty');
    });

    test('tcp against a closed local port does not report ok', () async {
      final result = await const ConnectivityProbe().run(
        method: ProbeMethod.tcp,
        input: '127.0.0.1:1',
        timeout: const Duration(seconds: 1),
      );
      expect(result.ok, isFalse);
      expect(
        result.outcome,
        anyOf(ProbeOutcome.refused, ProbeOutcome.timeout, ProbeOutcome.failed),
      );
    });
  });
}
