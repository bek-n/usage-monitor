import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'accounts.dart';
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

  static final _home = Platform.environment['HOME'] ?? '';

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
    for (final path in [
      '$_home/.local/bin/claude',
      '$_home/.claude/local/claude',
      '/opt/homebrew/bin/claude',
      '/usr/local/bin/claude',
      '$_home/.npm-global/bin/claude',
    ]) {
      if (await File(path).exists()) return path;
    }

    final bundled = <(List<int>, String)>[];
    for (final editor in ['.vscode', '.vscode-insiders', '.cursor', '.windsurf']) {
      final dir = Directory('$_home/$editor/extensions');
      if (!await dir.exists()) continue;
      await for (final entry in dir.list()) {
        final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final match = RegExp(r'^anthropic\.claude-code-(\d+)\.(\d+)\.(\d+)').firstMatch(name);
        if (match == null) continue;
        final binary = '${entry.path}/resources/native-binary/claude';
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
      process.kill();
    }
  }

  Future<void> openSignIn(Account account) async {
    final binary = await locate();
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

  Future<void> signOut(Account account) async {
    final binary = await locate();
    await Process.run(
      binary,
      ['auth', 'logout'],
      environment: _environmentFor(account),
      includeParentEnvironment: false,
      workingDirectory: Directory.systemTemp.path,
    );
  }

  String terminalCommand(Account account) {
    if (account.isCurrentLogin) return 'claude';
    final dir = RegExp(r'^[\w./~-]+$').hasMatch(account.shortConfigDir)
        ? account.shortConfigDir
        : _quote(account.configDir);
    return 'CLAUDE_CONFIG_DIR=$dir claude';
  }

  static String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  static int _compareVersions(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      final diff = a[i].compareTo(b[i]);
      if (diff != 0) return diff;
    }
    return 0;
  }
}
