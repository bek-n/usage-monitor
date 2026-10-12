import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'accounts.dart';
import 'paths.dart';
import 'usage.dart';

class ClaudeCliException implements Exception {
  const ClaudeCliException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ClaudeCli {
  ClaudeCli({this.overridePath});

  String? overridePath;

  static final _home = homeDir;
  static final _exe = Platform.isWindows ? '.exe' : '';

  static const _streamArgs = [
    '--output-format',
    'stream-json',
    '--verbose',
    '--input-format',
    'stream-json',
    '--settings',
    '{"disableAllHooks":true}',
  ];

  Future<String> locate() async {
    final override = overridePath;
    if (override != null && override.isNotEmpty) {
      if (await File(override).exists()) return override;
      throw ClaudeCliException('Claude Code not found at $override');
    }
    final detected = await detect();
    if (detected != null) return detected;
    throw const ClaudeCliException(
      'Claude Code not found. Install the CLI or the VS Code extension, '
      'or set its path in Settings.',
    );
  }

  Future<String?> detect() async {
    final candidates = Platform.isWindows
        ? [
            '$_home/.local/bin/claude.exe',
            '$_home/.claude/local/claude.exe',
            for (final dir in (Platform.environment['PATH'] ?? '').split(';'))
              if (dir.isNotEmpty) ...['$dir/claude.exe', '$dir/claude.cmd'],
            '${Platform.environment['APPDATA']}/npm/claude.cmd',
          ]
        : [
            '$_home/.local/bin/claude',
            '$_home/.claude/local/claude',
            '/opt/homebrew/bin/claude',
            '/usr/local/bin/claude',
            '$_home/.npm-global/bin/claude',
          ];
    for (final path in candidates.map(nativePath)) {
      if (await File(path).exists()) return path;
    }

    final bundled = <(List<int>, String)>[];
    for (final editor in ['.vscode', '.vscode-insiders', '.cursor', '.windsurf']) {
      final dir = Directory(nativePath('$_home/$editor/extensions'));
      if (!await dir.exists()) continue;
      await for (final entry in dir.list()) {
        final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final match = RegExp(r'^anthropic\.claude-code-(\d+)\.(\d+)\.(\d+)').firstMatch(name);
        if (match == null) continue;
        final binary = nativePath('${entry.path}/resources/native-binary/claude$_exe');
        if (await File(binary).exists()) {
          bundled.add(([for (var i = 1; i <= 3; i++) int.parse(match[i]!)], binary));
        }
      }
    }
    if (bundled.isEmpty) return null;
    bundled.sort((a, b) => _compareVersions(b.$1, a.$1));
    return bundled.first.$2;
  }

  Map<String, String> _environmentFor(Account account) {
    final env = Map<String, String>.of(Platform.environment)..remove('CLAUDE_CONFIG_DIR');
    if (!account.isCurrentLogin) env['CLAUDE_CONFIG_DIR'] = account.configDir;
    return env;
  }

  Future<AccountUsage> fetchUsage(
    Account account, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final binary = await locate();
    final workDir = Directory.systemTemp.path;
    final process = await Process.start(
      binary,
      _streamArgs,
      environment: _environmentFor(account),
      includeParentEnvironment: false,
      workingDirectory: workDir,
      runInShell: _needsShell(binary),
    );

    final responses = <String, Map<String, dynamic>>{};
    final done = Completer<void>();
    final stderrText = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(stderrText.write);

    final subscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final Object? message;
      try {
        message = jsonDecode(line);
      } on FormatException {
        return;
      }
      if (message is! Map || message['type'] != 'control_response') return;
      final response = message['response'];
      if (response is! Map) return;
      final requestId = response['request_id'] as String?;
      if (requestId == null) return;
      if (response['subtype'] == 'error') {
        if (!done.isCompleted) {
          done.completeError(ClaudeCliException('${response['error']}'));
        }
        return;
      }
      responses[requestId] = Map<String, dynamic>.from(response['response'] as Map? ?? {});
      if (responses.containsKey('init') && responses.containsKey('usage') && !done.isCompleted) {
        done.complete();
      }
    });

    unawaited(process.exitCode.then((code) {
      if (!done.isCompleted) {
        final detail = stderrText.toString().trim();
        done.completeError(ClaudeCliException(
          detail.isEmpty ? 'Claude Code exited with code $code' : detail.split('\n').last,
        ));
      }
    }));

    void send(String id, Map<String, dynamic> request) {
      process.stdin.writeln(jsonEncode({
        'type': 'control_request',
        'request_id': id,
        'request': request,
      }));
    }

