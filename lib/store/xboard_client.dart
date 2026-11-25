import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/store/xboard_models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/store/xboard_parse.dart';

class XboardException implements Exception {
  const XboardException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class XboardClient {
  XboardClient({String baseUrl = defaultBaseUrl}) : _baseUrl = _normalize(baseUrl);

  static const defaultBaseUrl = 'https://plan.zzyo.top';

  /// Shown wherever the app would otherwise print the address; the panel's own
  /// page title overrides it once fetched.
  static const defaultSiteName = '易挽机场';

  /// What the panel sees as the client; it decides the config format a
  /// subscription is served in.
  static String get defaultUserAgent => 'FlClash/${globalState.packageInfo.version}';

  static String _normalize(String value) {
    var url = value.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  final String _baseUrl;

  String get baseUrl => _baseUrl;

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: '$_baseUrl/api/v1',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      headers: {'Accept': 'application/json'},
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ),
  );

  String? _token;
  String? _userAgentOverride;

  String get _userAgent => _userAgentOverride ?? defaultUserAgent;

  String? get token => _token;

  set token(String? value) => _token = value;

  set userAgent(String value) =>
      _userAgentOverride = value.trim().isEmpty ? null : value.trim();

  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? data,
    bool auth = true,
  }) async {
    final Map<String, Object?> headers = {'User-Agent': _userAgent};
    final current = _token;
    if (auth && current != null && current.isNotEmpty) {
      headers['Authorization'] = current;
    }
    Response<String> response;
    try {
      response = await _dio.request<String>(
        path,
        data: data,
        options: Options(method: method, headers: headers),
      );
    } on DioException catch (error) {
      throw XboardException(_describeNetworkError(error));
    } on SocketException catch (error) {
      throw XboardException(error.message);
    }
    final body = response.data ?? '';
    final status = response.statusCode ?? 0;
    dynamic decoded;
    try {
      decoded = body.isEmpty ? null : jsonDecode(body);
    } catch (_) {
      decoded = null;
    }
    if (decoded is! Map) {
      throw XboardException(
        status == 0 ? 'Empty response' : 'HTTP $status',
        statusCode: status,
      );
    }
    if (decoded['status'] == 'success') {
      return decoded['data'];
    }
    final message = decoded['message'];
    // The payment endpoint answers with `{type, data}` and no status field.
    if (message == null && decoded.containsKey('type')) {
      return decoded;
    }
    throw XboardException(
      message is String && message.isNotEmpty ? message : 'HTTP $status',
      statusCode: status,
    );
  }

  String _describeNetworkError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.transformTimeout:
        return 'Connection timeout';
      case DioExceptionType.badCertificate:
        return 'Bad certificate';
      case DioExceptionType.connectionError:
        return 'Cannot reach $_baseUrl';
      case DioExceptionType.cancel:
        return 'Request cancelled';
      case DioExceptionType.badResponse:
        return 'HTTP ${error.response?.statusCode}';
      case DioExceptionType.unknown:
        return error.message ?? 'Network error';
    }
  }

  /// The panel publishes its name only in the page it serves, so the site
  /// root is read once and both the title tag and the `settings` object are
  /// tried; the name is cached for the session by the caller.
  Future<String> fetchSiteName() async {
    for (final path in const ['/', '/index.html']) {
      try {
        final response = await Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 12),
            validateStatus: (_) => true,
            responseType: ResponseType.plain,
          ),
        ).get<String>(
          '$_baseUrl$path',
          options: Options(headers: {'User-Agent': _userAgent}),
        );
        final body = response.data ?? '';
        if (body.isEmpty) continue;
        final settings = RegExp(
          r'title:\s*[\x27"]([^\x27"]+)[\x27"]',
        ).firstMatch(body);
        final tag = RegExp(
          r'<title[^>]*>([^<]+)</title>',
          caseSensitive: false,
        ).firstMatch(body);
        final name = (settings?.group(1) ?? tag?.group(1) ?? '').trim();
        if (name.isNotEmpty) return name;
      } catch (_) {}
    }
    return '';
  }

  Future<XboardSiteConfig> fetchSiteConfig() async {
    final data = await _request('/guest/comm/config', auth: false);
    return XboardSiteConfig.fromJson(asMap(data));
  }

  Future<List<XboardPlan>> fetchPlans() async {
    final data = await _request('/guest/plan/fetch', auth: false);
    if (data is! List) return [];
    final plans = data
        .whereType<Map>()
        .map((item) => XboardPlan.fromJson(item.cast<String, Object?>()))
        .where((plan) => plan.sell && plan.id > 0)
        .toList();
    plans.sort((a, b) => a.sort.compareTo(b.sort));
    return plans;
  }

  Future<String> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    final data = await _request(
      '/passport/auth/login',
      method: 'POST',
      data: {
        'email': email.trim(),
        'password': password,
        if (captchaToken != null && captchaToken.isNotEmpty)
          'cf-turnstile-response': captchaToken,
      },
      auth: false,
    );
    final token = _readAuthData(data);
    _token = token;
    return token;
  }

  String _readAuthData(Object? data) {
    final authData = data is Map ? data['auth_data'] : null;
    final token = asStringOrNull(authData);
    if (token == null || token.isEmpty) {
      throw const XboardException('No auth data returned');
    }
    return token;
  }

  Future<String> register({
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
    String? captchaToken,
  }) async {
    final data = await _request(
      '/passport/auth/register',
      method: 'POST',
      data: {
        'email': email.trim(),
        'password': password,
        if (inviteCode != null && inviteCode.isNotEmpty)
          'invite_code': inviteCode.trim(),
        if (emailCode != null && emailCode.isNotEmpty)
          'email_code': emailCode.trim(),
        if (captchaToken != null && captchaToken.isNotEmpty)
          'cf-turnstile-response': captchaToken,
      },
      auth: false,
    );
    final token = _readAuthData(data);
    _token = token;
    return token;
  }

  Future<void> sendEmailVerify({required String email}) async {
    await _request(
      '/passport/comm/sendEmailVerify',
      method: 'POST',
      data: {'email': email.trim()},
      auth: false,
    );
  }

  Future<void> forget({required String email}) async {
    await _request(
      '/passport/auth/forget',
      method: 'POST',
      data: {'email': email.trim()},
      auth: false,
    );
  }

  /// The subscription endpoint carries the traffic figures, the plan and the
  /// signed share link; `user/info` only adds the balance, so both feed one
  /// record and a failure of either still yields an account to show.
  Future<XboardUserInfo> fetchUserInfo() async {
    final info = await _readMap('/user/info');
    final subscribe = await _readMap('/user/getSubscribe');
    if (info.isEmpty && subscribe.isEmpty) {
      throw const XboardException('Malformed user info');
    }
    return XboardUserInfo.fromJson({...info, ...subscribe});
  }

  Future<Map<String, Object?>> _readMap(String path) async {
    try {
      final data = await _request(path);
      return asMap(data);
    } catch (_) {
      return const {};
    }
  }

  Future<int?> fetchBalance() async {
    try {
      final data = await _request('/user/stat/getTrafficLog');
      return data is Map ? asInt(data['balance']) : null;
    } catch (_) {
      return null;
    }
  }

  /// Builds the share link for the signed-in account; [subPath] is the
  /// panel's `subscribe_url` value and already carries the token.
  String subscribeLink(XboardUserInfo info) => info.subscribeUrl;

  Future<List<XboardPaymentMethod>> fetchPaymentMethods() async {
    final data = await _request('/user/order/getPaymentMethod');
    if (data is! List) return [];
    return [
      for (final item in data.whereType<Map>())
        XboardPaymentMethod(
          id: asIntOr(item['id'], 0),
          name: asString(item['name'], asString(item['payment'])),
        ),
    ];
  }

  /// The panel answers with the trade number itself rather than an object,
  /// and `checkout` takes the payment method's numeric id, not its name.
  Future<XboardOrder> createOrder({
    required int planId,
    required String period,
    String? couponCode,
    int? paymentId,
    String? url,
  }) async {
    final data = await _request(
      '/user/order/save',
      method: 'POST',
      data: {
        'plan_id': planId,
        'period': period,
        if (url != null && url.isNotEmpty) 'url': url,
        if (paymentId != null && paymentId > 0) 'payment_id': paymentId,
        if (couponCode != null && couponCode.isNotEmpty)
          'coupon_code': couponCode.trim(),
      },
    );
    if (data is Map) {
      final order = XboardOrder.fromJson(asMap(data));
      if (order.tradeNo.isNotEmpty) return order;
      throw const XboardException('Malformed order');
    }
    final tradeNo = asStringOrNull(data);
    if (tradeNo == null || tradeNo.isEmpty) {
      throw const XboardException('Malformed order');
    }
    return XboardOrder(tradeNo: tradeNo);
  }

  /// The answer is `{type, data}`: type 1 carries a payment page to open,
  /// type 0 a bare QR payload, and a plain string is the URL itself.
  Future<XboardPayment> checkout({
    required String tradeNo,
    required String method,
  }) async {
    final data = await _request(
      '/user/order/checkout',
      method: 'POST',
      data: {'trade_no': tradeNo, 'method': method},
    );
    if (data is Map) {
      final map = asMap(data);
      final payload = asStringOrNull(map['data']) ?? asStringOrNull(map['url']);
      if (payload == null || payload.isEmpty) {
        throw const XboardException('Malformed payment');
      }
      return XboardPayment(
        isRedirect: asIntOr(map['type'], 1) == 1,
        payload: payload,
      );
    }
    final payload = asStringOrNull(data);
    if (payload == null || payload.isEmpty) {
      throw const XboardException('Malformed payment');
    }
    return XboardPayment(isRedirect: true, payload: payload);
  }

  Future<List<XboardOrderRecord>> fetchOrders() async {
    final data = await _request('/user/order/fetch');
    if (data is! List) return const [];
    return [
      for (final item in data.whereType<Map>())
        XboardOrderRecord.fromJson(asMap(item)),
    ];
  }

  Future<void> cancelOrder(String tradeNo) async {
    await _request(
      '/user/order/cancel',
      method: 'POST',
      data: {'trade_no': tradeNo},
    );
  }

  Future<int?> orderStatus({required String tradeNo}) async {
    try {
      final data = await _request('/user/order/detail', data: {'trade_no': tradeNo});
      if (data is Map) return asInt(data['status']);
    } catch (_) {}
    return null;
  }
}

final xboardClient = XboardClient();
