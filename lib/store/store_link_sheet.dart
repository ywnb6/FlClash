import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/ui/nested_sheet.dart';
import 'package:fl_clash/ui/scaffold/scaffold.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// Shows the subscription link the panel issued, so it can be copied, edited
/// or pasted over before the profile is created from it.
/// Shows the link and hands whatever the user confirms straight to
/// [onConfirm]. The sheet is raised from the shop tab, which is not a sheet
/// page, so the result would otherwise be returned to the wrong route.
Future<void> showStoreLinkSheet(
  BuildContext context, {
  required String url,
  required String siteName,
  required Future<void> Function(String link) onConfirm,
}) async {
  await showNestedSheet<void>(
    context,
    builder: (_) => _LinkSheet(
      url: url,
      siteName: siteName,
      onConfirm: onConfirm,
    ),
  );
}

class _LinkSheet extends StatefulWidget {
  const _LinkSheet({
    required this.url,
    required this.siteName,
    required this.onConfirm,
  });

  final String url;
  final String siteName;
  final Future<void> Function(String link) onConfirm;

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  late final _controller = TextEditingController(text: widget.url);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _controller.text.trim()));
    if (!mounted) return;
    dialogs.showBanner(currentAppLocalizations.storeLinkCopied);
  }

  Future<void> _confirm() async {
    final link = _controller.text.trim();
    if (link.isEmpty) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
    await widget.onConfirm(link);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = context.colorScheme;
    return Scaffold(
      title: appLocalizations.storeImportSubscription,
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.sectionsTopPadding,
          bottom: 24 + context.bottomInset,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              widget.siteName,
              style: AppTextStyle.headline.of(context),
            ),
          ),
          generateSection(
            items: [
              ListItem(
                title: Text(appLocalizations.storeSubscribeLink),
                subtitle: FormRowTextField(
                  controller: _controller,
                  hintText: appLocalizations.storeSubscribeLink,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Text(
              appLocalizations.storeLinkTip,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colors.onSurfaceVariant, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _confirm,
            child: Text(appLocalizations.storeImportSubscription),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _copy,
            child: Text(appLocalizations.storeCopyLink),
          ),
        ],
      ),
    );
  }
}
