import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/store/xboard_client.dart';
import 'package:fl_clash/store/xboard_models.dart';
import 'package:fl_clash/store/store_link_sheet.dart';
import 'package:fl_clash/store/store_orders_sheet.dart';
import 'package:fl_clash/store/store_payment_sheet.dart';
import 'package:fl_clash/store/xboard_session.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/nested_sheet.dart';
import 'package:fl_clash/ui/scaffold/scaffold.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart';

class StoreView extends ConsumerStatefulWidget {
  const StoreView({super.key});

  @override
  ConsumerState<StoreView> createState() => _StoreViewState();
}

class _StoreViewState extends ConsumerState<StoreView> {
  XboardSession? _session;
  List<XboardPlan> _plans = const [];
  bool _loading = true;
  String? _error;
  bool _signedIn = false;

  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _syncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refresh(force: true),
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final session = await xboardSession();
    if (!mounted) return;
    setState(() => _session = session);
    await _refresh(force: true);
  }

  Future<void> _refresh({bool force = false}) async {
    final session = _session;
    if (session == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await session.loadSiteInfo(force: force);
      await session.loadPlans(force: force);
      if (session.isSignedIn) {
        await session.refreshUserInfo();
      }
      if (!mounted) return;
      setState(() {
        _plans = session.plans;
        _signedIn = session.isSignedIn;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _humanError(error);
        _loading = false;
      });
    }
  }

  Future<void> _openSignIn() async {
    final session = _session;
    if (session == null) return;
    final signedIn = await showStoreSignInSheet(context, session: session);
    if (!mounted || !signedIn) return;
    await _refresh(force: true);
  }

  Future<void> _openPlan(XboardPlan plan) async {
    final session = _session;
    if (session == null) return;
    final bought = await showStorePlanSheet(
      context,
      session: session,
      plan: plan,
    );
    if (!mounted || !bought) return;
    await _refresh(force: true);
  }

  Future<void> _signOut() async {
    final session = _session;
    if (session == null) return;
    await session.signOut();
    if (!mounted) return;
    setState(() => _signedIn = false);
    dialogs.showBanner(currentAppLocalizations.storeSignedOut);
  }

  Future<void> _openOrders() async {
    final session = _session;
    if (session == null) return;
    if (!session.isSignedIn) {
      await _openSignIn();
      return;
    }
    await showStoreOrdersSheet(context, session: session);
    if (!mounted) return;
    await _refresh(force: true);
  }

  Future<void> _openSettings() async {
    final session = _session;
    if (session == null) return;
    await showStoreSettingsSheet(context, session: session);
    if (!mounted) return;
    await _refresh(force: true);
  }

  Future<void> _importSubscription() async {
    final session = _session;
    if (session == null) return;
    if (!session.isSignedIn) {
      await _openSignIn();
      return;
    }
    setState(() => _loading = true);
    String url;
    try {
      await session.refreshUserInfo();
      if (!mounted) return;
      url = session.subscribeUrl;
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      dialogs.showBanner(
        _humanError(error),
        level: BannerLevel.error,
      );
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (url.isEmpty) {
      dialogs.showBanner(
        currentAppLocalizations.storeNoSubscription,
        level: BannerLevel.warning,
      );
      return;
    }
    final link = await showStoreLinkSheet(
      context,
      url: url,
      siteName: session.siteName,
    );
    if (!mounted || link == null || link.isEmpty) return;
    final planName = session.userInfo?.planName?.trim();
    final label = planName == null || planName.isEmpty
        ? session.siteName
        : planName;
    await ref
        .read(profilesActionProvider.notifier)
        .addProfileFromLink(link, label: label);
    if (!mounted) return;
    dialogs.showBanner(
      currentAppLocalizations.storeImported,
      level: BannerLevel.success,
    );
  }

  List<Widget> _buildItems(BuildContext context) {
    final items = <Widget>[
      _AccountCard(
        session: _session,
        signedIn: _signedIn,
        onSignIn: _openSignIn,
        onSignOut: _signOut,
        onImport: _importSubscription,
      ),
    ];
    if (_loading) {
      items.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: ActivityIndicator(size: 24)),
        ),
      );
      return items;
    }
    if (_error != null) {
      items.add(
        _ErrorView(message: _error!, onRetry: () => _refresh(force: true)),
      );
      return items;
    }
    items.add(
      generateSection(
        title: context.appLocalizations.storePlans,
        items: [
          for (final plan in _plans)
            _PlanRow(plan: plan, onTap: () => _openPlan(plan)),
          if (_plans.isEmpty) _EmptyPlans(),
        ],
      ),
    );
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(context);
    return Scaffold(
      title: PageLabel.store.label,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.listAdd,
          tooltip: context.appLocalizations.storeOrders,
          onPressed: _openOrders,
        ),
        IconButtonData(
          glyph: AppGlyphs.settings,
          tooltip: context.appLocalizations.storeSettings,
          onPressed: _openSettings,
        ),
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: context.appLocalizations.storeRefresh,
          isLoading: _loading,
          onPressed: () => _refresh(force: true),
        ),
      ],
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, index) => items[index],
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.sectionsTopPadding,
          bottom: 20 + context.bottomInset,
        ),
      ),
    );
  }
}

