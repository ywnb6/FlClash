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
      final value = json[key];
      if (value is num) {
        final price = value.toInt();
        return price > 0 ? price : null;
      }
      return null;
    }

    return XboardPlan(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      content: json['content'] as String? ?? '',
      monthPrice: readPrice('month_price'),
      quarterPrice: readPrice('quarter_price'),
      halfYearPrice: readPrice('half_year_price'),
      yearPrice: readPrice('year_price'),
      twoYearPrice: readPrice('two_year_price'),
      threeYearPrice: readPrice('three_year_price'),
      onetimePrice: readPrice('onetime_price'),
      transferEnable: (json['transfer_enable'] as num?)?.toInt(),
      sell: json['sell'] as bool? ?? true,
      sort: (json['sort'] as num?)?.toInt() ?? 0,
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
    final prices = periods.map((period) => period.price).toList();
    if (prices.isEmpty) return null;
    prices.sort();
    return prices.first;
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
    if (months == 0) {
      return locale.startsWith('zh') ? '一次性' : 'One time';
    }
    if (months == 1) return locale.startsWith('zh') ? '月付' : 'Monthly';
    if (months == 3) return locale.startsWith('zh') ? '季付' : 'Quarterly';
    if (months == 6) return locale.startsWith('zh') ? '半年' : '6 months';
    if (months == 12) return locale.startsWith('zh') ? '年付' : 'Yearly';
    return locale.startsWith('zh') ? '$months 个月' : '$months months';
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
    required this.subscribeUrl,
    required this.planName,
    required this.discount,
    required this.banned,
  });

  final String email;
  final int balance;
  final int commissionBalance;
  final int transferEnable;
  final int upload;
  final int download;
  final int? expiredAt;
  final String subscribeUrl;
  final String? planName;
  final int? discount;
  final int banned;

  factory XboardUserInfo.fromJson(Map<String, Object?> json) {
    final subscribe = json['subscribe_url'];
    return XboardUserInfo(
      email: json['email'] as String? ?? '',
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      commissionBalance: (json['commission_balance'] as num?)?.toInt() ?? 0,
      transferEnable: (json['transfer_enable'] as num?)?.toInt() ?? 0,
      upload: (json['u'] as num?)?.toInt() ?? 0,
      download: (json['d'] as num?)?.toInt() ?? 0,
      expiredAt: (json['expired_at'] as num?)?.toInt(),
      subscribeUrl: subscribe is String ? subscribe : '',
      planName: json['plan_name'] as String?,
      discount: (json['discount'] as num?)?.toInt(),
      banned: (json['banned'] as num?)?.toInt() ?? 0,
    );
  }

  int get used => upload + download;

  int get remain {
    final left = transferEnable - used;
    return left > 0 ? left : 0;
  }

  bool get hasSubscription => subscribeUrl.isNotEmpty;

  DateTime? get expiredAtDate => expiredAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(expiredAt! * 1000);
}

class XboardOrder {
  const XboardOrder({required this.tradeNo, this.methods});

  final String tradeNo;
  final Map<String, String>? methods;

  factory XboardOrder.fromJson(Map<String, Object?> json) {
    final rawMethods = json['payment_method'];
    final methods = <String, String>{};
    if (rawMethods is Map) {
      rawMethods.forEach((key, value) {
        if (value is String) methods['$key'] = value;
      });
    } else if (rawMethods is String && rawMethods.isNotEmpty) {
      methods[rawMethods] = rawMethods;
    }
    return XboardOrder(
      tradeNo: json['trade_no'] as String? ?? '',
      methods: methods.isEmpty ? null : methods,
    );
  }
}
