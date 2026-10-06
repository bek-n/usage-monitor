import 'package:flutter/services.dart';

class EdgePanel {
  EdgePanel({this.onShown});

  static const _channel = MethodChannel('usage_monitor/edge');

  final VoidCallback? onShown;

  void listen() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shown') onShown?.call();
    });
  }

  Future<void> setEnabled(bool enabled) => _invoke('setEnabled', {'enabled': enabled});

  Future<void> setPinned(bool pinned) => _invoke('setPinned', {'pinned': pinned});

  Future<void> show() => _invoke('show');

  Future<void> hide() => _invoke('hide');

  Future<void> resize(double height) => _invoke('resize', {'height': height});

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException catch (_) {}
  }
}