String _humanError(Object error) {
  if (error is XboardException) return error.message;
  return error.toString();
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyle.body
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: Text(context.appLocalizations.retry),
          ),
        ],
      ),
    );
  }
}

class _EmptyPlans extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Text(
        context.appLocalizations.storeNoPlans,
        textAlign: TextAlign.center,
        style: AppTextStyle.body
            .of(context)
            .copyWith(color: context.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.session,
    required this.signedIn,
    required this.onSignIn,
    required this.onSignOut,
    required this.onImport,
  });

  final XboardSession? session;
  final bool signedIn;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final user = session?.userInfo;
    if (!signedIn || user == null) {
      return Card(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.appLocalizations.storeWelcome,
              style: AppTextStyle.title3.of(context, emphasized: true),
            ),
            const SizedBox(height: 6),
            Text(
              session?.siteName ?? XboardClient.defaultSiteName,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onSignIn,
              child: Text(context.appLocalizations.storeSignIn),
            ),
          ],
        ),
      );
    }
    final ratio = user.transferEnable <= 0
        ? 0.0
        : (user.used / user.transferEnable).clamp(0.0, 1.0);
    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.headline.of(context),
                ),
              ),
              TextButton(
                onPressed: onSignOut,
                child: Text(context.appLocalizations.storeSignOut),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: context.appLocalizations.storeBalance,
                  value: formatPrice(user.balance),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: context.appLocalizations.storeExpireAt,
                  value: formatDate(user.expiredAtDate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRect(
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(value: ratio),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${context.appLocalizations.storeTraffic}: '
            '${formatBytes(user.used)} / ${formatBytes(user.transferEnable)}',
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colors.onSurfaceVariant),
          ),
          if (user.planName != null && user.planName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${context.appLocalizations.storeCurrentPlan}: ${user.planName}',
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onImport,
            child: Text(context.appLocalizations.storeImportSubscription),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyle.title3.of(context, emphasized: true)),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.onTap});

  final XboardPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final periods = plan.periods;
    final subtitle = [
      if (plan.transferEnable != null) formatPlanTraffic(plan.transferEnable!),
      for (final period in periods)
        '${period.label(locale)} ${formatPrice(period.price)}',
    ].join(' · ');
    return ListItem(
      title: Text(plan.name),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
      onTap: onTap,
    );
  }
}

