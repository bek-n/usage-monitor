import 'dart:convert';

class _Token {
  const _Token(this.kind, this.start, this.end);

  final String kind;
  final int start;
  final int end;
}

class Jsonc {
  static List<_Token> _tokenize(String s) {
    final tokens = <_Token>[];
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (' \t\r\n﻿'.contains(c)) {
        i++;
      } else if (s.startsWith('//', i)) {
        final end = s.indexOf('\n', i);
        i = end == -1 ? s.length : end;
      } else if (s.startsWith('/*', i)) {
        final end = s.indexOf('*/', i + 2);
        i = end == -1 ? s.length : end + 2;
      } else if ('{}[]:,'.contains(c)) {
        tokens.add(_Token(c, i, i + 1));
        i++;
      } else if (c == '"') {
        var j = i + 1;
        while (j < s.length && s[j] != '"') {
          j += s[j] == r'\' ? 2 : 1;
        }
        tokens.add(_Token('string', i, (j + 1).clamp(0, s.length)));
        i = j + 1;
      } else {
        var j = i;
        while (j < s.length && !' \t\r\n{}[]:,"/'.contains(s[j])) {
          j++;
        }
        if (j == i) j++;
        tokens.add(_Token('literal', i, j));
        i = j;
      }
    }
    return tokens;
  }

  static String strip(String text) {
    final tokens = _tokenize(text);
    final out = StringBuffer();
    for (var k = 0; k < tokens.length; k++) {
      final t = tokens[k];
      final next = k + 1 < tokens.length ? tokens[k + 1].kind : null;
      if (t.kind == ',' && (next == '}' || next == ']' || next == null)) continue;
      out.write(text.substring(t.start, t.end));
    }
    return out.toString();
  }

  static Object? decode(String text) => text.trim().isEmpty ? null : jsonDecode(strip(text));

  static String setTopLevel(String text, String key, Object? value) {
    if (text.trim().isEmpty) {
      return '{\n  ${jsonEncode(key)}: ${_encode(value, '  ')}\n}\n';
    }
    final tokens = _tokenize(text);
    if (tokens.isEmpty || tokens.first.kind != '{') {
      throw const FormatException('The settings file is not a JSON object');
    }

    var depth = 0;
    int? rootClose;
    _Token? firstKey;
    for (var k = 0; k < tokens.length; k++) {
      final t = tokens[k];
      if (t.kind == '{' || t.kind == '[') {
        depth++;
      } else if (t.kind == '}' || t.kind == ']') {
        depth--;
        if (depth == 0) {
          rootClose = k;
          break;
        }
      } else if (depth == 1 &&
          t.kind == 'string' &&
          k + 1 < tokens.length &&
          tokens[k + 1].kind == ':') {
        firstKey ??= t;
        if (jsonDecode(text.substring(t.start, t.end)) == key) {
          final valueStart = k + 2;
          final valueEnd = _valueEnd(tokens, valueStart);
          final indent = _lineIndent(text, t.start);
          return text.replaceRange(
            tokens[valueStart].start,
            tokens[valueEnd].end,
            _encode(value, indent),
          );
        }
      }
    }
    if (rootClose == null) throw const FormatException('The settings file is not closed');

    final indent = firstKey == null ? '  ' : _lineIndent(text, firstKey.start);
    final last = tokens[rootClose - 1];
    final leading = last.kind == '{' || last.kind == ',' ? '' : ',';
    final trailingComma = last.kind == ',' ? ',' : '';
    final entry = '$leading\n$indent${jsonEncode(key)}: ${_encode(value, indent)}$trailingComma';
    final trailing = last.kind == '{' ? '\n' : '';
    return text.replaceRange(last.end, last.end, '$entry$trailing');
  }

  static String removeTopLevel(String text, String key) {
    final tokens = _tokenize(text);
    var depth = 0;
    for (var k = 0; k < tokens.length; k++) {
      final t = tokens[k];
      if (t.kind == '{' || t.kind == '[') {
        depth++;
      } else if (t.kind == '}' || t.kind == ']') {
        depth--;
      } else if (depth == 1 &&
          t.kind == 'string' &&
          k + 1 < tokens.length &&
          tokens[k + 1].kind == ':' &&
          jsonDecode(text.substring(t.start, t.end)) == key) {
        final valueEnd = _valueEnd(tokens, k + 2);
        final after = valueEnd + 1 < tokens.length ? tokens[valueEnd + 1] : null;
        if (after != null && after.kind == ',') {
          var start = t.start;
          final lineStart = text.lastIndexOf('\n', start - 1) + 1;
          if (RegExp(r'^[ \t]*$').hasMatch(text.substring(lineStart, start))) start = lineStart;
          var end = after.end;
          final rest = RegExp(r'^[ \t]*\r?\n').firstMatch(text.substring(end));
          if (rest != null && start == text.lastIndexOf('\n', t.start - 1) + 1) end += rest.end;
          return text.replaceRange(start, end, '');
        }
        final before = tokens[k - 1];
        final start = before.kind == ',' ? before.start : t.start;
        return text.replaceRange(start, tokens[valueEnd].end, '');
      }
    }
    return text;
  }

  static int _valueEnd(List<_Token> tokens, int start) {
    final first = tokens[start];
    if (first.kind != '{' && first.kind != '[') return start;
    var depth = 0;
    for (var k = start; k < tokens.length; k++) {
      final kind = tokens[k].kind;
      if (kind == '{' || kind == '[') depth++;
      if (kind == '}' || kind == ']') depth--;
      if (depth == 0) return k;
    }
    throw const FormatException('A value in the settings file is not closed');
  }

  static String _lineIndent(String text, int offset) {
    final lineStart = text.lastIndexOf('\n', offset - 1) + 1;
    final prefix = text.substring(lineStart, offset);
    return RegExp(r'^[ \t]*$').hasMatch(prefix) ? prefix : '  ';
  }

  static String _encode(Object? value, String indent) {
    final unit = indent.isEmpty ? '  ' : (indent.startsWith('\t') ? '\t' : indent);
    return JsonEncoder.withIndent(unit).convert(value).replaceAll('\n', '\n$indent');
  }
}
