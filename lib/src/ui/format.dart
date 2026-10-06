const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _two(int n) => n.toString().padLeft(2, '0');

String clockTime(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String resetLabel(DateTime? resetsAt, {DateTime? now}) {
  if (resetsAt == null) return '';
  final current = now ?? DateTime.now();
  final left = resetsAt.difference(current);
  if (left.isNegative) return 'Reset, refreshing';
  if (left.inMinutes < 1) return 'Resets in under a minute';
  if (left.inHours < 1) return 'Resets in ${left.inMinutes}m';
  if (left.inHours < 24) {
    final minutes = left.inMinutes % 60;
    return minutes == 0 ? 'Resets in ${left.inHours}h' : 'Resets in ${left.inHours}h ${minutes}m';
  }
  return 'Resets ${_weekdays[resetsAt.weekday - 1]} ${clockTime(resetsAt)}';
}

String updatedLabel(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Not updated yet';
  final ago = (now ?? DateTime.now()).difference(at);
  if (ago.inSeconds < 45) return 'Updated just now';
  if (ago.inMinutes < 60) return 'Updated ${ago.inMinutes < 1 ? 1 : ago.inMinutes}m ago';
  return 'Updated at ${clockTime(at)}';
}
