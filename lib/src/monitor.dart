import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'claude_cli.dart';
import 'editor_settings.dart';
import 'login_item.dart';
import 'profile_sync.dart';
import 'usage.dart';

class Monitor extends ChangeNotifier {
  Monitor({
    AccountStore? store,
    ClaudeCli? cli,
    LoginItem? loginItem,
    EditorSettings? editorSettings,
    ProfileSync? profileSync,
  })  : store = store ?? AccountStore(),
        cli = cli ?? ClaudeCli(),
        loginItem = loginItem ?? LoginItem(),
        editorSettings = editorSettings ?? EditorSettings(),
        profileSync = profileSync ?? ProfileSync();

  final AccountStore store;
  final ClaudeCli cli;
  final LoginItem loginItem;
  final EditorSettings editorSettings;
  final ProfileSync profileSync;

  List<Account> _profiles = [];
  MonitorSettings _settings = const MonitorSettings();
  final Map<String, AccountUsage> _usage = {};
  final Map<String, String> _errors = {};
  final Set<String> _loading = {};
  final Map<String, Timer> _signInWatchers = {};
  Timer? _refreshTimer;
  Timer? _ticker;
  DateTime? _lastRefresh;
  bool _ready = false;
  LoginItemStatus _loginItemStatus = LoginItemStatus.notRegistered;
  List<Editor> _editors = [];
  final Map<String, List<String>> _ownCopies = {};
  String? _editorConfigDir;

  bool get ready => _ready;
  MonitorSettings get settings => _settings;
  List<Account> get profiles => List.unmodifiable(_profiles);
  DateTime? get lastRefresh => _lastRefresh;
  bool get isRefreshing => _loading.isNotEmpty;
  LoginItemStatus get loginItemStatus => _loginItemStatus;

  AccountUsage? usageOf(Account account) => _usage[account.id];
  String? errorOf(Account account) => _errors[account.id];
  bool isLoading(Account account) => _loading.contains(account.id);
  bool isWaitingForSignIn(Account account) => _signInWatchers.containsKey(account.id);

  String? get _currentLoginEmail => _usage[Account.currentLoginId]?.email;

  bool _matchesMainLogin(Account account) {
    if (account.isCurrentLogin) return false;
    final email = _usage[account.id]?.email;
    return email != null && email == _currentLoginEmail;
  }

  Editor? get editor => _editors.isEmpty ? null : _editors.first;

  List<String> ownCopiesOf(Account account) => _ownCopies[account.id] ?? const [];

  Future<void> _shareProfiles([Iterable<Account>? accounts]) async {
    if (!_settings.shareWithMain) {
      _ownCopies.clear();
      return;
    }
    for (final account in accounts ?? _profiles) {
      try {
        final report = await profileSync.share(account.configDir);
        _ownCopies[account.id] = report.ownCopies;
      } on FileSystemException catch (_) {}
    }
  }

  bool isInEditor(Account account) {
    if (editor == null) return false;
    final dir = _editorConfigDir;
    if (dir == null) return account.isCurrentLogin || _matchesMainLogin(account);
    return !account.isCurrentLogin && _samePath(account.configDir, dir);
  }

  bool canSwitch(Account account) =>
      editor != null &&
      _usage[account.id]?.loginState == LoginState.signedIn &&
      !isInEditor(account);

  Future<void> switchEditorTo(Account account) async {
    final target = account.isCurrentLogin || _matchesMainLogin(account) ? null : account.configDir;
    for (final e in _editors) {
      await editorSettings.setConfigDir(e, target);
    }
    _editorConfigDir = target;
    notifyListeners();
  }

  Future<void> _loadEditorState() async {
    try {
      _editors = await editorSettings.detect();
      final primary = editor;
      _editorConfigDir = primary == null ? null : await editorSettings.configDir(primary);
    } on FileSystemException catch (_) {
    } on FormatException catch (_) {}
  }

  static bool _samePath(String a, String b) {
    String clean(String p) => p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    return clean(a) == clean(b);
  }

  List<Account> get _polledAccounts => [Account.currentLogin, ..._profiles];

  List<Account> get visibleAccounts {
    final showCurrent = _settings.showCurrentLogin && !_profiles.any(_matchesMainLogin);
    return [if (showCurrent) Account.currentLogin, ..._profiles];
  }

  String get menuBarTitle {
    final parts = [
      for (final account in visibleAccounts)
        if (_usage[account.id]?.session case final session?) '${session.currentPercent.round()}%',
    ];
    return parts.join(' · ');
  }

