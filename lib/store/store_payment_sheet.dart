import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/store/xboard_models.dart';
import 'package:fl_clash/store/xboard_session.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/nested_sheet.dart';
import 'package:fl_clash/ui/scaffold/scaffold.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// Shows what the panel returned for a payment: a link to open in the browser
/// and the same link as a code, while polling the order until it settles.
Future<void> showStorePaymentSheet(
  BuildContext context, {
  required XboardPayment payment,
  required XboardSession session,
  required String tradeNo,
}) {
  return showNestedSheet<void>(
    context,
    builder: (_) => _PaymentSheet(
      payment: payment,
      session: session,
      tradeNo: tradeNo,
    ),
  );
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({
    required this.payment,
    required this.session,
    required this.tradeNo,
  });

  final XboardPayment payment;
  final XboardSession session;
  final String tradeNo;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  Timer? _poller;
  bool _paid = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _poller = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    _openBrowser();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _openBrowser() async {
    final url = widget.payment.payload;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      await dialogs.openUrl(url);
    }
  }

  Future<void> _poll() async {
    if (_paid || _checking) return;
    _checking = true;
    try {
      final orders = await widget.session.fetchOrders();
      final order = orders.where((item) => item.tradeNo == widget.tradeNo);
      if (order.isNotEmpty && order.first.status >= 1) {
        _poller?.cancel();
        if (!mounted) return;
        setState(() => _paid = true);
        dialogs.showBanner(
          currentAppLocalizations.storePaid,
          level: BannerLevel.success,
        );
      }
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.payment.payload));
    if (!mounted) return;
    dialogs.showBanner(currentAppLocalizations.storeLinkCopied);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = context.colorScheme;
    final payload = widget.payment.payload;
    return Scaffold(
      title: appLocalizations.storePay,
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.sectionsTopPadding,
          bottom: 24 + context.bottomInset,
        ),
        children: [
          if (_paid)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  GlyphIcon(AppGlyphs.checkCircle, size: 56, color: colors.primary),
                  const SizedBox(height: 12),
                  Text(
                    appLocalizations.storePaid,
                    style: AppTextStyle.title3.of(context, emphasized: true),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    appLocalizations.storePaidTip,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                appLocalizations.storePayTip,
                textAlign: TextAlign.center,
                style: AppTextStyle.body
                    .of(context)
                    .copyWith(color: colors.onSurfaceVariant, height: 1.5),
              ),
            ),
            const SizedBox(height: 8),
            if (payload.startsWith('http'))
              FilledButton(
                onPressed: _openBrowser,
                child: Text(appLocalizations.storeOpenPayPage),
              ),
            const SizedBox(height: 12),
            generateSection(
              items: [
                ListItem(
                  title: Text(appLocalizations.storePayLink),
                  subtitle: SelectableText(
                    payload,
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: colors.onSurfaceVariant),
                  ),
                  trailing: TextButton(
                    onPressed: _copy,
                    child: Text(appLocalizations.storeCopyLink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const ActivityIndicator(size: 14),
                const SizedBox(width: 8),
                Text(
                  appLocalizations.storeWaitingPay,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
