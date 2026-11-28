import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/connectivity_probe.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/nested_sheet.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// The bolt's menu: the delay test it always ran, plus the three probes that
/// reach the node itself rather than the URL behind it.
class ProbePicker extends StatelessWidget {
  const ProbePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListItem(
            leading: const GlyphIcon(AppGlyphs.speed),
            title: Text(appLocalizations.delayTest),
            onTap: () => Navigator.of(context).pop(),
          ),
          for (final method in ProbeMethod.values)
            ListItem(
              leading: const GlyphIcon(AppGlyphs.link),
              title: Text(method.label),
              onTap: () => Navigator.of(context).pop(method),
            ),
        ],
      ),
    );
  }
}

class _NodeRow {
  _NodeRow({required this.name, required this.addr});

  final String name;
  final String addr;
  NodeProbeResult? result;
  bool running = false;
}

Future<void> showNodeProbeSheet(
  BuildContext context, {
  required ProbeMethod method,
}) {
  return showNestedSheet<void>(
    context,
    builder: (_) => _NodeProbeSheet(method: method),
  );
}

class _NodeProbeSheet extends StatefulWidget {
  const _NodeProbeSheet({required this.method});

  final ProbeMethod method;

  @override
  State<_NodeProbeSheet> createState() => _NodeProbeSheetState();
}

class _NodeProbeSheetState extends State<_NodeProbeSheet> {
  static const _probe = NodeProbe();

  final List<_NodeRow> _rows = [];
  bool _loading = true;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await coreController.getProxies();
      final rows = <_NodeRow>[];
      for (final raw in data.proxies.values) {
        if (raw is! Map) continue;
        final proxy = Proxy.fromJson(raw.cast<String, Object?>());
        if (proxy.addr.isEmpty) continue;
        if (const {
          'Direct',
          'Reject',
          'Selector',
          'URLTest',
          'Fallback',
          'LoadBalance',
          'Compatible',
          'Pass',
        }.contains(proxy.type)) {
          continue;
        }
        rows.add(_NodeRow(name: proxy.name, addr: proxy.addr));
      }
      rows.sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
        _loading = false;
      });
      await _runAll();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<NodeProbeResult> _measure(_NodeRow row) => switch (widget.method) {
    ProbeMethod.tcp => _probe.tcp(row.addr),
    ProbeMethod.icmp => _probe.icmp(row.addr),
    ProbeMethod.connect => _probe.connect(row.addr),
  };

  Future<void> _runAll() async {
    if (_running) return;
    setState(() => _running = true);
    for (final row in _rows) {
      if (!mounted) return;
      setState(() {
        row.running = true;
        row.result = null;
      });
      final result = await _measure(row);
      if (!mounted) return;
      setState(() {
        row.running = false;
        row.result = result;
      });
    }
    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = context.colorScheme;
    return Scaffold(
      title: appLocalizations.connectivityTest,
      body: Builder(
        builder: (context) {
          if (_loading) {
            return const Center(child: ActivityIndicator());
          }
          if (_error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.body
                      .of(context)
                      .copyWith(color: colors.error),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: context.sectionsTopPadding,
              bottom: 24 + context.bottomInset,
            ),
            itemCount: _rows.length,
            itemBuilder: (_, index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _NodeCard(row: _rows[index]),
            ),
          );
        },
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.row});

  final _NodeRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final result = row.result;
    final Color tone;
    if (result == null || row.running) {
      tone = colors.onSurfaceVariant;
    } else if (result.ok) {
      tone = colors.primary;
    } else {
      tone = colors.error;
    }
    return Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.body.of(context),
                ),
                const SizedBox(height: 2),
                Text(
                  row.addr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (row.running)
            const ActivityIndicator(size: 14)
          else if (result == null)
            Text('—', style: AppTextStyle.body.of(context))
          else if (result.ok)
            Text(
              '${result.milliseconds ?? 0} ms',
              style: AppTextStyle.body.of(context).copyWith(color: tone),
            )
          else
            Text(
              result.outcome.name,
              style: AppTextStyle.caption1.of(context).copyWith(color: tone),
            ),
        ],
      ),
    );
  }
}
