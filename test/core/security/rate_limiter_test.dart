import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/core/security/rate_limiter.dart';

void main() {
  var t = DateTime(2026, 10, 3, 9);
  DateTime now() => t;
  void advance(Duration d) => t = t.add(d);

  setUp(() => t = DateTime(2026, 10, 3, 9));

  group('ThrottlePolicy.lockAfter', () {
    const p = ThrottlePolicy.loginPerEmail;

    test('the first five failures are free', () {
      for (var n = 1; n <= 5; n++) {
        expect(p.lockAfter(n), Duration.zero, reason: 'failure $n');
      }
    });

    test('then 1 minute, doubling, capped at 15', () {
      expect(p.lockAfter(6), const Duration(minutes: 1));
      expect(p.lockAfter(7), const Duration(minutes: 2));
      expect(p.lockAfter(8), const Duration(minutes: 4));
      expect(p.lockAfter(9), const Duration(minutes: 8));
      expect(p.lockAfter(10), const Duration(minutes: 15));
      expect(p.lockAfter(500), const Duration(minutes: 15));
    });
  });

  group('Throttle', () {
    Throttle make({SharedPreferences? prefs}) =>
        Throttle('t', ThrottlePolicy.loginPerEmail, prefs: prefs, now: now);

    test('locks on the sixth failure and says for how long', () {
      final th = make();
      for (var i = 0; i < 5; i++) {
        expect(th.recordFailure('a'), isNull);
      }
      expect(th.lockedFor('a'), isNull);

      expect(th.recordFailure('a'), const Duration(minutes: 1));
      expect(th.lockedFor('a'), const Duration(minutes: 1));
    });

    test('the lock runs out with time', () {
      final th = make();
      for (var i = 0; i < 6; i++) {
        th.recordFailure('a');
      }
      advance(const Duration(seconds: 59));
      expect(th.lockedFor('a'), const Duration(seconds: 1));
      advance(const Duration(seconds: 1));
      expect(th.lockedFor('a'), isNull);
    });

    test('a failure right after a lock ends locks for longer', () {
      final th = make();
      for (var i = 0; i < 6; i++) {
        th.recordFailure('a');
      }
      advance(const Duration(minutes: 1));
      expect(th.recordFailure('a'), const Duration(minutes: 2));
    });

    test('keys are separate', () {
      final th = make();
      for (var i = 0; i < 6; i++) {
        th.recordFailure('a');
      }
      expect(th.lockedFor('a'), isNotNull);
      expect(th.lockedFor('b'), isNull);
    });

    test('a success clears the count', () {
      final th = make();
      for (var i = 0; i < 6; i++) {
        th.recordFailure('a');
      }
      th.reset('a');
      expect(th.lockedFor('a'), isNull);
      for (var i = 0; i < 5; i++) {
        expect(th.recordFailure('a'), isNull);
      }
    });

    test('failures an hour old stop counting', () {
      final th = make();
      for (var i = 0; i < 5; i++) {
        th.recordFailure('a');
      }
      advance(const Duration(hours: 1, minutes: 1));
      expect(th.recordFailure('a'), isNull, reason: 'counts as the first');
    });

    test('a lock survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = make(prefs: prefs);
      for (var i = 0; i < 6; i++) {
        first.recordFailure('a');
      }

      final reopened = make(prefs: prefs);
      expect(reopened.lockedFor('a'), const Duration(minutes: 1));
    });

    test('a damaged record is ignored', () async {
      SharedPreferences.setMockInitialValues({'rate_limit.t': 'not json'});
      final prefs = await SharedPreferences.getInstance();
      final th = make(prefs: prefs);
      expect(th.lockedFor('a'), isNull);
      expect(th.recordFailure('a'), isNull);
    });
  });

  group('Cooldown', () {
    test('waits a minute between sends, per key', () {
      final c = Cooldown('c', const Duration(seconds: 60), now: now);
      expect(c.remaining('a'), isNull);
      c.start('a');
      expect(c.remaining('a'), const Duration(seconds: 60));
      expect(c.remaining('b'), isNull);
      advance(const Duration(seconds: 61));
      expect(c.remaining('a'), isNull);
    });

    test('survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Cooldown('c', const Duration(seconds: 60), prefs: prefs, now: now)
          .start('a');
      final reopened =
          Cooldown('c', const Duration(seconds: 60), prefs: prefs, now: now);
      expect(reopened.remaining('a'), const Duration(seconds: 60));
    });
  });

  group('AuthLimits', () {
    test('the device lock catches many emails tried a few times each', () {
      final limits = AuthLimits(null);
      for (var i = 0; i < 16; i++) {
        limits.loginFailed('person$i@isufst.edu.ph');
      }
      expect(limits.loginLock('person0@isufst.edu.ph'), isNotNull);
      expect(limits.loginLock('someone-new@isufst.edu.ph'), isNotNull);
    });

    test('emails are matched ignoring case and spaces', () {
      final limits = AuthLimits(null);
      for (var i = 0; i < 6; i++) {
        limits.loginFailed('  Kj@ISUFST.edu.ph ');
      }
      expect(limits.loginLock('kj@isufst.edu.ph'), isNotNull);
    });

    test('a success clears both locks', () {
      final limits = AuthLimits(null);
      for (var i = 0; i < 6; i++) {
        limits.loginFailed('a@isufst.edu.ph');
      }
      limits.loginSucceeded('a@isufst.edu.ph');
      expect(limits.loginLock('a@isufst.edu.ph'), isNull);
    });
  });

  group('waitText', () {
    test('rounds up and pluralises', () {
      expect(waitText(const Duration(milliseconds: 100)), '1 second');
      expect(waitText(const Duration(seconds: 45)), '45 seconds');
      expect(waitText(const Duration(seconds: 60)), '1 minute');
      expect(waitText(const Duration(seconds: 61)), '2 minutes');
      expect(waitText(const Duration(minutes: 15)), '15 minutes');
    });
  });
}
