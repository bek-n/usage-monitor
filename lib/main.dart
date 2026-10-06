import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/monitor.dart';
import 'src/tray_panel.dart';
import 'src/ui/panel.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final monitor = Monitor();
  final tray = TrayPanel(monitor);

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'Usage Monitor',
      size: Size(TrayPanel.panelWidth, 420),
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      skipTaskbar: true,
    ),
  );
  await windowManager.setResizable(false);

  runApp(UsageMonitorApp(monitor: monitor, tray: tray));

  await monitor.load();
  await tray.init();
  if (monitor.profiles.isEmpty) await tray.showPanel();
  await monitor.start();
}

class UsageMonitorApp extends StatelessWidget {
  const UsageMonitorApp({super.key, required this.monitor, required this.tray});

  final Monitor monitor;
  final TrayPanel tray;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Usage Monitor',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: UsagePanel(monitor: monitor, tray: tray),
    );
  }
}
