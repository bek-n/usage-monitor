import 'dart:io';

import 'package:flutter/services.dart';

enum LoginItemStatus { enabled, requiresApproval, notRegistered, notFound, unsupported }

class LoginItem {
  static const _channel = MethodChannel('usage_monitor/login_item');
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _runValue = 'Usage Monitor';

  Future<LoginItemStatus> status() async {
    if (Platform.isWindows) {
      final result = await Process.run('reg', ['query', _runKey, '/v', _runValue]);
      return result.exitCode == 0 ? LoginItemStatus.enabled : LoginItemStatus.notRegistered;
    }
    return _parse(await _channel.invokeMethod<String>('status'));
  }

  Future<LoginItemStatus> setEnabled(bool enabled) async {
    if (Platform.isWindows) {
      final result = await Process.run('reg', [
        if (enabled) ...['add', _runKey, '/v', _runValue, '/t', 'REG_SZ', '/d', '"${Platform.resolvedExecutable}"', '/f']
        else ...['delete', _runKey, '/v', _runValue, '/f'],
      ]);
      if (enabled && result.exitCode != 0) {
        throw PlatformException(code: 'login_item', message: '${result.stderr}'.trim());
      }
      return status();
    }
    return _parse(await _channel.invokeMethod<String>('setEnabled', {'enabled': enabled}));
  }

  LoginItemStatus _parse(String? name) => LoginItemStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => LoginItemStatus.notRegistered,
      );
}
