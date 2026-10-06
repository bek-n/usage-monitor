import 'package:usage_monitor/main.dart';
import 'package:usage_monitor/src/accounts.dart';
import 'package:usage_monitor/src/claude_cli.dart';
import 'package:usage_monitor/src/monitor.dart';
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

  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (_) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (_) async => null);
    monitor = Monitor(
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

  testWidgets('shows every account and marks the one Claude Code uses', (tester) async {
    await pumpPanel(tester);

    expect(find.text('Current login'), findsNothing);
    expect(find.text('In Claude Code'), findsOneWidget);
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
    expect(find.text('Found: /usr/local/bin/claude'), findsOneWidget);
  });
}
