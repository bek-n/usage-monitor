import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:usage_monitor/src/editor_settings.dart';
import 'package:usage_monitor/src/jsonc.dart';

void main() {
  late Directory home;
  late EditorSettings settings;
  const vscode = Editor(name: 'VS Code', supportFolder: 'Code', dotFolder: '.vscode');

  File file() => settings.settingsFile(vscode);

  setUp(() async {
    home = await Directory.systemTemp.createTemp('usage_monitor_test');
    settings = EditorSettings(home: home.path);
    await Directory('${home.path}/.vscode/extensions/anthropic.claude-code-2.1.289-darwin-arm64')
        .create(recursive: true);
  });

  tearDown(() => home.delete(recursive: true));

  test('detects editors that have Claude Code installed', () async {
    await Directory('${home.path}/.cursor/extensions/someone.other-1.0.0').create(recursive: true);
    expect((await settings.detect()).map((e) => e.name), ['VS Code']);
  });

  test('adds the setting and keeps comments, URLs in strings and trailing commas', () async {
    await file().create(recursive: true);
    await file().writeAsString('''
{
  // editor
  "editor.fontSize": 13,
  "http.proxy": "http://example.com//path", /* keep */
  "workbench.colorTheme": "Default Dark Modern",
}
''');

    await settings.setConfigDir(vscode, '/Users/me/.claude-accounts/work');
    final text = await file().readAsString();

    expect(text, contains('// editor'));
    expect(text, contains('/* keep */'));
    expect(text, contains('"http.proxy": "http://example.com//path"'));
    expect(await settings.configDir(vscode), '/Users/me/.claude-accounts/work');
    expect((Jsonc.decode(text) as Map)['editor.fontSize'], 13);
    expect(File('${file().path}.usage-monitor-backup').existsSync(), isTrue);
  });

  test('switches between accounts and back to the main login, keeping other variables', () async {
    await file().create(recursive: true);
    await file().writeAsString('''
{
\t"claudeCode.environmentVariables": [
\t\t{ "name": "HTTPS_PROXY", "value": "http://proxy:8080" },
\t],
\t"editor.tabSize": 2
}
''');

    await settings.setConfigDir(vscode, '/a/1');
    expect(await settings.configDir(vscode), '/a/1');
    await settings.setConfigDir(vscode, '/a/2');
    expect(await settings.configDir(vscode), '/a/2');

    final decoded = Jsonc.decode(await file().readAsString()) as Map;
    expect(decoded['editor.tabSize'], 2);
    expect(decoded[EditorSettings.settingKey], [
      {'name': 'HTTPS_PROXY', 'value': 'http://proxy:8080'},
      {'name': 'CLAUDE_CONFIG_DIR', 'value': '/a/2'},
    ]);
    expect(await file().readAsString(), contains('\t"claudeCode.environmentVariables": [\n\t\t{'));

    await settings.setConfigDir(vscode, null);
    expect(await settings.configDir(vscode), isNull);
    expect((Jsonc.decode(await file().readAsString()) as Map)[EditorSettings.settingKey], [
      {'name': 'HTTPS_PROXY', 'value': 'http://proxy:8080'},
    ]);
  });

  test('creates the settings file when there is none, and leaves it alone for the main login', () async {
    await settings.setConfigDir(vscode, null);
    expect(file().existsSync(), isFalse);

    await settings.setConfigDir(vscode, '/a/1');
    expect(await settings.configDir(vscode), '/a/1');
  });

  test('handles an empty object', () async {
    await file().create(recursive: true);
    await file().writeAsString('{}');
    await settings.setConfigDir(vscode, '/a/1');
    expect(await settings.configDir(vscode), '/a/1');
  });

  test('refuses to touch a file that is not a JSON object', () async {
    await file().create(recursive: true);
    await file().writeAsString('[1, 2]');
    await expectLater(settings.setConfigDir(vscode, '/a/1'), throwsFormatException);
    expect(await file().readAsString(), '[1, 2]');
  });

  test('switching to an account and back leaves the file exactly as it was', () async {
    const originals = [
      '{\n  "editor.fontSize": 13,\n  "claudeCode.hideOnboarding": true\n}\n',
      '{\n  "editor.fontSize": 13, // size\n  "workbench.colorTheme": "Dark",\n}\n',
      '{\n    "claudeCode.environmentVariables": [\n        { "name": "CLAUDE_CONFIG_DIR", "value": "/a/1" }\n    ],\n    "editor.tabSize": 4\n}\n',
    ];
    for (final original in originals) {
      await file().create(recursive: true);
      await file().writeAsString(original);
      final before = await settings.configDir(vscode);
      await settings.setConfigDir(vscode, '/a/2');
      await settings.setConfigDir(vscode, before);
      if (before == null) {
        expect(await file().readAsString(), original);
      } else {
        expect(await settings.configDir(vscode), before);
      }
      await settings.setConfigDir(vscode, null);
      expect(await settings.configDir(vscode), isNull);
      expect((Jsonc.decode(await file().readAsString()) as Map).containsKey(EditorSettings.settingKey), isFalse);
    }
  });
}
