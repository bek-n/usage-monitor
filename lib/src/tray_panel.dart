import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'accounts.dart';
import 'edge_panel.dart';
import 'monitor.dart';
import 'usage.dart';

class TrayPanel with TrayListener, WindowListener {
  TrayPanel(this.monitor) {
    edge = EdgePanel(onShown: () => monitor.refreshIfStale());
  }

  /// The Windows runner sends `reopen` when the app is started while it is already running.
  static const _appChannel = MethodChannel('usage_monitor/app');

  static const panelWidth = 380.0;
  static const minPanelHeight = 180.0;
  static const maxPanelHeight = 720.0;

  final Monitor monitor;
  final pinned = ValueNotifier<bool>(false);
  late final EdgePanel edge;
  PanelPlacement? _placement;
  bool _trayVisible = false;
  DateTime _hiddenAt = DateTime(0);
  double _panelHeight = 420;
  double _contentHeight = 420;
  double _roomForDialog = 0;
  String _lastTitle = '';

  /// Set while the panel sits above a bottom taskbar, so that it grows upwards.
  double? _anchoredBottom;

  Future<void> init() async {
    await windowManager.setPreventClose(true);
    if (Platform.isMacOS) await windowManager.setVisibleOnAllWorkspaces(true, visibleOnFullScreen: true);
    edge.listen();
    _appChannel.setMethodCallHandler((call) async {
      if (call.method == 'reopen') await showPanel();
    });
    trayManager.addListener(this);
    windowManager.addListener(this);
    monitor.addListener(_onMonitorChanged);
    pinned.addListener(() {
      windowManager.setAlwaysOnTop(pinned.value);
      edge.setPinned(pinned.value);
    });
    await _onMonitorChanged();
  }

  bool get edgeMode => _placement == PanelPlacement.screenEdge;

  Future<void> _onMonitorChanged() async {
    final placement = Platform.isMacOS ? monitor.settings.placement : PanelPlacement.menuBar;
    if (placement != _placement) {
      final previous = _placement;
      _placement = placement;
      final wasVisible = previous != null && await windowManager.isVisible();
      if (wasVisible) {
        await (previous == PanelPlacement.screenEdge ? edge.hide() : windowManager.hide());
      }
      await edge.setEnabled(edgeMode);
      if (edgeMode && _trayVisible) {
        await trayManager.destroy();
        _trayVisible = false;
        _lastTitle = '';
      } else if (!edgeMode && !_trayVisible) {
        await trayManager.setIcon(
          Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
          isTemplate: true,
        );
        _trayVisible = true;
      }
      if (wasVisible) await showPanel();
    }
    if (_trayVisible) await _syncTray();
  }

  Future<void> _syncTray() async {
    final title = monitor.menuBarTitle;
    if (Platform.isMacOS && title != _lastTitle) {
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
    if (edgeMode) {
      await edge.resize(_panelHeight);
      await edge.show();
      return;
    }
    await windowManager.setSize(Size(panelWidth, _panelHeight));
    await windowManager.setPosition(await _panelPosition());
    await windowManager.show();
    await windowManager.focus();
    await monitor.refreshIfStale();
  }

  Future<Offset> _panelPosition() async {
    _anchoredBottom = null;
    final displays = await screenRetriever.getAllDisplays();
    final tray = await trayManager.getBounds();
    if (Platform.isWindows) return _panelPositionNearTaskbar(displays, tray);
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

  /// Opens next to the tray icon like the system's own flyouts, on whichever edge the taskbar is.
  Future<Offset> _panelPositionNearTaskbar(List<Display> displays, Rect? tray) async {
    final anchor = tray != null && tray.width > 0 ? tray.center : await screenRetriever.getCursorScreenPoint();
    Rect workArea(Display d) => (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size);
    double distance(Rect area) {
      final dx = [area.left - anchor.dx, 0.0, anchor.dx - area.right].reduce((a, b) => a > b ? a : b);
      final dy = [area.top - anchor.dy, 0.0, anchor.dy - area.bottom].reduce((a, b) => a > b ? a : b);
      return dx * dx + dy * dy;
    }

    final area = displays.map(workArea).reduce((a, b) => distance(a) <= distance(b) ? a : b);
    final x = (anchor.dx - panelWidth / 2).clamp(area.left + 12, area.right - panelWidth - 12);
    if (anchor.dy < area.center.dy) return Offset(x, area.top + 12);
    final bottom = _anchoredBottom = area.bottom - 12;
    return Offset(x, bottom - _panelHeight);
  }

  Future<void> hidePanel() async {
    _hiddenAt = DateTime.now();
    if (edgeMode) {
      await edge.hide();
      return;
    }
    await windowManager.hide();
  }

  Future<void> fitContentHeight(double height) async {
    _contentHeight = height;
    final target = (height < _roomForDialog ? _roomForDialog : height)
        .clamp(minPanelHeight, maxPanelHeight)
        .ceilToDouble();
    if ((target - _panelHeight).abs() < 1) return;
    _panelHeight = target;
    if (edgeMode) {
      await edge.resize(target);
    } else if (_anchoredBottom case final bottom?) {
      final position = await windowManager.getPosition();
      await windowManager.setBounds(Rect.fromLTWH(position.dx, bottom - target, panelWidth, target));
    } else {
      await windowManager.setSize(Size(panelWidth, target));
    }
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
    final editor = monitor.editor;
    final accounts = monitor.visibleAccounts;
    await trayManager.setContextMenu(Menu(items: [
      if (editor != null && accounts.isNotEmpty) MenuItem(label: 'Switch ${editor.name} account', disabled: true),
      for (final account in accounts)
        if (editor != null)
          MenuItem.checkbox(
            key: 'switch:${account.id}',
            label: '${account.label} — ${_summary(monitor.usageOf(account))}',
            checked: monitor.isInEditor(account),
            disabled: !monitor.isInEditor(account) && !monitor.canSwitch(account),
          )
        else
          MenuItem(
            label: '${account.label} — ${_summary(monitor.usageOf(account))}',
            disabled: true,
          ),
      if (accounts.isNotEmpty) MenuItem.separator(),
      MenuItem(key: 'open', label: 'Open Usage Monitor'),
      MenuItem(key: 'refresh', label: 'Refresh now'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key ?? '';
    if (key.startsWith('switch:')) {
      final id = key.substring('switch:'.length);
      final account = monitor.visibleAccounts.where((a) => a.id == id).firstOrNull;
      if (account != null && monitor.canSwitch(account)) {
        monitor.switchEditorTo(account).catchError((Object _) {});
      }
      return;
    }
    switch (key) {
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

  @override
  void onWindowMoved() => _anchoredBottom = null;
}
