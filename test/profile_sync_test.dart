import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:usage_monitor/src/profile_sync.dart';

void main() {
  late Directory root;
  late String main;
  late String profile;
  late ProfileSync sync;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('profile_sync_test');
    main = '${root.path}/main';
    profile = '${root.path}/profile';
    await Directory('$main/projects/-work/memory').create(recursive: true);
    await File('$main/projects/-work/memory/MEMORY.md').writeAsString('notes');
    await File('$main/settings.json').writeAsString('{"model":"opus"}');
    await Directory('$main/skills/synced/bucket-main').create(recursive: true);
    await Directory('$main/skills/my-skill').create(recursive: true);
    await Directory('$profile/skills/synced/bucket-profile').create(recursive: true);
    sync = ProfileSync(mainDir: main);
  });

  tearDown(() => root.delete(recursive: true));

  test('links settings, memory and own skills, but keeps account-synced skills apart', () async {
    final report = await sync.share(profile);

    expect(report.linked, containsAll(['settings.json', 'projects', 'skills/my-skill']));
    expect(report.ownCopies, isEmpty);
    expect(await Link('$profile/settings.json').target(), '$main/settings.json');
    expect(await File('$profile/projects/-work/memory/MEMORY.md').readAsString(), 'notes');
    expect(Directory('$profile/skills/synced/bucket-profile').existsSync(), isTrue);
    expect(Directory('$profile/skills/synced/bucket-main').existsSync(), isFalse);
    expect(FileSystemEntity.isLinkSync('$profile/skills'), isFalse);
  });

  test('is idempotent', () async {
    await sync.share(profile);
    final again = await sync.share(profile);
    expect(again.linked, isEmpty);
    expect(again.ownCopies, isEmpty);
  });

  test('never touches an account that already has its own copy', () async {
    await File('$profile/settings.json').writeAsString('{"model":"sonnet"}');

    final report = await sync.share(profile);

    expect(report.ownCopies, ['settings.json']);
    expect(await File('$profile/settings.json').readAsString(), '{"model":"sonnet"}');
    expect(await File('$main/settings.json').readAsString(), '{"model":"opus"}');
  });

  test('removing an account folder leaves the main folder intact', () async {
    await sync.share(profile);
    await Directory(profile).delete(recursive: true);

    expect(await File('$main/projects/-work/memory/MEMORY.md').readAsString(), 'notes');
    expect(await File('$main/settings.json').readAsString(), '{"model":"opus"}');
    expect(Directory('$main/skills/my-skill').existsSync(), isTrue);
  });
}
