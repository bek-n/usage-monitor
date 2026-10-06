import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:window_manager/window_manager.dart';

import '../monitor.dart';
import '../tray_panel.dart';
import 'account_card.dart';
import 'dialogs.dart';
import 'format.dart';
import 'theme.dart';

class UsagePanel extends StatelessWidget {
  const UsagePanel({super.key, required this.monitor, required this.tray});

  static const headerHeight = 56.0;

  final Monitor monitor;
  final TrayPanel tray;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([monitor, tray.pinned]),
        builder: (context, _) => Column(
          children: [
            _PanelHeader(monitor: monitor, tray: tray),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: _HeightReporter(
                  onHeight: (h) => tray.fitContentHeight(h + headerHeight + 1),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                    child: _AccountList(monitor: monitor, tray: tray),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.monitor, required this.tray});

  final Monitor monitor;
  final TrayPanel tray;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DragToMoveArea(
      child: SizedBox(
        height: UsagePanel.headerHeight,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Usage limits',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: palette.text),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      monitor.isRefreshing ? 'Refreshing…' : updatedLabel(monitor.lastRefresh),
                      style: TextStyle(fontSize: 11.5, color: palette.muted),
                    ),
                  ],
                ),
              ),
              _HeaderButton(
                tooltip: 'Refresh all',
                onPressed: monitor.isRefreshing ? null : monitor.refreshAll,
                child: monitor.isRefreshing
                    ? SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8, color: palette.muted),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              _HeaderButton(
                tooltip: tray.pinned.value ? 'Unpin (hide when clicking away)' : 'Keep open on top',
                onPressed: () => tray.pinned.value = !tray.pinned.value,
                child: Icon(
                  tray.pinned.value ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  color: tray.pinned.value ? palette.accent : null,
                ),
              ),
              _HeaderButton(
                tooltip: 'Settings',
                onPressed: () => tray.withRoomForDialog(() => showSettingsDialog(context, monitor, onQuit: tray.quit)),
                child: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.tooltip, required this.onPressed, required this.child});

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 18,
        color: context.palette.muted,
        visualDensity: VisualDensity.compact,
        icon: child,
      );
}

class _AccountList extends StatelessWidget {
  const _AccountList({required this.monitor, required this.tray});

  final Monitor monitor;
  final TrayPanel tray;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accounts = monitor.visibleAccounts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final account in accounts) ...[
          AccountCard(key: ValueKey(account.id), monitor: monitor, tray: tray, account: account),
          const SizedBox(height: 10),
        ],
        _AddAccountButton(monitor: monitor, tray: tray),
        if (monitor.profiles.isEmpty && monitor.ready) ...[
          const SizedBox(height: 12),
          Text(
            'Add each Claude account once. Each one gets its own Claude Code profile '
            'in ~/.claude-accounts, so you never have to sign out to check another account.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4, color: palette.muted),
          ),
        ],
      ],
    );
  }
}

class _AddAccountButton extends StatelessWidget {
  const _AddAccountButton({required this.monitor, required this.tray});

  final Monitor monitor;
  final TrayPanel tray;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final result = await tray.withRoomForDialog(() => showAddAccountDialog(context));
        if (result != null) await monitor.addAccount(label: result.label, email: result.email);
      },
      child: CustomPaint(
        painter: _DashedBorderPainter(color: palette.border, radius: 12),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 18, color: palette.muted),
              const SizedBox(width: 6),
              Text(
                'Add account',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.6),
        Radius.circular(radius),
      ));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color || old.radius != radius;
}

class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderHeightReporter renderObject) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
