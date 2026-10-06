class UsageWindow {
  const UsageWindow({
    required this.label,
    required this.percent,
    required this.resetsAt,
  });

  final String label;
  final double percent;
  final DateTime? resetsAt;

  bool get hasReset => resetsAt != null && DateTime.now().isAfter(resetsAt!);

  double get currentPercent => hasReset ? 0 : percent;

  static UsageWindow? fromJson(String label, Object? json) {
    if (json is! Map) return null;
    final utilization = json['utilization'];
    if (utilization is! num) return null;
    final resetsAt = json['resets_at'];
    return UsageWindow(
      label: label,
      percent: utilization.toDouble(),
      resetsAt: resetsAt is String ? DateTime.tryParse(resetsAt)?.toLocal() : null,
    );
  }
}

enum LoginState { signedIn, signedOut, noPlanLimits }

class AccountUsage {
  const AccountUsage({
    required this.loginState,
    required this.fetchedAt,
    this.email,
    this.organization,
    this.plan,
    this.session,
    this.weekly,
    this.extraWindows = const [],
  });

  final LoginState loginState;
  final DateTime fetchedAt;
  final String? email;
  final String? organization;
  final String? plan;
  final UsageWindow? session;
  final UsageWindow? weekly;
  final List<UsageWindow> extraWindows;

  List<UsageWindow> get windows => [?session, ?weekly, ...extraWindows];

  DateTime? get nextReset {
    final upcoming = windows
        .map((w) => w.resetsAt)
        .whereType<DateTime>()
        .where((t) => t.isAfter(fetchedAt));
    if (upcoming.isEmpty) return null;
    return upcoming.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  factory AccountUsage.fromControlResponses({
    required Map<String, dynamic> initialize,
    required Map<String, dynamic> usage,
  }) {
    final account = initialize['account'];
    final email = account is Map ? account['email'] as String? : null;
    final organization = account is Map ? account['organization'] as String? : null;
    final now = DateTime.now();

    if (email == null || email.isEmpty) {
      return AccountUsage(loginState: LoginState.signedOut, fetchedAt: now);
    }

    final plan = _planName(usage['subscription_type'] as String?) ??
        _planName(account is Map ? account['subscriptionType'] as String? : null);
    final limits = usage['rate_limits'];
    if (usage['rate_limits_available'] != true || limits is! Map) {
      return AccountUsage(
        loginState: LoginState.noPlanLimits,
        fetchedAt: now,
        email: email,
        organization: organization,
        plan: plan,
      );
    }

    final modelScoped = limits['model_scoped'];
    return AccountUsage(
      loginState: LoginState.signedIn,
      fetchedAt: now,
      email: email,
      organization: organization,
      plan: plan,
      session: UsageWindow.fromJson('Session', limits['five_hour']),
      weekly: UsageWindow.fromJson('Weekly', limits['seven_day']),
      extraWindows: [
        ?UsageWindow.fromJson('Weekly · Opus', limits['seven_day_opus']),
        ?UsageWindow.fromJson('Weekly · Sonnet', limits['seven_day_sonnet']),
        if (modelScoped is List)
          for (final row in modelScoped)
            if (row is Map && row['display_name'] is String)
              ?UsageWindow.fromJson('Weekly · ${row['display_name']}', row),
      ],
    );
  }

  static String? _planName(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final name = raw.replaceFirst(RegExp(r'^claude\s+', caseSensitive: false), '');
    return name[0].toUpperCase() + name.substring(1);
  }
}
