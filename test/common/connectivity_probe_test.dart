import 'package:fl_clash/common/connectivity_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitNodeAddr', () {
    test('a host and port are split apart', () {
      final target = splitNodeAddr('1.2.3.4:8443');
      expect(target.host, '1.2.3.4');
      expect(target.port, 8443);
    });

    test('a bare host keeps the fallback port', () {
      final target = splitNodeAddr('node.example.com');
      expect(target.host, 'node.example.com');
      expect(target.port, 443);
    });

    test('a hostname with a port splits on the last colon', () {
      final target = splitNodeAddr('node.example.com:2053');
      expect(target.host, 'node.example.com');
      expect(target.port, 2053);
    });

    test('an ipv6 literal keeps its inner colons', () {
      final target = splitNodeAddr('[2001:db8::1]:443');
      expect(target.host, '2001:db8::1');
      expect(target.port, 443);
    });

    test('a non numeric tail is treated as part of the host', () {
      final target = splitNodeAddr('node:abc', fallback: 80);
      expect(target.host, 'node:abc');
      expect(target.port, 80);
    });

    test('an empty address stays empty', () {
      final target = splitNodeAddr('  ');
      expect(target.host, isEmpty);
    });
  });

  group('ProbeMethod', () {
    test('every method has a label', () {
      for (final method in ProbeMethod.values) {
        expect(method.label, isNotEmpty);
      }
    });
  });

  group('NodeProbeResult', () {
    test('only a reached probe counts as ok', () {
      for (final outcome in ProbeOutcome.values) {
        final result = NodeProbeResult(
          method: ProbeMethod.tcp,
          outcome: outcome,
        );
        expect(result.ok, outcome == ProbeOutcome.reached);
      }
    });
  });

  group('NodeProbe', () {
    test('an empty address fails without touching the network', () async {
      final result = await const NodeProbe().tcp('');
      expect(result.outcome, ProbeOutcome.failed);
      expect(result.detail, 'no address');
    });

    test('a closed local port does not report reached', () async {
      final result = await const NodeProbe().tcp(
        '127.0.0.1:1',
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
