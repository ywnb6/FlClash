import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/connectivity_probe.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
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

class _NodeRow {
  _NodeRow({required this.name, required this.addr});

  final String name;
  final String addr;
  NodeProbeResult? result;
  bool running = false;
}

class _ConnectivityTestViewState extends State<ConnectivityTestView> {
  static const _probe = NodeProbe();

  final List<_NodeRow> _rows = [];
  ProbeMethod _method = ProbeMethod.tcp;
  bool _loading = true;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  Future<void> _loadNodes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await coreController.getProxies();
      final rows = <_NodeRow>[];
      for (final entry in data.proxies.entries) {
        final raw = entry.value;
        if (raw is! Map) continue;
        final proxy = Proxy.fromJson(raw.cast<String, Object?>());
        if (proxy.addr.isEmpty) continue;
        if (proxy.type == 'Direct' || proxy.type == 'Reject') continue;
        if (proxy.type == 'Selector' || proxy.type == 'URLTest') continue;
        if (proxy.type == 'Fallback' || proxy.type == 'LoadBalance') continue;
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<NodeProbeResult> _measure(_NodeRow row) async {
    return switch (_method) {
      ProbeMethod.tcp => _probe.tcp(row.addr),
      ProbeMethod.icmp => _probe.icmp(row.addr),
      ProbeMethod.connect => _probe.connect(row.addr),
    };
  }

  Future<void> _runAll() async {
    if (_running || _rows.isEmpty) return;
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

  Future<void> _runOne(_NodeRow row) async {
    if (_running) return;
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
          return ListView(
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
                    title: Text(appLocalizations.connectivityMethod),
                    subtitle: Text(_method.label),
                    trailing: const GlyphIcon(AppGlyphs.chevronDown),
                    onTap: _pickMethod,
                  ),
                  ListItem(
                    title: Text(appLocalizations.connectivityNodeCount(_rows.length)),
                    trailing: GlyphIcon(
                      AppGlyphs.refresh,
                      color: colors.primary,
                    ),
                    onTap: _runAll,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final row in _rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _NodeCard(
                    row: row,
                    onTap: () => _runOne(row),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickMethod() async {
    final next = await showFloatingDialog<ProbeMethod>(
      context: context,
      child: _MethodPicker(current: _method),
    );
    if (next == null || !mounted) return;
    setState(() {
      _method = next;
      for (final row in _rows) {
        row.result = null;
      }
    });
  }
}

class _MethodPicker extends StatelessWidget {
  const _MethodPicker({required this.current});

  final ProbeMethod current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final method in ProbeMethod.values)
            ListItem(
              title: Text(method.label),
              trailing: method == current
                  ? const GlyphIcon(AppGlyphs.check)
                  : null,
              onTap: () => Navigator.of(context).pop(method),
            ),
        ],
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.row, required this.onTap});

  final _NodeRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final result = row.result;
    final Color tone;
    if (row.running) {
      tone = colors.onSurfaceVariant;
    } else if (result == null) {
      tone = colors.onSurfaceVariant;
    } else if (result.ok) {
      tone = colors.primary;
    } else {
      tone = colors.error;
    }
    return Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: row.running ? null : onTap,
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
              Text(
                '—',
                style: AppTextStyle.body.of(context).copyWith(color: tone),
              )
            else if (result.ok)
              Text(
                '${result.milliseconds ?? 0} ms',
                style: AppTextStyle.body
                    .of(context)
                    .copyWith(color: tone),
              )
            else
              Text(
                result.outcome.name,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: tone),
              ),
          ],
        ),
      ),
    );
  }
}
