import 'package:flutter/services.dart';

enum LoginItemStatus { enabled, requiresApproval, notRegistered, notFound, unsupported }

class LoginItem {
  static const _channel = MethodChannel('usage_monitor/login_item');

  Future<LoginItemStatus> status() async => _parse(await _channel.invokeMethod<String>('status'));

  Future<LoginItemStatus> setEnabled(bool enabled) async =>
      _parse(await _channel.invokeMethod<String>('setEnabled', {'enabled': enabled}));

  LoginItemStatus _parse(String? name) => LoginItemStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => LoginItemStatus.notRegistered,
      );
}
