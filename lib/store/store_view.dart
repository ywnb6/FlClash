import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/pages/navigation.dart';
import 'package:fl_clash/providers/generated/action.g.dart';
import 'package:fl_clash/store/xboard_models.dart';
import 'package:fl_clash/store/xboard_session.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/scaffold/scaffold.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prism_ui/prism_ui.dart';

class StoreView extends StatefulWidget {
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

  @override
  void initState() {
    super.initState();
    _bootstrap();
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
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openSignIn() async {
    final session = _session;
    if (session == null) return;
    final signedIn = await showStoreSignInSheet(context, session: session);
    if (!mounted) return;
    if (signedIn) {
      await _refresh(force: true);
    }
  }

  Future<void> _openPlan(XboardPlan plan) async {
    final session = _session;
    if (session == null) return;
    final bought = await showStorePlanSheet(
      context,
      session: session,
      plan: plan,
    );
    if (!mounted) return;
    if (bought) {
      await _refresh(force: true);
    }
  }

  Future<void> _signOut() async {
    final session = _session;
    if (session == null) return;
    await session.signOut();
    if (!mounted) return;
    setState(() {
      _signedIn = false;
    });
    dialogs.showBanner(
      currentAppLocalizations.storeSignedOut,
      level: BannerLevel.info,
    );
  }

  Future<void> _openSettings() async {
    final session = _session;
    if (session == null) return;
    await showStoreSettingsSheet(context, session: session);
    if (!mounted) return;
    await _refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _AccountCard(
        session: _session,
        signedIn: _signedIn,
        onSignIn: _openSignIn,
        onSignOut: _signOut,
        onSubscribe: _importSubscription,
      ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_error != null)
        _ErrorView(
          message: _error!,
          onRetry: () => _refresh(force: true),
        )
      else ...[
        _SectionHeader(title: context.appLocalizations.storePlans),
        for (final plan in _plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PlanCard(
              plan: plan,
              onTap: () => _openPlan(plan),
            ),
          ),
        if (_plans.isEmpty) _EmptyPlans(),
      ],
    ];
    return Scaffold(
      title: PageLabel.store.label,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.settings,
          tooltip: context.appLocalizations.storeSettings,
          onPressed: _openSettings,
        ),
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: context.appLocalizations.storeRefresh,
          onPressed: () => _refresh(force: true),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () => _refresh(force: true),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context),
          child: ListView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: context.sectionsTopPadding,
              bottom: 24 + context.bottomInset,
            ),
            children: items,
          ),
        ),
      ),
    );
  }

  Future<void> _importSubscription() async {
    final session = _session;
    if (session == null) return;
    if (!session.isSignedIn) {
      await _openSignIn();
      return;
    }
    final url = session.subscribeUrl;
    if (url.isEmpty) {
      dialogs.showBanner(
        currentAppLocalizations.storeNoSubscription,
        level: BannerLevel.warning,
      );
      return;
    }
    final label = session.userInfo?.planName?.trim();
    await ref
        .read(profilesActionProvider)
        .addProfileFromLink(
          url,
          label: label == null || label.isEmpty ? 'Xboard' : label,
        );
    if (!mounted) return;
    dialogs.showBanner(
      currentAppLocalizations.storeImported,
      level: BannerLevel.success,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
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
      padding: const EdgeInsets.symmetric(vertical: 40),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10, left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: AppTextStyle.headline.of(context),
        ),
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
    required this.onSubscribe,
  });

  final XboardSession? session;
  final bool signedIn;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final user = session?.userInfo;
    final colors = context.colorScheme;
    if (!signedIn || user == null) {
      return Card(
        child: Padding(
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
                session?.baseUrl ?? XboardClient.defaultBaseUrl,
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
        ),
      );
    }
    final total = user.transferEnable <= 0 ? 0.0 : user.used / user.transferEnable;
    return Card(
      child: Padding(
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
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: colors.surfaceContainerHighest,
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
            Row(
              children: [
                FilledButton(
                  onPressed: onSubscribe,
                  child: Text(context.appLocalizations.storeImportSubscription),
                ),
              ],
            ),
          ],
        ),
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

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onTap});

  final XboardPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final periods = plan.periods;
    final colors = context.colorScheme;
    return Card(
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.name,
              style: AppTextStyle.headline.of(context),
            ),
            const SizedBox(height: 8),
            if (plan.transferEnable != null)
              Text(
                formatBytes(plan.transferEnable!),
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colors.onSurfaceVariant),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final period in periods)
                  _PeriodChip(
                    label:
                        '${period.label(Localizations.localeOf(context).languageCode)} '
                        '${formatPrice(period.price)}',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: AppTextStyle.footnote.of(context)),
      ),
    );
  }
}

String _humanError(Object error) {
  if (error is XboardException) return error.message;
  return error.toString();
}

