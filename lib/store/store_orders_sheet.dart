import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/store/xboard_client.dart';
import 'package:fl_clash/store/xboard_models.dart';
import 'package:fl_clash/store/xboard_session.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/nested_sheet.dart';
import 'package:fl_clash/ui/scaffold/scaffold.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// Lists the account's orders so an unpaid one can be found and cancelled
/// without leaving the app; the panel refuses a new order while one is open.
Future<void> showStoreOrdersSheet(
  BuildContext context, {
  required XboardSession session,
}) {
  return showNestedSheet<void>(
    context,
    builder: (_) => _OrdersSheet(session: session),
  );
}

class _OrdersSheet extends StatefulWidget {
  const _OrdersSheet({required this.session});

  final XboardSession session;

  @override
  State<_OrdersSheet> createState() => _OrdersSheetState();
}

class _OrdersSheetState extends State<_OrdersSheet> {
  List<XboardOrderRecord> _orders = const [];
  bool _loading = true;
  String? _error;
  String? _busyTradeNo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await widget.session.fetchOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is XboardException ? error.message : '$error';
        _loading = false;
      });
    }
  }

  Future<void> _cancel(XboardOrderRecord order) async {
    setState(() => _busyTradeNo = order.tradeNo);
    try {
      await widget.session.cancelOrder(order.tradeNo);
      if (!mounted) return;
      dialogs.showBanner(
        currentAppLocalizations.storeOrderCancelled,
        level: BannerLevel.success,
      );
    } catch (error) {
      if (!mounted) return;
      dialogs.showBanner(
        error is XboardException ? error.message : '$error',
        level: BannerLevel.error,
      );
    } finally {
      if (mounted) setState(() => _busyTradeNo = null);
    }
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = context.colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    return Scaffold(
      title: appLocalizations.storeOrders,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: appLocalizations.storeRefresh,
          isLoading: _loading,
          onPressed: _load,
        ),
      ],
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.sectionsTopPadding,
          bottom: 24 + context.bottomInset,
        ),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: ActivityIndicator(size: 24)),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTextStyle.body
                    .of(context)
                    .copyWith(color: colors.error),
              ),
            )
          else if (_orders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                appLocalizations.storeNoOrders,
                textAlign: TextAlign.center,
                style: AppTextStyle.body
                    .of(context)
                    .copyWith(color: colors.onSurfaceVariant),
              ),
            )
          else
            generateSection(
              items: [
                for (final order in _orders)
                  ListItem(
                    title: Text(
                      '${order.planName} · ${order.periodLabel(locale)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${order.statusLabel(locale)} · '
                      '${formatPrice(order.totalAmount)}',
                      style: AppTextStyle.footnote.of(context).copyWith(
                        color: order.isPending
                            ? colors.error
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    trailing: order.isPending
                        ? TextButton(
                            onPressed: _busyTradeNo == order.tradeNo
                                ? null
                                : () => _cancel(order),
                            child: _busyTradeNo == order.tradeNo
                                ? const ActivityIndicator(size: 14)
                                : Text(appLocalizations.storeCancelOrder),
                          )
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