Future<bool> showStoreSignInSheet(
  BuildContext context, {
  required XboardSession session,
}) async {
  final result = await showNestedSheet<bool>(
    context,
    builder: (_) => _SignInSheet(session: session),
  );
  return result ?? false;
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet({required this.session});

  final XboardSession session;

  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _invite = TextEditingController();
  final _code = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _sendingCode = false;
  int _cooldown = 0;
  Timer? _ticker;
  String? _error;

  @override
  void dispose() {
    _ticker?.cancel();
    _email.dispose();
    _password.dispose();
    _invite.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _cooldown = 60);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldown -= 1;
        if (_cooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _sendCode() async {
    final appLocalizations = context.appLocalizations;
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = appLocalizations.storeFillEmail);
      return;
    }
    setState(() {
      _sendingCode = true;
      _error = null;
    });
    try {
      await widget.session.sendEmailVerify(email);
      if (!mounted) return;
      setState(() => _sendingCode = false);
      _startCooldown();
      dialogs.showBanner(
        appLocalizations.storeCodeSent,
        level: BannerLevel.success,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sendingCode = false;
        _error = _humanError(error);
      });
    }
  }

  Future<void> _submit() async {
    final appLocalizations = context.appLocalizations;
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = appLocalizations.storeFillAll);
      return;
    }
    final config = widget.session.siteConfig;
    if (_register && !config.accepts(email)) {
      setState(() => _error = appLocalizations.storeEmailNotAllowed);
      return;
    }
    if (_register && config.needEmailVerify && _code.text.trim().isEmpty) {
      setState(() => _error = appLocalizations.storeFillCode);
      return;
    }
    if (_register && config.inviteRequired && _invite.text.trim().isEmpty) {
      setState(() => _error = appLocalizations.storeFillInvite);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await widget.session.register(
          email: email,
          password: password,
          inviteCode: _invite.text,
          emailCode: _code.text,
        );
      } else {
        await widget.session.login(email: email, password: password);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _humanError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = context.colorScheme;
    final config = widget.session.siteConfig;
    final needCode = _register && config.needEmailVerify;
    final showInvite = _register && config.inviteEnabled;
    final inviteRequired = _register && config.inviteRequired;
    return Scaffold(
      title: _register
          ? appLocalizations.storeRegister
          : appLocalizations.storeSignIn,
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.sectionsTopPadding,
          bottom: 24 + context.bottomInset,
        ),
        children: [
          generateSection(
            title: widget.session.siteName,
            items: [
              ListItem(
                title: FormRowTextField(
                  controller: _email,
                  hintText: appLocalizations.storeEmail,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
              ListItem(
                title: FormRowTextField(
                  controller: _password,
                  hintText: appLocalizations.storePassword,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ),
              if (needCode)
                ListItem(
                  title: FormRowTextField(
                    controller: _code,
                    hintText: appLocalizations.storeEmailCode,
                    keyboardType: TextInputType.number,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                  trailing: TextButton(
                    onPressed: _sendingCode || _cooldown > 0
                        ? null
                        : _sendCode,
                    child: _sendingCode
                        ? const ActivityIndicator(size: 14)
                        : Text(
                            _cooldown > 0
                                ? '${_cooldown}s'
                                : appLocalizations.storeSendCode,
                          ),
                  ),
                ),
              if (showInvite)
                ListItem(
                  title: FormRowTextField(
                    controller: _invite,
                    hintText: inviteRequired
                        ? appLocalizations.storeInviteCodeRequired
                        : appLocalizations.storeInviteCode,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colors.error),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const ActivityIndicator(size: 16)
                : Text(
                    _register
                        ? appLocalizations.storeRegister
                        : appLocalizations.storeSignIn,
                  ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _register = !_register;
                    _error = null;
                  }),
            child: Text(
              _register
                  ? appLocalizations.storeHaveAccount
                  : appLocalizations.storeNoAccount,
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> showStorePlanSheet(
  BuildContext context, {
  required XboardSession session,
  required XboardPlan plan,
}) async {
  final result = await showNestedSheet<bool>(
    context,
    builder: (_) => _PlanSheet(session: session, plan: plan),
  );
  return result ?? false;
}

class _PlanSheet extends StatefulWidget {
  const _PlanSheet({required this.session, required this.plan});

  final XboardSession session;
  final XboardPlan plan;

  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  final _coupon = TextEditingController();
  XboardPlanPeriod? _period;
  List<XboardPaymentMethod> _methods = const [];
  int? _paymentId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final periods = widget.plan.periods;
    _period = periods.isEmpty ? null : periods.first;
    _loadMethods();
  }

  Future<void> _loadMethods() async {
    try {
      await widget.session.loadPaymentMethods();
      if (!mounted) return;
      final methods = widget.session.paymentMethods;
      setState(() {
        _methods = methods;
        _paymentId = methods.isEmpty ? null : methods.first.id;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _methods = const []);
    }
  }

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _buy() async {
    final period = _period;
    if (period == null) return;
    if (!widget.session.isSignedIn) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await widget.session.buy(
        plan: widget.plan,
        period: period,
        coupon: _coupon.text,
        paymentId: _paymentId,
      );
      if (!mounted) return;
      if (_paymentId == null) {
        await widget.session.refreshUserInfo();
        if (!mounted) return;
        Navigator.of(context).pop(true);
        dialogs.showBanner(
          currentAppLocalizations.storeOrderCreated,
          level: BannerLevel.success,
        );
        return;
      }
      final payment = await widget.session.pay(
        tradeNo: order.tradeNo,
        methodId: _paymentId!,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await showStorePaymentSheet(
        context,
        payment: payment,
        session: widget.session,
        tradeNo: order.tradeNo,
      );
      if (!mounted) return;
      await widget.session.refreshUserInfo();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _humanError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = context.colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final periods = widget.plan.periods;
    return Scaffold(
      title: widget.plan.name,
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.sectionsTopPadding,
          bottom: 24 + context.bottomInset,
        ),
        children: [
          if (widget.plan.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
              child: Text(
                _stripMarkdown(widget.plan.content),
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colors.onSurfaceVariant, height: 1.5),
              ),
            ),
          generateSection(
            title: appLocalizations.storePlans,
            items: [
              for (final period in periods)
                _ChoiceRow(
                  label: period.label(locale),
                  trailing: formatPrice(period.price),
                  selected: _period?.period == period.period,
                  onTap: () => setState(() => _period = period),
                ),
            ],
          ),
          if (_methods.isNotEmpty)
            generateSection(
              title: appLocalizations.storePayMethod,
              items: [
                for (final method in _methods)
                  _ChoiceRow(
                    label: method.name,
                    selected: _paymentId == method.id,
                    onTap: () => setState(() => _paymentId = method.id),
                  ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FormRowTextField(
              controller: _coupon,
              hintText: appLocalizations.storeCoupon,
              autocorrect: false,
              enableSuggestions: false,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: AppTextStyle.footnote.of(context).copyWith(
                  color: colors.error,
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_period != null)
            FilledButton(
              onPressed: _busy ? null : _buy,
              child: _busy
                  ? const ActivityIndicator(size: 16)
                  : Text(
                      '${appLocalizations.storeBuy} · '
                      '${formatPrice(_period!.price)}',
                    ),
            ),
        ],
      ),
    );
  }
}

String _stripMarkdown(String source) {
  return source
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll('**', '')
      .replaceAllMapped(RegExp(r'^-\s+', multiLine: true), (_) => '· ');
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    this.trailing,
    this.onTap,
  });

  final String label;
  final bool selected;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyle.body.of(context, emphasized: selected),
              ),
            ),
            if (trailing != null) ...[
              Text(trailing!, style: AppTextStyle.body.of(context)),
              const SizedBox(width: 8),
            ],
            if (selected)
              GlyphIcon(AppGlyphs.check, size: 16, color: colors.primary)
            else
              const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

Future<void> showStoreSettingsSheet(
  BuildContext context, {
  required XboardSession session,
}) async {
  await showNestedSheet<void>(
    context,
    builder: (_) => _SettingsSheet(session: session),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.session});

  final XboardSession session;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final _url = TextEditingController(text: widget.session.baseUrl);
  late final _ua = TextEditingController(text: widget.session.userAgent);
  final _repo = TextEditingController();
  String _currentRepo = repository;

  @override
  void initState() {
    super.initState();
    _loadRepo();
  }

  Future<void> _loadRepo() async {
    final value = await request.resolvedRepository();
    if (!mounted) return;
    setState(() {
      _currentRepo = value;
      _repo.text = value;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _ua.dispose();
    _repo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.session.setBaseUrl(_url.text);
    await widget.session.setUserAgent(_ua.text);
    await request.setCustomRepository(_repo.text);
    if (!mounted) return;
    Navigator.of(context).pop();
    dialogs.showBanner(
      currentAppLocalizations.storeSettingsSaved,
      level: BannerLevel.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Scaffold(
      title: appLocalizations.storeSettings,
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.sectionsTopPadding,
          bottom: 24 + context.bottomInset,
        ),
        children: [
          generateSection(
            items: [
              ListItem(
                title: Text(appLocalizations.storePanelUrl),
                trailing: FormRowTextField(
                  controller: _url,
                  hintText: appLocalizations.storePanelUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
              ListItem(
                title: Text(appLocalizations.storeUserAgent),
                subtitle: FormRowTextField(
                  controller: _ua,
                  hintText: 'FlClash/0.9.4',
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
              ListItem(
                title: Text(appLocalizations.storeUpdateSource),
                subtitle: FormRowTextField(
                  controller: _repo,
                  hintText: 'owner/repo',
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            child: Text(appLocalizations.storeSave),
          ),
        ],
      ),
    );
  }
}
