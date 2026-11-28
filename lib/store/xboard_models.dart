import 'package:fl_clash/store/xboard_parse.dart';

class XboardPlan {
  const XboardPlan({
    required this.id,
    required this.name,
    required this.content,
    this.monthPrice,
    this.quarterPrice,
    this.halfYearPrice,
    this.yearPrice,
    this.twoYearPrice,
    this.threeYearPrice,
    this.onetimePrice,
    this.transferEnable,
    this.sell = true,
    this.sort = 0,
  });

  final int id;
  final String name;
  final String content;
  final int? monthPrice;
  final int? quarterPrice;
  final int? halfYearPrice;
  final int? yearPrice;
  final int? twoYearPrice;
  final int? threeYearPrice;
  final int? onetimePrice;
  final int? transferEnable;
  final bool sell;
  final int sort;

  factory XboardPlan.fromJson(Map<String, Object?> json) {
    int? readPrice(String key) {
      final price = asInt(json[key]);
      return price != null && price > 0 ? price : null;
    }

    return XboardPlan(
      id: asIntOr(json['id'], 0),
      name: asString(json['name']),
      content: asString(json['content']),
      monthPrice: readPrice('month_price'),
      quarterPrice: readPrice('quarter_price'),
      halfYearPrice: readPrice('half_year_price'),
      yearPrice: readPrice('year_price'),
      twoYearPrice: readPrice('two_year_price'),
      threeYearPrice: readPrice('three_year_price'),
      onetimePrice: readPrice('onetime_price'),
      transferEnable: asInt(json['transfer_enable']),
      sell: asBool(json['sell']),
      sort: asIntOr(json['sort'], 0),
    );
  }

  List<XboardPlanPeriod> get periods => [
    if (monthPrice != null)
      XboardPlanPeriod(period: 'month_price', months: 1, price: monthPrice!),
    if (quarterPrice != null)
      XboardPlanPeriod(period: 'quarter_price', months: 3, price: quarterPrice!),
    if (halfYearPrice != null)
      XboardPlanPeriod(
        period: 'half_year_price',
        months: 6,
        price: halfYearPrice!,
      ),
    if (yearPrice != null)
      XboardPlanPeriod(period: 'year_price', months: 12, price: yearPrice!),
    if (twoYearPrice != null)
      XboardPlanPeriod(
        period: 'two_year_price',
        months: 24,
        price: twoYearPrice!,
      ),
    if (threeYearPrice != null)
      XboardPlanPeriod(
        period: 'three_year_price',
        months: 36,
        price: threeYearPrice!,
      ),
    if (onetimePrice != null)
      XboardPlanPeriod(
        period: 'onetime_price',
        months: 0,
        price: onetimePrice!,
      ),
  ];

  int? get minPrice {
    final prices = [for (final period in periods) period.price]..sort();
    return prices.isEmpty ? null : prices.first;
  }
}

class XboardPlanPeriod {
  const XboardPlanPeriod({
    required this.period,
    required this.months,
    required this.price,
  });

  final String period;
  final int months;
  final int price;

  String label(String locale) {
    final zh = locale.startsWith('zh');
    if (months == 0) return zh ? '一次性' : 'One time';
    if (months == 1) return zh ? '月付' : 'Monthly';
    if (months == 3) return zh ? '季付' : 'Quarterly';
    if (months == 6) return zh ? '半年' : '6 months';
    if (months == 12) return zh ? '年付' : 'Yearly';
    return zh ? '$months 个月' : '$months months';
  }
}

class XboardUserInfo {
  const XboardUserInfo({
    required this.email,
    required this.balance,
    required this.commissionBalance,
    required this.transferEnable,
    required this.upload,
    required this.download,
    required this.expiredAt,
    required this.subscribeToken,
    required this.subscribeUrl,
    required this.planName,
    required this.discount,
    required this.banned,
  });

  /// Stands in while the profile has not arrived yet, so the account card can
  /// still show a signed-in shell instead of nothing.
  const XboardUserInfo.empty()
    : email = '',
      balance = 0,
      commissionBalance = 0,
      transferEnable = 0,
      upload = 0,
      download = 0,
      expiredAt = null,
      subscribeToken = '',
      subscribeUrl = '',
      planName = null,
      discount = null,
      banned = 0;

  final String email;
  final int balance;
  final int commissionBalance;
  final int transferEnable;
  final int upload;
  final int download;
  final int? expiredAt;
  final String subscribeToken;
  final String subscribeUrl;
  final String? planName;
  final int? discount;
  final int banned;

  factory XboardUserInfo.fromJson(Map<String, Object?> json) {
    return XboardUserInfo(
      email: asString(json['email']),
      balance: asIntOr(json['balance'], 0),
      commissionBalance: asIntOr(json['commission_balance'], 0),
      transferEnable: asIntOr(json['transfer_enable'], 0),
      upload: asIntOr(json['u'], 0),
      download: asIntOr(json['d'], 0),
      expiredAt: asInt(json['expired_at']),
      subscribeToken: asString(json['token']),
      subscribeUrl: asString(json['subscribe_url']),
      planName: asStringOrNull(
        json['plan_name'] ?? asMap(json['plan'])['name'],
      ),
      discount: asInt(json['discount']),
      banned: asIntOr(json['banned'], 0),
    );
  }

  int get used {
    final total = upload + download;
    return total > 0 ? total : 0;
  }

  int get remain {
    final left = transferEnable - used;
    return left > 0 ? left : 0;
  }

  bool get hasSubscription => subscribeToken.isNotEmpty;

