import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/store/xboard_client.dart';
import 'package:fl_clash/store/xboard_models.dart';
import 'package:fl_clash/store/store_auth_mode.dart';
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
  StreamSubscription<void>? _sessionSub;

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
    _sessionSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final session = await xboardSession();
    if (!mounted) return;
    setState(() => _session = session);
    // The sheet reports the session rather than a pop result, so the page
    // follows the session's own stream and repaints whenever sign-in state or
    // the profile changes.
    _sessionSub?.cancel();
    _sessionSub = session.changes.listen((_) {
      if (!mounted) return;
      setState(() => _signedIn = session.isSignedIn);
    });
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
      // A failed plan or site load must not undo a sign-in that already
      // succeeded, so the session still decides what the page shows.
      setState(() {
        _error = _humanError(error);
        _signedIn = session.isSignedIn;
        _plans = session.plans;
        _loading = false;
      });
    }
  }

  Future<void> _openSignIn() async {
    final session = _session;
    if (session == null) return;
    await showStoreSignInSheet(context, session: session);
    if (!mounted) return;
    setState(() => _signedIn = session.isSignedIn);
    if (!session.isSignedIn) return;
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
    final planName = session.userInfo?.planName?.trim();
    final label = planName == null || planName.isEmpty
        ? session.siteName
        : planName;
    await showStoreLinkSheet(
      context,
      url: url,
      siteName: session.siteName,
      onConfirm: (link) async {
        await ref
            .read(profilesActionProvider.notifier)
            .addProfileFromLink(link, label: label);
        dialogs.showBanner(
          currentAppLocalizations.storeImported,
          level: BannerLevel.success,
        );
      },
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
    if (!signedIn) {
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
    // The token can outlive a failed profile fetch, so the card renders from
    // empty figures rather than refusing to show a signed-in state.
    final profile = user ?? XboardUserInfo.empty();
    final ratio = profile.transferEnable <= 0
        ? 0.0
        : (profile.used / profile.transferEnable).clamp(0.0, 1.0);
    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  profile.email,
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
                  value: formatPrice(profile.balance),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: context.appLocalizations.storeExpireAt,
                  value: formatDate(profile.expiredAtDate),
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
            '${formatBytes(profile.used)} / ${formatBytes(profile.transferEnable)}',
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colors.onSurfaceVariant),
          ),
          if (profile.planName != null && profile.planName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${context.appLocalizations.storeCurrentPlan}: ${profile.planName}',
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


/// Closes the current route only while a route below it exists; a sheet stack
/// that already popped must not take the page with it.
void closeStoreRoute<T>(BuildContext context, [T? result]) {
  // The shop is a tab, so its sheets live on the root navigator; popping the
  // nearest one would leave the sheet on screen after a successful sign-in.
  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) {
    navigator.pop(result);
  }
}

/// Opens the sheet and reports whether the session ended up signed in. The
/// sheet is raised from a tab page, so a pop result would be delivered to the
/// wrong route; the session itself is what the caller reacts to.
Future<bool> showStoreSignInSheet(
  BuildContext context, {
  required XboardSession session,
}) async {
  await showNestedSheet<void>(
    context,
    builder: (_) => StoreAuthSheet(session: session),
  );
  // The route is gone; one frame lets the tab rebuild against the new session.
  await Future<void>.delayed(Duration.zero);
  return session.isSignedIn;
}

/// Visible so a widget test can drive the three forms without a live panel.
class StoreAuthSheet extends StatefulWidget {
  const StoreAuthSheet({super.key, required this.session});

  final XboardSession session;

  @override
  State<StoreAuthSheet> createState() => StoreAuthSheetState();
}

class StoreAuthSheetState extends State<StoreAuthSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _invite = TextEditingController();
  final _code = TextEditingController();
  bool _register = false;
  bool _reset = false;
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

  /// The panel resets the password in place, so the form asks for the mailed
  /// code and the new password instead of mailing a link.
  Future<void> _resetPassword() async {
    final appLocalizations = context.appLocalizations;
    final email = _email.text.trim();
    final password = _password.text;
    final code = _code.text.trim();
    if (email.isEmpty) {
      setState(() => _error = appLocalizations.storeFillEmail);
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = appLocalizations.storeFillCode);
      return;
    }
    if (password.length < 8) {
      setState(() => _error = appLocalizations.storePasswordTooShort);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.forgetPassword(
        email: email,
        password: password,
        emailCode: code,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _reset = false;
      });
      dialogs.showBanner(
        appLocalizations.storeResetDone,
        level: BannerLevel.success,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
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
        await widget.session.login(
          email: email,
          password: password,
        );
      }
      if (!mounted) return;
      setState(() => _busy = false);
      dialogs.showBanner(
        appLocalizations.storeSignedIn,
        level: BannerLevel.success,
      );
      closeStoreRoute(context);
    } catch (error) {
      if (!mounted) return;
      final message = _humanError(error);
      setState(() {
        _busy = false;
        _error = message;
      });
      // The text sits below the form, which the keyboard can cover; a banner
      // makes sure a failed attempt is visible without scrolling.
      dialogs.showBanner(message, level: BannerLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = context.colorScheme;
    final mode = storeAuthMode(register: _register, reset: _reset);
    final config = widget.session.siteConfig;
    // The panel's switch is about registration only; signing in and resetting
    // a password take no human check.
    final needCode = mode.showsEmailCodeFor(
      panelNeedsCode: config.needEmailVerify,
    );
    final showInvite = mode.showsInvite && config.inviteEnabled;
    final inviteRequired = mode.showsInvite && config.inviteRequired;
    return Scaffold(
      title: _reset
          ? appLocalizations.storeForgotPassword
          : _register
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
              if (needCode || _reset)
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
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colors.onErrorContainer),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy
                ? null
                : (_reset ? _resetPassword : _submit),
            child: _busy
                ? const ActivityIndicator(size: 16)
                : Text(
                    _reset
                        ? appLocalizations.storeResetPassword
                        : _register
                        ? appLocalizations.storeRegister
                        : appLocalizations.storeSignIn,
                  ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    final next = mode.toggled();
                    _reset = next == StoreAuthMode.reset;
                    _register = next == StoreAuthMode.register;
                    _error = null;
                  }),
            child: Text(
              _reset
                  ? appLocalizations.storeBackToSignIn
                  : _register
                  ? appLocalizations.storeHaveAccount
                  : appLocalizations.storeNoAccount,
            ),
          ),
          if (mode.showsForgotPassword)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _reset = true;
                      _error = null;
                    }),
              child: Text(appLocalizations.storeForgotPassword),
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
  XboardOrderRecord? _pendingOrder;
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
      closeStoreRoute(context, false);
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
        closeStoreRoute(context, true);
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
      // The payment sheet was the last route above this one, so closing it may
      // already have taken this one with it; popping again empties the stack.
      final route = ModalRoute.of(context);
      if (route?.isActive ?? false) {
        closeStoreRoute(context, true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      final pending = await _pendingOrderFor(error);
      if (!mounted) return;
      if (pending != null) {
        await _offerPendingOrder(pending);
        return;
      }
      setState(() => _error = _humanError(error));
    }
  }

  /// The panel refuses a new order while one is unpaid, and its message says
  /// so; the order itself is what the user wants to finish paying.
  Future<XboardOrderRecord?> _pendingOrderFor(Object error) async {
    if (error is! XboardException) return null;
    final message = error.message;
    if (!message.contains('未付款') && !message.contains('开通中')) return null;
    try {
      final orders = await widget.session.fetchOrders();
      for (final order in orders) {
        if (order.isPending) return order;
      }
    } catch (_) {}
    return null;
  }

  /// Shows the unpaid order in place instead of over the sheet, so the payment
  /// sheet that follows is never raised from inside another route.
  Future<void> _offerPendingOrder(XboardOrderRecord order) async {
    setState(() => _pendingOrder = order);
  }

  Future<void> _resumePendingOrder(XboardOrderRecord order) async {
    final paymentId = _paymentId;
    if (paymentId == null) {
      setState(() => _error = context.appLocalizations.storePickPayMethod);
      return;
    }
    setState(() => _busy = true);
    try {
      final payment = await widget.session.pay(
        tradeNo: order.tradeNo,
        methodId: paymentId,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      // A sheet raised from inside the dialog's route leaves the navigator
      // holding a popped route; wait for the frame that settles it first.
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      await showStorePaymentSheet(
        context,
        payment: payment,
        session: widget.session,
        tradeNo: order.tradeNo,
      );
      if (!mounted) return;
      await widget.session.refreshUserInfo();
      if (!mounted) return;
      closeStoreRoute(context, true);
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
          if (_pendingOrder != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _PendingOrderCard(
                order: _pendingOrder!,
                locale: locale,
                busy: _busy,
                onResume: () => _resumePendingOrder(_pendingOrder!),
                onDismiss: () => setState(() => _pendingOrder = null),
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
      closeStoreRoute(context);
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
                subtitle: FormRowTextField(
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
                  hintText: XboardClient.defaultUserAgent,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
              ListItem(
                title: Text(appLocalizations.storeUpdateSource),
                subtitle: FormRowTextField(
                  controller: _repo,
                  hintText: repository,
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

/// The unpaid order the panel is holding, shown in place: a dialog over the
/// sheet would leave a popped route behind, and the payment sheet raised after
/// it landed on a broken navigator.
class _PendingOrderCard extends StatelessWidget {
  const _PendingOrderCard({
    required this.order,
    required this.locale,
    required this.busy,
    required this.onResume,
    required this.onDismiss,
  });

  final XboardOrderRecord order;
  final String locale;
  final bool busy;
  final VoidCallback onResume;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = context.colorScheme;
    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appLocalizations.storePendingOrder,
            style: AppTextStyle.headline.of(context),
          ),
          const SizedBox(height: 6),
          Text(
            '${order.planName} · ${order.periodLabel(locale)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            '${order.statusLabel(locale)} · ${formatPrice(order.totalAmount)}',
            style: AppTextStyle.footnote.of(context).copyWith(
              color: colors.error,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: busy ? null : onResume,
                child: busy
                    ? const ActivityIndicator(size: 14)
                    : Text(appLocalizations.storeContinuePay),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: busy ? null : onDismiss,
                child: Text(appLocalizations.cancel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
