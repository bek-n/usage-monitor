import 'dart:io';

import 'paths.dart';

class ShareReport {
  const ShareReport({this.linked = const [], this.ownCopies = const []});

  final List<String> linked;
  final List<String> ownCopies;
}

class ProfileSync {
  ProfileSync({String? mainDir}) : mainDir = mainDir ?? nativePath('$homeDir/.claude');

  static const wholeItems = [
    'settings.json',
    'CLAUDE.md',
    'keybindings.json',
    'projects',
    'file-history',
    'agents',
    'commands',
    'output-styles',
  ];
  static const perEntryFolders = ['skills', 'plugins'];
  static const accountOwnedEntries = {'synced', '.trash'};

  final String mainDir;

  Future<ShareReport> share(String profileDir) async {
    final linked = <String>[];
    final ownCopies = <String>[];

    Future<void> link(String relative, String source) async {
      final path = nativePath('$profileDir/$relative');
      switch (await _type(path)) {
        case FileSystemEntityType.notFound:
          if (await _createLink(path, source)) linked.add(relative);
        case FileSystemEntityType.link:
          if (!samePath(await Link(path).target(), source)) ownCopies.add(relative);
        default:
          ownCopies.add(relative);
      }
    }

    for (final name in wholeItems) {
      final source = nativePath('$mainDir/$name');
      if (await _type(source) != FileSystemEntityType.notFound) await link(name, source);
    }

    for (final folder in perEntryFolders) {
      final mainFolder = Directory(nativePath('$mainDir/$folder'));
      if (!await mainFolder.exists()) continue;
      final entries = await mainFolder.list(followLinks: false).toList();
      final shareable = entries.where((e) {
        final name = fileName(e.path);
        return !accountOwnedEntries.contains(name) && !name.startsWith('plugin-directory-cache');
      });
      if (shareable.isEmpty) continue;
      await Directory(nativePath('$profileDir/$folder')).create(recursive: true);
      for (final entry in shareable) {
        await link('$folder/${fileName(entry.path)}', entry.path);
      }
    }

    return ShareReport(linked: linked, ownCopies: ownCopies);
  }

  static Future<FileSystemEntityType> _type(String path) => FileSystemEntity.type(path, followLinks: false);

  /// Symbolic links need Developer Mode on Windows, so folders fall back to a
  /// junction there. Files are left unlinked when neither works.
  static Future<bool> _createLink(String path, String source) async {
    if (!Platform.isWindows) {
      await Link(path).create(source);
      return true;
    }
    try {
      await Link(path).create(source);
      return true;
    } on FileSystemException catch (_) {
      if (!await FileSystemEntity.isDirectory(source)) return false;
      final result = await Process.run('cmd', ['/c', 'mklink', '/J', path, source]);
      return result.exitCode == 0;
    }
  }
}
