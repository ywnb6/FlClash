import 'package:fl_clash/providers/action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEndpoint', () {
    test('a host and port are split', () {
      final endpoint = parseEndpoint('hk-2.zzyo.top:23111');
      expect(endpoint?.host, 'hk-2.zzyo.top');
      expect(endpoint?.port, 23111);
    });

    test('a bare host falls back to 443', () {
      final endpoint = parseEndpoint('hk-2.zzyo.top');
      expect(endpoint?.host, 'hk-2.zzyo.top');
      expect(endpoint?.port, 443);
    });

    test('an ipv4 address keeps its dots', () {
      final endpoint = parseEndpoint('101.43.78.107:18588');
      expect(endpoint?.host, '101.43.78.107');
      expect(endpoint?.port, 18588);
    });

    test('a non numeric tail is part of the host', () {
      final endpoint = parseEndpoint('node.example');
      expect(endpoint?.host, 'node.example');
      expect(endpoint?.port, 443);
    });

    test('an empty address yields nothing', () {
      expect(parseEndpoint(''), isNull);
      expect(parseEndpoint('   '), isNull);
    });
  });
}