  DateTime? get expiredAtDate {
    final value = expiredAt;
    if (value == null || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }
}

class XboardOrder {
  const XboardOrder({required this.tradeNo, this.methods});

  final String tradeNo;
  final Map<String, String>? methods;

  factory XboardOrder.fromJson(Map<String, Object?> json) {
    final raw = json['payment_method'];
    final methods = <String, String>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        final text = asStringOrNull(value);
        if (text != null) {
          methods[asString(key, '$key')] = text;
        }
      });
    } else {
      final text = asStringOrNull(raw);
      if (text != null) methods[text] = text;
    }
    return XboardOrder(
      tradeNo: asString(json['trade_no']),
      methods: methods.isEmpty ? null : methods,
    );
  }
}

class XboardPaymentMethod {
  const XboardPaymentMethod({required this.id, required this.name});

  final int id;
  final String name;
}

/// What the panel decides about signing up; the shop follows it instead of
/// assuming a form shape, so a change on the panel reaches the app on refresh.
class XboardSiteConfig {
  const XboardSiteConfig({
    this.needEmailVerify = false,
    this.inviteRequired = false,
    this.inviteEnabled = false,
    this.logo = '',
    this.appUrl = '',
    this.description = '',
    this.emailSuffixes = const [],
    this.captchaEnabled = false,
    this.captchaType = '',
    this.turnstileSiteKey = '',
    this.recaptchaSiteKey = '',
  });

  final bool needEmailVerify;

  /// Whether an invite code is mandatory to sign up.
  final bool inviteRequired;

  /// Whether the panel accepts an invite code at all; an optional code is
  /// offered but never demanded.
  final bool inviteEnabled;
  final String logo;
  final String appUrl;
  final String description;
  final List<String> emailSuffixes;

  /// Whether signing up asks for a human check, and which widget draws it.
  final bool captchaEnabled;
  final String captchaType;
  final String turnstileSiteKey;
  final String recaptchaSiteKey;

  /// The site key the widget needs, empty when the panel asks for none.
  String get captchaSiteKey => switch (captchaType) {
    'turnstile' => turnstileSiteKey,
    'recaptcha' || 'recaptcha-v3' => recaptchaSiteKey,
    _ => turnstileSiteKey.isNotEmpty ? turnstileSiteKey : recaptchaSiteKey,
  };

  factory XboardSiteConfig.fromJson(Map<String, Object?> json) {
    final suffixes = json['email_whitelist_suffix'];
    return XboardSiteConfig(
      needEmailVerify: asBool(json['is_email_verify'], fallback: false),
      inviteRequired: asBool(json['is_invite_force'], fallback: false),
      inviteEnabled:
          asBool(json['is_invite_force'], fallback: false) ||
          asBool(json['is_invite'], fallback: true),
      logo: asString(json['logo']),
      captchaEnabled: asBool(json['is_captcha'], fallback: false),
      captchaType: asString(json['captcha_type']),
      turnstileSiteKey: asString(json['turnstile_site_key']),
      recaptchaSiteKey: asString(json['recaptcha_site_key']),
      appUrl: asString(json['app_url']),
      description: asString(json['app_description']),
      emailSuffixes: [
        if (suffixes is List)
          for (final suffix in suffixes)
            if (asStringOrNull(suffix) != null) asString(suffix),
      ],
    );
  }

  bool accepts(String email) {
    if (emailSuffixes.isEmpty) return true;
    final at = email.lastIndexOf('@');
    if (at < 0) return true;
    final suffix = email.substring(at + 1).toLowerCase();
    return emailSuffixes.any((item) => item.toLowerCase() == suffix);
  }
}

/// What the panel hands back for a payment: a page to open, or a payload the
/// app renders as a code.
class XboardPayment {
  const XboardPayment({required this.isRedirect, required this.payload});

  final bool isRedirect;
  final String payload;

  String get url => payload;
}

class XboardOrderRecord {
  const XboardOrderRecord({
    required this.tradeNo,
    required this.planName,
    required this.period,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
  });

  final String tradeNo;
  final String planName;
  final String period;
  final int totalAmount;
  final int status;
  final int createdAt;

  factory XboardOrderRecord.fromJson(Map<String, Object?> json) {
    return XboardOrderRecord(
      tradeNo: asString(json['trade_no']),
      planName: asString(asMap(json['plan'])['name'], asString(json['plan_id'])),
      period: asString(json['period']),
      totalAmount: asIntOr(json['total_amount'], 0),
      status: asIntOr(json['status'], 0),
      createdAt: asIntOr(json['created_at'], 0),
    );
  }

  bool get isPending => status == 0;

  String periodLabel(String locale) {
    final zh = locale.startsWith('zh');
    switch (period) {
      case 'month_price':
        return zh ? '月付' : 'Monthly';
      case 'quarter_price':
        return zh ? '季付' : 'Quarterly';
      case 'half_year_price':
        return zh ? '半年' : '6 months';
      case 'year_price':
        return zh ? '年付' : 'Yearly';
      case 'two_year_price':
        return zh ? '两年' : '2 years';
      case 'three_year_price':
        return zh ? '三年' : '3 years';
      case 'onetime_price':
        return zh ? '一次性' : 'One time';
      default:
        return period;
    }
  }

  String statusLabel(String locale) {
    final zh = locale.startsWith('zh');
    switch (status) {
      case 0:
        return zh ? '待支付' : 'Unpaid';
      case 1:
        return zh ? '开通中' : 'Processing';
      case 2:
        return zh ? '已完成' : 'Completed';
      case 3:
        return zh ? '已取消' : 'Cancelled';
      default:
        return '$status';
    }
  }
}
