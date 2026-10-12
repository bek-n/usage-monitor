import 'dart:io';

final String homeDir = Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '';

/// Turns a path written with `/` into the platform's own form.
String nativePath(String path) => Platform.isWindows ? path.replaceAll('/', r'\') : path;

/// Compares two paths the way the file system does.
bool samePath(String a, String b) {
  String clean(String path) {
    var p = path;
    if (Platform.isWindows) {
      p = p.replaceAll('/', r'\').replaceFirst(RegExp(r'^\\(\\\?|\?\?)\\'), '').toLowerCase();
    }
    return p.endsWith(Platform.pathSeparator) ? p.substring(0, p.length - 1) : p;
  }

  return clean(a) == clean(b);
}

/// Shortens a path in the home folder to start with `~`.
String shortPath(String path) =>
    homeDir.isNotEmpty && path.startsWith(homeDir) ? '~${path.substring(homeDir.length)}' : path;

String fileName(String path) => path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
