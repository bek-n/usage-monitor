import 'package:usage_monitor/main.dart';
import 'package:usage_monitor/src/accounts.dart';
import 'package:usage_monitor/src/claude_cli.dart';
import 'package:usage_monitor/src/editor_settings.dart';
import 'package:usage_monitor/src/login_item.dart';
import 'package:usage_monitor/src/monitor.dart';
import 'package:usage_monitor/src/profile_sync.dart';
import 'package:usage_monitor/src/tray_panel.dart';
import 'package:usage_monitor/src/usage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStore extends AccountStore {
  MemoryStore(this.accounts);

  final List<Account> accounts;

  @override
  Future<(List<Account>, MonitorSettings)> load() async => (accounts, const MonitorSettings());

  @override
  Future<void> save(List<Account> accounts, MonitorSettings settings) async {}
}

class FakeCli extends ClaudeCli {
  FakeCli(this.usageById);

  final Map<String, AccountUsage> usageById;

  @override
  Future<String?> detect() async => '/usr/local/bin/claude';

  @override
  Future<AccountUsage> fetchUsage(Account account, {Duration timeout = const Duration(seconds: 30)}) async {
    final usage = usageById[account.id];
    if (usage == null) throw const ClaudeCliException('Claude Code did not answer in time');
    return usage;
  }
}

class FakeLoginItem extends LoginItem {
  LoginItemStatus current = LoginItemStatus.notRegistered;
  final calls = <bool>[];

  @override
  Future<LoginItemStatus> status() async => current;

  @override
  Future<LoginItemStatus> setEnabled(bool enabled) async {
    calls.add(enabled);
    return current = enabled ? LoginItemStatus.enabled : LoginItemStatus.notRegistered;
  }
}

class FakeEditorSettings extends EditorSettings {
  String? dir;
  final writes = <String?>[];

  @override
  Future<List<Editor>> detect() async => [EditorSettings.known.first];

  @override
  Future<String?> configDir(Editor editor) async => dir;

  @override
  Future<void> setConfigDir(Editor editor, String? dir) async {
    writes.add(dir);
    this.dir = dir;
  }
}

class FakeProfileSync extends ProfileSync {
  final shared = <String>[];

  @override
  Future<ShareReport> share(String profileDir) async {
    shared.add(profileDir);
    return ShareReport(ownCopies: profileDir.endsWith('spare') ? const ['settings.json'] : const []);
  }
}

AccountUsage signedIn(String email, double session, double weekly) {
  final now = DateTime.now();
  return AccountUsage(
    loginState: LoginState.signedIn,
    fetchedAt: now,
    email: email,
    plan: 'Pro',
    session: UsageWindow(label: 'Session', percent: session, resetsAt: now.add(const Duration(hours: 2))),
    weekly: UsageWindow(label: 'Weekly', percent: weekly, resetsAt: now.add(const Duration(days: 3))),
  );
}

void main() {
  const work = Account(id: 'work', label: 'Work', configDir: '/tmp/.claude-accounts/work');
  const personal = Account(id: 'personal', label: 'Personal', configDir: '/tmp/.claude-accounts/personal');
  const spare = Account(id: 'spare', label: 'Spare', configDir: '/tmp/.claude-accounts/spare');

  late Monitor monitor;
  late FakeLoginItem loginItem;
  late FakeEditorSettings editorSettings;
  late FakeProfileSync profileSync;

  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (_) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (_) async => null);
    loginItem = FakeLoginItem();
    editorSettings = FakeEditorSettings();
    profileSync = FakeProfileSync();
    monitor = Monitor(
      profileSync: profileSync,
      loginItem: loginItem,
      editorSettings: editorSettings,
      store: MemoryStore([work, personal, spare]),
      cli: FakeCli({
        Account.currentLoginId: signedIn('work@example.com', 71, 23),
        'work': signedIn('work@example.com', 71, 23),
        'personal': signedIn('personal@example.com', 93, 78),
        'spare': AccountUsage(loginState: LoginState.signedOut, fetchedAt: DateTime.now()),
      }),
    );
  });

  tearDown(() => monitor.dispose());

  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(380, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UsageMonitorApp(monitor: monitor, tray: TrayPanel(monitor)));
    await tester.runAsync(monitor.init);
    await tester.pumpAndSettle();
  }

  testWidgets('shows every account and marks the one VS Code uses', (tester) async {
    await pumpPanel(tester);

    expect(find.text('Main login'), findsNothing);
    expect(find.text('In VS Code'), findsOneWidget);
    expect(monitor.isInEditor(work), isTrue);
    expect(find.text('Switch'), findsOneWidget);
    expect(find.text('93%'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(monitor.menuBarTitle, '71% · 93%');
  });

  testWidgets('opens settings', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.byTooltip('Settings'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(find.text('Refresh every'), findsOneWidget);
    expect(find.text('Open at login'), findsOneWidget);
    expect(find.text('Found: /usr/local/bin/claude'), findsOneWidget);
  });

  testWidgets('turns on open-at-login once, on first launch', (tester) async {
    await pumpPanel(tester);

    expect(loginItem.calls, [true]);
    expect(monitor.loginItemStatus, LoginItemStatus.enabled);
    expect(monitor.settings.loginItemSetUp, isTrue);
  });

  testWidgets('switches VS Code to another account and back to the main login', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();

    expect(editorSettings.writes, [personal.configDir]);
    expect(monitor.isInEditor(personal), isTrue);
    expect(monitor.isInEditor(work), isFalse);
    expect(find.text('VS Code now uses Personal. Start a new Claude chat there to use it.'), findsOneWidget);

    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();

    expect(editorSettings.writes, [personal.configDir, null]);
    expect(monitor.isInEditor(work), isTrue);
  });

  testWidgets('shares the main login with every account and flags own copies', (tester) async {
    await pumpPanel(tester);

    expect(profileSync.shared.toSet(), {work.configDir, personal.configDir, spare.configDir});
    expect(monitor.ownCopiesOf(spare), ['settings.json']);
    expect(monitor.ownCopiesOf(work), isEmpty);
  });
}
