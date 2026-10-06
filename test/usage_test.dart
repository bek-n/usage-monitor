import 'package:usage_monitor/src/ui/format.dart';
import 'package:usage_monitor/src/usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountUsage.fromControlResponses', () {
    test('reads session and weekly windows from a Pro account', () {
      final usage = AccountUsage.fromControlResponses(
        initialize: {
          'account': {'email': 'work@example.com', 'subscriptionType': 'Claude Pro'},
        },
        usage: {
          'subscription_type': 'pro',
          'rate_limits_available': true,
          'rate_limits': {
            'five_hour': {'utilization': 62, 'resets_at': '2026-10-06T15:09:59.784784+00:00'},
            'seven_day': {'utilization': 22, 'resets_at': '2026-10-12T09:59:59.784804+00:00'},
            'seven_day_opus': null,
            'model_scoped': [
              {'display_name': 'Fable', 'utilization': 40, 'resets_at': '2026-10-12T09:59:59Z'},
            ],
          },
        },
      );

      expect(usage.loginState, LoginState.signedIn);
      expect(usage.email, 'work@example.com');
      expect(usage.plan, 'Pro');
      expect(usage.session!.percent, 62);
      expect(usage.session!.resetsAt!.toUtc(), DateTime.utc(2026, 10, 6, 15, 9, 59, 784, 784));
      expect(usage.weekly!.percent, 22);
      expect(usage.extraWindows.map((w) => w.label), ['Weekly · Fable']);
    });

    test('treats a missing email as signed out', () {
      final usage = AccountUsage.fromControlResponses(
        initialize: {
          'account': {'tokenSource': 'none'},
        },
        usage: {'subscription_type': null, 'rate_limits_available': false, 'rate_limits': null},
      );
      expect(usage.loginState, LoginState.signedOut);
    });

    test('reports no plan limits for a Console login', () {
      final usage = AccountUsage.fromControlResponses(
        initialize: {
          'account': {'email': 'work@example.com'},
        },
        usage: {'subscription_type': null, 'rate_limits_available': false, 'rate_limits': null},
      );
      expect(usage.loginState, LoginState.noPlanLimits);
    });
  });

  group('resetLabel', () {
    final now = DateTime(2026, 10, 6, 18, 0);

    test('counts down within a day', () {
      expect(resetLabel(DateTime(2026, 10, 6, 19, 44), now: now), 'Resets in 1h 44m');
      expect(resetLabel(DateTime(2026, 10, 6, 18, 20), now: now), 'Resets in 20m');
      expect(resetLabel(DateTime(2026, 10, 6, 21, 0), now: now), 'Resets in 3h');
    });

    test('names the weekday beyond a day', () {
      expect(resetLabel(DateTime(2026, 10, 12, 14, 59), now: now), 'Resets Mon 14:59');
    });

    test('flags a passed reset', () {
      expect(resetLabel(DateTime(2026, 10, 6, 17, 0), now: now), 'Reset, refreshing');
    });
  });
}
