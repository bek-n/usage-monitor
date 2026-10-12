import 'dart:io';

import 'jsonc.dart';
import 'paths.dart';

class Editor {
  const Editor({required this.name, required this.supportFolder, required this.dotFolder});

  final String name;
  final String supportFolder;
  final String dotFolder;
}

class EditorSettings {
  EditorSettings({String? home}) : home = home ?? homeDir;

  static const settingKey = 'claudeCode.environmentVariables';
  static const configDirVariable = 'CLAUDE_CONFIG_DIR';

  static const known = [
    Editor(name: 'VS Code', supportFolder: 'Code', dotFolder: '.vscode'),
    Editor(name: 'VS Code Insiders', supportFolder: 'Code - Insiders', dotFolder: '.vscode-insiders'),
    Editor(name: 'Cursor', supportFolder: 'Cursor', dotFolder: '.cursor'),
    Editor(name: 'Windsurf', supportFolder: 'Windsurf', dotFolder: '.windsurf'),
  ];

  final String home;

  String get _userDataRoot => Platform.isWindows ? '$home/AppData/Roaming' : '$home/Library/Application Support';

  File settingsFile(Editor editor) =>
      File(nativePath('$_userDataRoot/${editor.supportFolder}/User/settings.json'));

  Future<List<Editor>> detect() async {
    final found = <Editor>[];
    for (final editor in known) {
      final extensions = Directory(nativePath('$home/${editor.dotFolder}/extensions'));
      if (!await extensions.exists()) continue;
      final hasClaude = await extensions
          .list()
          .any((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last.startsWith('anthropic.claude-code-'));
      if (hasClaude) found.add(editor);
    }
    return found;
  }

  Future<String?> configDir(Editor editor) async {
    final file = settingsFile(editor);
    if (!await file.exists()) return null;
    final settings = Jsonc.decode(await file.readAsString());
    if (settings is! Map) return null;
    final variables = settings[settingKey];
    if (variables is! List) return null;
    for (final entry in variables) {
      if (entry is Map && entry['name'] == configDirVariable && entry['value'] is String) {
        final value = entry['value'] as String;
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  Future<void> setConfigDir(Editor editor, String? dir) async {
    final file = settingsFile(editor);
    final exists = await file.exists();
    final text = exists ? await file.readAsString() : '';
    final settings = Jsonc.decode(text);
    final current = settings is Map ? settings[settingKey] : null;
    if (current == null && dir == null) return;

    final variables = [
      if (current is List)
        for (final entry in current)
          if (!(entry is Map && entry['name'] == configDirVariable)) entry,
    ];
    if (dir != null) {
      final at = current is List
          ? current.indexWhere((e) => e is Map && e['name'] == configDirVariable)
          : -1;
      final entry = {'name': configDirVariable, 'value': dir};
      if (at >= 0 && at <= variables.length) {
        variables.insert(at, entry);
      } else {
        variables.add(entry);
      }
    }

    final updated = variables.isEmpty
        ? Jsonc.removeTopLevel(text, settingKey)
        : Jsonc.setTopLevel(text, settingKey, variables);
    Jsonc.decode(updated);
    await file.parent.create(recursive: true);
    if (exists) await file.copy('${file.path}.usage-monitor-backup');
    final tmp = File('${file.path}.usage-monitor-tmp');
    await tmp.writeAsString(updated);
    await tmp.rename(file.path);
  }
}