    try {
      send('init', {'subtype': 'initialize'});
      send('usage', {'subtype': 'get_usage', 'skip_behaviors': true});
      await process.stdin.flush();
      await done.future.timeout(
        timeout,
        onTimeout: () => throw const ClaudeCliException('Claude Code did not answer in time'),
      );
      return AccountUsage.fromControlResponses(
        initialize: responses['init']!,
        usage: responses['usage']!,
      );
    } finally {
      await subscription.cancel();
      await _kill(process);
    }
  }

  /// npm installs Claude Code on Windows as a .cmd script, which only cmd can run.
  static bool _needsShell(String binary) =>
      Platform.isWindows && RegExp(r'\.(cmd|bat)$', caseSensitive: false).hasMatch(binary);

  /// On Windows, kill() ends only the process itself and leaves anything it started running.
  static Future<void> _kill(Process process) async {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/pid', '${process.pid}', '/t', '/f']);
    } else {
      process.kill();
    }
  }

  Future<void> openSignIn(Account account) async {
    final binary = await locate();
    if (Platform.isWindows) return _openSignInWindows(account, binary);
    final script = File('${Directory.systemTemp.path}/claude-sign-in-${account.id}.command');
    final emailArg = account.email == null ? '' : ' --email ${_quote(account.email!)}';
    final configLine = account.isCurrentLogin
        ? 'unset CLAUDE_CONFIG_DIR'
        : 'export CLAUDE_CONFIG_DIR=${_quote(account.configDir)}';
    await script.writeAsString('''
#!/bin/zsh
clear
echo "Signing in: ${account.label.replaceAll('"', "'")}"
echo "Profile:    ${account.shortConfigDir}"
echo
echo "Your browser will open. Sign in there with the account you want for this profile."
echo "If the browser is already signed in to a different account, sign out there first,"
echo "or copy the link below into a private window."
echo
$configLine
${_quote(binary)} auth login --claudeai$emailArg
echo
echo "Done. You can close this window; Usage Monitor refreshes on its own."
''');
    await Process.run('chmod', ['+x', script.path]);
    await Process.run('open', ['-a', 'Terminal', script.path]);
  }

  Future<void> _openSignInWindows(Account account, String binary) async {
    final script = File(nativePath('${Directory.systemTemp.path}/claude-sign-in-${account.id}.ps1'));
    final emailArg = account.email == null ? '' : ' --email ${_psQuote(account.email!)}';
    final configLine = account.isCurrentLogin
        ? 'Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue'
        : '\$env:CLAUDE_CONFIG_DIR = ${_psQuote(account.configDir)}';
    final content = '''
\$Host.UI.RawUI.WindowTitle = 'Claude sign-in'
Clear-Host
Write-Host ${_psQuote('Signing in: ${account.label}')}
Write-Host ${_psQuote('Profile:    ${account.shortConfigDir}')}
Write-Host ''
Write-Host 'Your browser will open. Sign in there with the account you want for this profile.'
Write-Host 'If the browser is already signed in to a different account, sign out there first,'
Write-Host 'or copy the link below into a private window.'
Write-Host ''
$configLine
& ${_psQuote(binary)} auth login --claudeai$emailArg
Write-Host ''
Write-Host 'Done. You can close this window; Usage Monitor refreshes on its own.'
Read-Host 'Press Enter to close' | Out-Null
''';
    // The byte order mark makes Windows PowerShell read the script as UTF-8.
    await script.writeAsString('\uFEFF$content');
    await Process.start(
      'cmd',
      ['/c', 'start', 'Claude sign-in', 'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script.path],
      mode: ProcessStartMode.detached,
    );
  }

  Future<void> signOut(Account account) async {
    final binary = await locate();
    await Process.run(
      binary,
      ['auth', 'logout'],
      environment: _environmentFor(account),
      includeParentEnvironment: false,
      workingDirectory: Directory.systemTemp.path,
      runInShell: _needsShell(binary),
    );
  }

  String terminalCommand(Account account) {
    if (account.isCurrentLogin) return 'claude';
    if (Platform.isWindows) return '\$env:CLAUDE_CONFIG_DIR = ${_psQuote(account.configDir)}; claude';
    final dir = RegExp(r'^[\w./~-]+$').hasMatch(account.shortConfigDir)
        ? account.shortConfigDir
        : _quote(account.configDir);
    return 'CLAUDE_CONFIG_DIR=$dir claude';
  }

  static String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  /// PowerShell also treats curly single quotes as quotes.
  static String _psQuote(String value) =>
      "'${value.replaceAllMapped(RegExp("['\u2018\u2019\u201A\u201B]"), (m) => '${m[0]}${m[0]}')}'";

  static int _compareVersions(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      final diff = a[i].compareTo(b[i]);
      if (diff != 0) return diff;
    }
    return 0;
  }
}
