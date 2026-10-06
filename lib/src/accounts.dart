import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Account {
  const Account({
    required this.id,
    required this.label,
    required this.configDir,
    this.email,
  });

  static const currentLoginId = 'current-login';

  static final currentLogin = Account(
    id: currentLoginId,
    label: 'Main login',
    configDir: '${Platform.environment['HOME']}/.claude',
  );

  final String id;
  final String label;
  final String configDir;
  final String? email;

  bool get isCurrentLogin => id == currentLoginId;

  bool get isManagedProfile => configDir.startsWith('${AccountStore.profilesRoot}/');

  String get shortConfigDir {
    final home = Platform.environment['HOME'] ?? '';
    return home.isNotEmpty && configDir.startsWith(home)
        ? '~${configDir.substring(home.length)}'
        : configDir;
  }

  Account copyWith({String? label}) =>
      Account(id: id, label: label ?? this.label, configDir: configDir, email: email);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'configDir': configDir,
        if (email != null) 'email': email,
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        label: json['label'] as String,
        configDir: json['configDir'] as String,
        email: json['email'] as String?,
      );
}

enum PanelPlacement { menuBar, screenEdge }

class MonitorSettings {
  const MonitorSettings({
    this.refreshMinutes = 5,
    this.claudeBinary,
    this.showCurrentLogin = true,
    this.loginItemSetUp = false,
    this.shareWithMain = true,
    this.placement = PanelPlacement.menuBar,
  });

  final int refreshMinutes;
  final String? claudeBinary;
  final bool showCurrentLogin;
  final bool loginItemSetUp;
  final bool shareWithMain;
  final PanelPlacement placement;

  MonitorSettings copyWith({
    int? refreshMinutes,
    String? Function()? claudeBinary,
    bool? showCurrentLogin,
    bool? loginItemSetUp,
    bool? shareWithMain,
    PanelPlacement? placement,
  }) =>
      MonitorSettings(
        refreshMinutes: refreshMinutes ?? this.refreshMinutes,
        claudeBinary: claudeBinary != null ? claudeBinary() : this.claudeBinary,
        showCurrentLogin: showCurrentLogin ?? this.showCurrentLogin,
        loginItemSetUp: loginItemSetUp ?? this.loginItemSetUp,
        shareWithMain: shareWithMain ?? this.shareWithMain,
        placement: placement ?? this.placement,
      );

  Map<String, dynamic> toJson() => {
        'refreshMinutes': refreshMinutes,
        if (claudeBinary != null) 'claudeBinary': claudeBinary,
        'showCurrentLogin': showCurrentLogin,
        'loginItemSetUp': loginItemSetUp,
        'shareWithMain': shareWithMain,
        'placement': placement.name,
      };

  factory MonitorSettings.fromJson(Map<String, dynamic> json) => MonitorSettings(
        refreshMinutes: (json['refreshMinutes'] as num?)?.toInt() ?? 5,
        claudeBinary: json['claudeBinary'] as String?,
        showCurrentLogin: json['showCurrentLogin'] as bool? ?? true,
        loginItemSetUp: json['loginItemSetUp'] as bool? ?? false,
        shareWithMain: json['shareWithMain'] as bool? ?? true,
        placement: PanelPlacement.values.asNameMap()[json['placement']] ?? PanelPlacement.menuBar,
      );
}

class AccountStore {
  static final profilesRoot = '${Platform.environment['HOME']}/.claude-accounts';

  File? _file;

  Future<File> _stateFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return _file = File('${dir.path}/accounts.json');
  }

  Future<(List<Account>, MonitorSettings)> load() async {
    final file = await _stateFile();
    if (!await file.exists()) return (<Account>[], const MonitorSettings());
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final accounts = (json['accounts'] as List? ?? [])
          .map((e) => Account.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final settings = MonitorSettings.fromJson(
        Map<String, dynamic>.from(json['settings'] as Map? ?? {}),
      );
      return (accounts, settings);
    } on FormatException {
      return (<Account>[], const MonitorSettings());
    }
  }

  Future<void> save(List<Account> accounts, MonitorSettings settings) async {
    final file = await _stateFile();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'accounts': accounts.map((a) => a.toJson()).toList(),
      'settings': settings.toJson(),
    }));
    await tmp.rename(file.path);
  }

  Future<Account> createProfile({required String label, String? email}) async {
    final base = _slug(label);
    var slug = base;
    var n = 2;
    while (await Directory('$profilesRoot/$slug').exists()) {
      slug = '$base-${n++}';
    }
    final dir = Directory('$profilesRoot/$slug');
    await dir.create(recursive: true);
    return Account(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      label: label,
      configDir: dir.path,
      email: email,
    );
  }

  Future<void> deleteProfileDir(Account account) async {
    if (!account.isManagedProfile) return;
    final dir = Directory(account.configDir);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  String _slug(String label) {
    final slug = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'account' : slug;
  }
}