  Future<void> init() async {
    final (profiles, settings) = await store.load();
    _profiles = profiles;
    _settings = settings;
    cli.overridePath = settings.claudeBinary;
    await _setUpLoginItem();
    await _loadEditorState();
    await _shareProfiles();
    _ready = true;
    notifyListeners();
    _scheduleRefresh();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    await refreshAll();
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      Duration(minutes: _settings.refreshMinutes),
      (_) => refreshAll(),
    );
  }

  void _tick() {
    for (final account in _polledAccounts) {
      final usage = _usage[account.id];
      if (usage == null || _loading.contains(account.id)) continue;
      final nextReset = usage.nextReset;
      if (nextReset != null && DateTime.now().isAfter(nextReset)) refresh(account);
    }
    notifyListeners();
  }

  Future<void> refreshIfStale({Duration maxAge = const Duration(minutes: 1)}) async {
    final last = _lastRefresh;
    if (last == null || DateTime.now().difference(last) > maxAge) await refreshAll();
  }

  Future<void> refreshAll() async {
    await _loadEditorState();
    await _shareProfiles();
    await Future.wait(_polledAccounts.map(refresh));
    _lastRefresh = DateTime.now();
    notifyListeners();
  }

  Future<void> refresh(Account account) async {
    if (!_loading.add(account.id)) return;
    notifyListeners();
    try {
      _usage[account.id] = await cli.fetchUsage(account);
      _errors.remove(account.id);
      if (_usage[account.id]!.loginState != LoginState.signedOut) {
        _signInWatchers.remove(account.id)?.cancel();
      }
    } catch (error) {
      _errors[account.id] = error.toString();
    } finally {
      _loading.remove(account.id);
      notifyListeners();
    }
  }

  Future<Account> addAccount({required String label, String? email}) async {
    final account = await store.createProfile(label: label, email: email);
    _profiles = [..._profiles, account];
    await _save();
    await _shareProfiles([account]);
    notifyListeners();
    await signIn(account);
    return account;
  }

  Future<void> signIn(Account account) async {
    await cli.openSignIn(account);
    _signInWatchers.remove(account.id)?.cancel();
    final startedAt = DateTime.now();
    _signInWatchers[account.id] = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (DateTime.now().difference(startedAt) > const Duration(minutes: 5)) {
        timer.cancel();
        _signInWatchers.remove(account.id);
        notifyListeners();
        return;
      }
      refresh(account);
    });
    notifyListeners();
  }

  Future<void> signOut(Account account) async {
    await cli.signOut(account);
    await refresh(account);
  }

  Future<void> rename(Account account, String label) async {
    _profiles = [
      for (final p in _profiles) p.id == account.id ? p.copyWith(label: label) : p,
    ];
    await _save();
    notifyListeners();
  }

  Future<void> remove(Account account) async {
    _signInWatchers.remove(account.id)?.cancel();
    if (account.isManagedProfile) {
      try {
        await cli.signOut(account);
      } catch (_) {}
      await store.deleteProfileDir(account);
    }
    _profiles = _profiles.where((p) => p.id != account.id).toList();
    _usage.remove(account.id);
    _errors.remove(account.id);
    await _save();
    notifyListeners();
  }

  Future<void> move(int from, int to) async {
    final list = [..._profiles];
    final item = list.removeAt(from);
    list.insert(to, item);
    _profiles = list;
    await _save();
    notifyListeners();
  }

  Future<void> updateSettings(MonitorSettings settings) async {
    final intervalChanged = settings.refreshMinutes != _settings.refreshMinutes;
    final binaryChanged = settings.claudeBinary != _settings.claudeBinary;
    final sharingTurnedOn = settings.shareWithMain && !_settings.shareWithMain;
    _settings = settings;
    if (sharingTurnedOn || !settings.shareWithMain) await _shareProfiles();
    cli.overridePath = settings.claudeBinary;
    await _save();
    if (intervalChanged) _scheduleRefresh();
    notifyListeners();
    if (binaryChanged) await refreshAll();
  }

  Future<void> _setUpLoginItem() async {
    try {
      if (_settings.loginItemSetUp) {
        _loginItemStatus = await loginItem.status();
        return;
      }
      _loginItemStatus = await loginItem.setEnabled(true);
      _settings = _settings.copyWith(loginItemSetUp: true);
      await _save();
    } on PlatformException catch (_) {
      _loginItemStatus = LoginItemStatus.notRegistered;
    } on MissingPluginException catch (_) {
      _loginItemStatus = LoginItemStatus.unsupported;
    }
  }

  Future<void> setOpenAtLogin(bool enabled) async {
    _loginItemStatus = await loginItem.setEnabled(enabled);
    notifyListeners();
  }

  Future<void> _save() => store.save(_profiles, _settings);

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _ticker?.cancel();
    for (final timer in _signInWatchers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
