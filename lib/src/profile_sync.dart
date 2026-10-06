import 'dart:io';

class ShareReport {
  const ShareReport({this.linked = const [], this.ownCopies = const []});

  final List<String> linked;
  final List<String> ownCopies;
}

class ProfileSync {
  ProfileSync({String? mainDir}) : mainDir = mainDir ?? '${Platform.environment['HOME']}/.claude';

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
      final path = '$profileDir/$relative';
      switch (await _type(path)) {
        case FileSystemEntityType.notFound:
          await Link(path).create(source);
          linked.add(relative);
        case FileSystemEntityType.link:
          if (await Link(path).target() != source) ownCopies.add(relative);
        default:
          ownCopies.add(relative);
      }
    }

    for (final name in wholeItems) {
      final source = '$mainDir/$name';
      if (await _type(source) != FileSystemEntityType.notFound) await link(name, source);
    }

    for (final folder in perEntryFolders) {
      final mainFolder = Directory('$mainDir/$folder');
      if (!await mainFolder.exists()) continue;
      final entries = await mainFolder.list(followLinks: false).toList();
      final shareable = entries.where((e) {
        final name = _name(e.path);
        return !accountOwnedEntries.contains(name) && !name.startsWith('plugin-directory-cache');
      });
      if (shareable.isEmpty) continue;
      await Directory('$profileDir/$folder').create(recursive: true);
      for (final entry in shareable) {
        await link('$folder/${_name(entry.path)}', entry.path);
      }
    }

    return ShareReport(linked: linked, ownCopies: ownCopies);
  }

  static Future<FileSystemEntityType> _type(String path) => FileSystemEntity.type(path, followLinks: false);

  static String _name(String path) => path.split('/').where((s) => s.isNotEmpty).last;
}
