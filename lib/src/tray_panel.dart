import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'monitor.dart';
import 'usage.dart';

class TrayPanel with TrayListener, WindowListener {
  TrayPanel(this.monitor);

  static const panelWidth = 380.0;
  static const minPanelHeight = 180.0;
  static const maxPanelHeight = 720.0;

  final Monitor monitor;
  final pinned = ValueNotifier<bool>(false);
  DateTime _hiddenAt = DateTime(0);
  double _panelHeight = 420;
  double _contentHeight = 420;
  double _roomForDialog = 0;
  String _lastTitle = '';

  Future<void> init() async {
    await windowManager.setPreventClose(true);
    await windowManager.setVisibleOnAllWorkspaces(true, visibleOnFullScreen: true);
    await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
    trayManager.addListener(this);
    windowManager.addListener(this);
    monitor.addListener(_syncTray);
    pinned.addListener(() => windowManager.setAlwaysOnTop(pinned.value));
    await _syncTray();
  }

  Future<void> _syncTray() async {
    final title = monitor.menuBarTitle;
    if (title != _lastTitle) {
      _lastTitle = title;
      await trayManager.setTitle(title.isEmpty ? '' : ' $title');
    }
    final lines = [
      for (final account in monitor.visibleAccounts)
        '${account.label}: ${_summary(monitor.usageOf(account))}',
    ];
    await trayManager.setToolTip(lines.isEmpty ? 'Usage Monitor' : lines.join('\n'));
  }

  String _summary(AccountUsage? usage) {
    if (usage == null) return '…';
    return switch (usage.loginState) {
      LoginState.signedOut => 'not signed in',
      LoginState.noPlanLimits => 'no plan limits',
      LoginState.signedIn => [
          for (final w in [usage.session, usage.weekly].whereType<UsageWindow>())
            '${w.label.toLowerCase()} ${w.currentPercent.round()}%',
        ].join(', '),
    };
  }

  Future<void> togglePanel() async {
    final justHidden = DateTime.now().difference(_hiddenAt) < const Duration(milliseconds: 350);
    if (await windowManager.isVisible() || justHidden) {
      await hidePanel();
    } else {
      await showPanel();
    }
  }

  Future<void> showPanel() async {
    await windowManager.setSize(Size(panelWidth, _panelHeight));
    await windowManager.setPosition(await _panelPosition());
    await windowManager.show();
    await windowManager.focus();
    await monitor.refreshIfStale();
  }

  Future<Offset> _panelPosition() async {
    final displays = await screenRetriever.getAllDisplays();
    final tray = await trayManager.getBounds();
    if (tray != null && tray.width > 0) {
      for (final display in displays) {
        final top = display.visiblePosition?.dy ?? 0;
        final left = display.visiblePosition?.dx ?? 0;
        final width = display.size.width;
        final onThisDisplay = tray.center.dx >= left && tray.center.dx <= left + width;
        if (onThisDisplay && (tray.top - top).abs() < 60) {
          final x = (tray.center.dx - panelWidth / 2).clamp(left + 8, left + width - panelWidth - 8);
          return Offset(x, tray.bottom + 6);
        }
      }
    }
    final cursor = await screenRetriever.getCursorScreenPoint();
    final display = displays.firstWhere(
      (d) {
        final origin = d.visiblePosition ?? Offset.zero;
        final size = d.visibleSize ?? d.size;
        return (origin & size).contains(cursor);
      },
      orElse: () => displays.first,
    );
    final origin = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    return Offset(origin.dx + size.width - panelWidth - 12, origin.dy + 8);
  }

  Future<void> hidePanel() async {
    _hiddenAt = DateTime.now();
    await windowManager.hide();
  }

  Future<void> fitContentHeight(double height) async {
    _contentHeight = height;
    final target = (height < _roomForDialog ? _roomForDialog : height)
        .clamp(minPanelHeight, maxPanelHeight)
        .ceilToDouble();
    if ((target - _panelHeight).abs() < 1) return;
    _panelHeight = target;
    await windowManager.setSize(Size(panelWidth, target));
  }

  Future<T> withRoomForDialog<T>(Future<T> Function() openDialog, {double height = 560}) async {
    _roomForDialog = height;
    await fitContentHeight(_contentHeight);
    try {
      return await openDialog();
    } finally {
      _roomForDialog = 0;
      await fitContentHeight(_contentHeight);
    }
  }

  Future<void> quit() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onTrayIconMouseDown() => togglePanel();

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.setContextMenu(Menu(items: [
      for (final account in monitor.visibleAccounts)
        MenuItem(
          label: '${account.label} — ${_summary(monitor.usageOf(account))}',
          disabled: true,
        ),
      if (monitor.visibleAccounts.isNotEmpty) MenuItem.separator(),
      MenuItem(key: 'open', label: 'Open Usage Monitor'),
      MenuItem(key: 'refresh', label: 'Refresh now'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        showPanel();
      case 'refresh':
        monitor.refreshAll();
      case 'quit':
        quit();
    }
  }

  @override
  void onWindowBlur() {
    if (!pinned.value) hidePanel();
  }

  @override
  void onWindowClose() => hidePanel();
}
