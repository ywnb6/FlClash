import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/store/xboard_client.dart';
import 'package:fl_clash/store/xboard_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the shop session: the panel address, the auth token and the account
/// the panel last reported, kept in preferences so a restart stays signed in.
class XboardSession {
  static const _baseUrlKey = 'xboard.baseUrl';
  static const _tokenKey = 'xboard.token';
  static const _userAgentKey = 'xboard.userAgent';

  final XboardClient _client = xboardClient;
  final SharedPreferences? _preferences;

  XboardSession(this._preferences);

  String _baseUrl = XboardClient.defaultBaseUrl;
  String _siteName = '';
  XboardSiteConfig _siteConfig = const XboardSiteConfig();
  String? _token;
  XboardUserInfo? _userInfo;
  List<XboardPlan> _plans = const [];
  bool _busy = false;
  String? _lastError;

  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  XboardClient get client => _client;

  String get baseUrl => _baseUrl;

  /// The panel's own name; the app never shows the address in its place.
  String get siteName =>
      _siteName.isNotEmpty ? _siteName : XboardClient.defaultSiteName;

  XboardSiteConfig get siteConfig => _siteConfig;

  String? get token => _token;

  bool get isSignedIn => _token != null && _token!.isNotEmpty;

  XboardUserInfo? get userInfo => _userInfo;

  List<XboardPlan> get plans => _plans;

  bool get busy => _busy;

  String? get lastError => _lastError;

  String get userAgent => _preferences?.getString(_userAgentKey) ?? '';

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> restore() async {
    _baseUrl = _preferences?.getString(_baseUrlKey) ?? _baseUrl;
    _token = _preferences?.getString(_tokenKey);
    _client
      ..token = _token
      ..userAgent = _preferences?.getString(_userAgentKey) ?? '';
    await loadSiteInfo();
    _notify();
  }

  /// Pulls everything the panel publishes about itself: its name, signup
  /// rules and logo, so a panel-side change shows up on the next load.
  Future<void> loadSiteInfo({bool force = false}) async {
    if (_siteName.isNotEmpty && !force) return;
    try {
      _siteConfig = await _client.fetchSiteConfig();
    } catch (_) {}
    _siteName = await _client.fetchSiteName();
    _notify();
  }

  Future<void> setBaseUrl(String value) async {
    var url = value.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    _baseUrl = url;
    _siteName = '';
    _siteConfig = const XboardSiteConfig();
    await _preferences?.setString(_baseUrlKey, url);
    _plans = const [];
    _notify();
  }

  Future<void> setUserAgent(String value) async {
    await _preferences?.setString(_userAgentKey, value.trim());
    _client.userAgent = value;
    _notify();
  }

  Future<void> _setToken(String? value) async {
    _token = value;
    _client.token = value;
    if (value == null || value.isEmpty) {
      await _preferences?.remove(_tokenKey);
    } else {
      await _preferences?.setString(_tokenKey, value);
    }
    _notify();
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    _busy = true;
    _lastError = null;
    _notify();
    try {
      return await action();
    } on XboardException catch (error) {
      _lastError = error.message;
      rethrow;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> loadPlans({bool force = false}) async {
    if (_plans.isNotEmpty && !force) return;
    await _run(() async {
      _plans = await _client.fetchPlans();
    });
  }

  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    await _run(() async {
      final token = await _client.login(
        email: email,
        password: password,
        captchaToken: captchaToken,
      );
      await _setToken(token);
      _userInfo = await _client.fetchUserInfo();
    });
  }

  Future<void> register({
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
    String? captchaToken,
  }) async {
    await _run(() async {
      final token = await _client.register(
        email: email,
        password: password,
        inviteCode: inviteCode,
        emailCode: emailCode,
        captchaToken: captchaToken,
      );
      await _setToken(token);
      _userInfo = await _client.fetchUserInfo();
    });
  }

  Future<void> refreshUserInfo() async {
    if (!isSignedIn) return;
    await _run(() async {
      _userInfo = await _client.fetchUserInfo();
    });
  }

  List<XboardPaymentMethod> _paymentMethods = const [];

  List<XboardPaymentMethod> get paymentMethods => _paymentMethods;

  Future<void> loadPaymentMethods() async {
    _paymentMethods = await _client.fetchPaymentMethods();
    _notify();
  }

  Future<XboardOrder> buy({
    required XboardPlan plan,
    required XboardPlanPeriod period,
    String? coupon,
    int? paymentId,
  }) {
    return _run(
      () => _client.createOrder(
        planId: plan.id,
        period: period.period,
        couponCode: coupon,
        paymentId: paymentId,
      ),
    );
  }

  Future<XboardPayment> pay({
    required String tradeNo,
    required int methodId,
  }) {
    return _run(
      () => _client.checkout(tradeNo: tradeNo, method: '$methodId'),
    );
  }

  Future<List<XboardOrderRecord>> fetchOrders() {
    return _run(() => _client.fetchOrders());
  }

  Future<void> cancelOrder(String tradeNo) async {
    await _run(() => _client.cancelOrder(tradeNo));
  }

  Future<void> sendEmailVerify(String email) async {
    await _run(() => _client.sendEmailVerify(email: email));
  }

  /// Asks the panel to mail a reset link; the panel decides whether the
  /// address exists and never says so.
  Future<void> forgetPassword(String email) async {
    await _run(() => _client.forget(email: email));
  }

  Future<void> signOut() async {
    await _setToken(null);
    _userInfo = null;
    _notify();
  }

  /// The Clash subscription link of the signed-in account, empty when the
  /// panel reports none.
  String get subscribeUrl {
    final info = _userInfo;
    if (info == null) return '';
    return _client.subscribeLink(info);
  }

  void dispose() {
    _changes.close();
  }
}

XboardSession? _session;

Future<XboardSession> xboardSession() async {
  final existing = _session;
  if (existing != null) return existing;
  SharedPreferences? preferences;
  try {
    preferences = await SharedPreferences.getInstance();
  } catch (_) {
    preferences = null;
  }
  final session = XboardSession(preferences);
  await session.restore();
  _session = session;
  return session;
}

String formatPrice(int cents, {String symbol = '¥'}) {
  if (cents <= 0) return '${symbol}0';
  final yuan = cents / 100;
  final text = yuan == yuan.roundToDouble()
      ? yuan.toStringAsFixed(0)
      : yuan.toStringAsFixed(2);
  return '$symbol$text';
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0
      ? 0
      : value >= 10
      ? 1
      : 2;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// A plan's `transfer_enable` is counted in GB, unlike the account's traffic
/// fields, which are bytes.
String formatPlanTraffic(int gb) {
  if (gb <= 0) return '不限';
  if (gb % 1024 == 0) return '${gb ~/ 1024} TB';
  return '$gb GB';
}

String formatDate(DateTime? date) {
  if (date == null) return '-';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
