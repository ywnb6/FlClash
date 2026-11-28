import 'package:fl_clash/common/connectivity_probe.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/scaffold/scaffold.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

class ConnectivityTestView extends StatefulWidget {
  const ConnectivityTestView({super.key});

  @override
  State<ConnectivityTestView> createState() => _ConnectivityTestViewState();
}

class _ConnectivityTestViewState extends State<ConnectivityTestView> {
  static const _probe = ConnectivityProbe();

  final _target = TextEditingController(text: 'www.qualcomm.cn');
  ProbeMethod _method = ProbeMethod.tcp;
  ProbeResult? _result;
  bool _running = false;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _running = true;
      _result = null;
    });
    final result = await _probe.run(
      method: _method,
      input: _target.text,
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = context.colorScheme;
    final result = _result;
    return Scaffold(
      title: appLocalizations.connectivityTest,
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
                title: FormRowTextField(
                  controller: _target,
                  hintText: appLocalizations.connectivityTarget,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  onFieldSubmitted: (_) => _run(),
                ),
              ),
              for (final method in ProbeMethod.values)
                ListItem(
                  title: Text(method.label),
                  trailing: method == _method
                      ? GlyphIcon(
                          AppGlyphs.check,
                          color: colors.primary,
                        )
                      : null,
                  onTap: () => setState(() {
                    _method = method;
                    _result = null;
                  }),
                ),
            ],
          ),
          if (result != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _ResultCard(result: result),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _running ? null : _run,
            child: _running
                ? const ActivityIndicator(size: 16)
                : Text(appLocalizations.connectivityRun),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              appLocalizations.connectivityTip,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colors.onSurfaceVariant, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final ProbeResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final ok = result.ok;
    final tone = ok ? colors.primary : colors.error;
    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result.method.label,
                  style: AppTextStyle.headline.of(context),
                ),
              ),
              Text(
                ok
                    ? '${result.milliseconds ?? 0} ms'
                    : result.outcome.name.toUpperCase(),
                style: AppTextStyle.title3
                    .of(context, emphasized: true)
                    .copyWith(color: tone),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            result.target,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colors.onSurfaceVariant),
          ),
          if (result.detail != null && result.detail!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              result.detail!,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colors.error),
            ),
          ],
        ],
      ),
    );
  }
}
