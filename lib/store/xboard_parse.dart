/// Parsers that read an Xboard payload whose fields may arrive as a number, a
/// numeric string or a bool, so one unexpected value never fails a whole call.
library;

int? asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is bool) return value ? 1 : 0;
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
    final asDouble = double.tryParse(value.trim());
    return asDouble?.toInt();
  }
  return null;
}

int asIntOr(Object? value, int fallback) => asInt(value) ?? fallback;

String asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return fallback;
}

String? asStringOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  if (value is num || value is bool) return '$value';
  return null;
}

bool asBool(Object? value, {bool fallback = true}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0' || normalized.isEmpty) {
      return false;
    }
  }
  return fallback;
}

Map<String, Object?> asMap(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}