Future<bool> showStoreSignInSheet(
  BuildContext context, {
  required XboardSession session,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SignInSheet(session: session),
  );
  return changed ?? false;
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
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = context.appLocalizations.storeFillAll);
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _register
                    ? appLocalizations.storeRegister
                    : appLocalizations.storeSignIn,
                textAlign: TextAlign.center,
                style: AppTextStyle.title2.of(context, emphasized: true),
              ),
              const SizedBox(height: 4),
              Text(
                widget.session.baseUrl,
                textAlign: TextAlign.center,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FormRowTextField(
                controller: _email,
                hintText: appLocalizations.storeEmail,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 12),
              FormRowTextField(
                controller: _password,
                hintText: appLocalizations.storePassword,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_register) ...[
                const SizedBox(height: 12),
                FormRowTextField(
                  controller: _invite,
                  hintText: appLocalizations.storeInviteCode,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
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
        ),
      ),
    );
  }
}

Future<bool> showStorePlanSheet(
  BuildContext context, {
  required XboardSession session,
  required XboardPlan plan,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
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
  late XboardPlanPeriod? _period;
  Map<String, String>? _methods;
  String? _selectedMethod;
  String? _tradeNo;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final periods = widget.plan.periods;
    _period = periods.isEmpty ? null : periods.first;
  }

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final period = _period;
    if (period == null) return;
    if (!widget.session.isSignedIn) {
      Navigator.of(context).pop(false);
      await showStoreSignInSheet(context, session: widget.session);
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
      );
      final methods = order.methods;
      if (methods == null || methods.isEmpty) {
        await widget.session.refreshUserInfo();
        if (!mounted) return;
        Navigator.of(context).pop(true);
        dialogs.showBanner(
          context.appLocalizations.storeOrderCreated,
          level: BannerLevel.success,
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _tradeNo = order.tradeNo;
        _methods = methods;
        _selectedMethod = methods.keys.first;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _humanError(error);
      });
    }
  }

  Future<void> _pay() async {
    final tradeNo = _tradeNo;
    final method = _selectedMethod;
    if (tradeNo == null || method == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await widget.session.pay(tradeNo: tradeNo, method: method);
      if (!mounted) return;
      setState(() => _busy = false);
      if (url.isNotEmpty) {
        await dialogs.openUrl(url);
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
    final periods = widget.plan.periods;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.plan.name,
              textAlign: TextAlign.center,
              style: AppTextStyle.title2.of(context, emphasized: true),
            ),
            const SizedBox(height: 16),
            if (widget.plan.content.trim().isNotEmpty)
              Text(
                _stripMarkdown(widget.plan.content),
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colors.onSurfaceVariant, height: 1.5),
              ),
            const SizedBox(height: 16),
            for (final period in periods)
              _PeriodRow(
                period: period,
                selected: _period?.period == period.period,
                locale: Localizations.localeOf(context).languageCode,
                onTap: _tradeNo != null
                    ? null
                    : () => setState(() => _period = period),
              ),
            if (_tradeNo == null) ...[
              const SizedBox(height: 12),
              FormRowTextField(
                controller: _coupon,
                hintText: appLocalizations.storeCoupon,
                autocorrect: false,
                enableSuggestions: false,
              ),
            ],
            if (_methods != null) ...[
              const SizedBox(height: 16),
              Text(
                appLocalizations.storePayMethod,
                style: AppTextStyle.headline.of(context),
              ),
              const SizedBox(height: 8),
              for (final entry in _methods!.entries)
                _MethodRow(
                  label: entry.value,
                  selected: _selectedMethod == entry.key,
                  onTap: () => setState(() => _selectedMethod = entry.key),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: AppTextStyle.footnote.of(context).copyWith(
                  color: colors.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_period != null)
              FilledButton(
                onPressed: _busy ? null : (_tradeNo == null ? _create : _pay),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _tradeNo == null
                            ? '${appLocalizations.storeBuy} · '
                                  '${formatPrice(_period!.price)}'
                            : appLocalizations.storePay,
                      ),
              ),
          ],
        ),
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

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.period,
    required this.selected,
    required this.locale,
    required this.onTap,
  });

  final XboardPlanPeriod period;
  final bool selected;
  final String locale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                period.label(locale),
                style: AppTextStyle.body.of(context),
              ),
            ),
            Text(
              formatPrice(period.price),
              style: AppTextStyle.body.of(context, emphasized: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: Text(label, style: AppTextStyle.body.of(context)),
      ),
    );
  }
}

Future<void> showStoreSettingsSheet(
  BuildContext context, {
  required XboardSession session,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
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

  @override
  void dispose() {
    _url.dispose();
    _ua.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.session.setBaseUrl(_url.text);
    await widget.session.setUserAgent(_ua.text);
    if (!mounted) return;
    Navigator.of(context).pop();
    dialogs.showBanner(
      context.appLocalizations.storeSettingsSaved,
      level: BannerLevel.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              appLocalizations.storeSettings,
              textAlign: TextAlign.center,
              style: AppTextStyle.title2.of(context, emphasized: true),
            ),
            const SizedBox(height: 20),
            Text(
              appLocalizations.storePanelUrl,
              style: AppTextStyle.footnote.of(context),
            ),
            const SizedBox(height: 6),
            FormRowTextField(
              controller: _url,
              hintText: 'https://plan.zzyo.top',
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 16),
            Text(
              appLocalizations.storeUserAgent,
              style: AppTextStyle.footnote.of(context),
            ),
            const SizedBox(height: 6),
            FormRowTextField(
              controller: _ua,
              hintText: 'FlClash/0.9.4',
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Text(appLocalizations.storeSave),
            ),
          ],
        ),
      ),
    );
  }
}
