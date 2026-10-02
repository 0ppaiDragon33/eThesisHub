import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/providers/shared_prefs_provider.dart';

/// Client-side rate limiting for sign-in and the account emails.
///
/// This slows a person down; it is not a security boundary. Anyone can clear
/// app storage or call Firebase directly, and Firebase Auth throttles on its
/// own servers too (`too-many-requests`). What this adds is a clear lock with
/// a time on it, so a wrong-password loop or a mashed Resend button stops
/// early and says when to come back.

/// How many failures are free, and how long the lock is after that. The lock
/// doubles with every further failure, up to [maxLock].
class ThrottlePolicy {
  const ThrottlePolicy({
    required this.freeAttempts,
    required this.baseLock,
    required this.maxLock,
  });

  final int freeAttempts;
  final Duration baseLock;
  final Duration maxLock;

  /// Failures older than this stop counting, so five slips last week do not
  /// lock today's first mistake.
  static const decayAfter = Duration(hours: 1);

  /// Sign-in: 5 wrong passwords for one email, then 1 minute, doubling to 15.
  static const loginPerEmail = ThrottlePolicy(
    freeAttempts: 5,
    baseLock: Duration(minutes: 1),
    maxLock: Duration(minutes: 15),
  );

  /// Sign-in across all emails on this device, so trying many addresses a few
  /// times each does not get around the per-email lock.
  static const loginPerDevice = ThrottlePolicy(
    freeAttempts: 15,
    baseLock: Duration(minutes: 1),
    maxLock: Duration(minutes: 15),
  );

  Duration lockAfter(int failures) {
    if (failures <= freeAttempts) return Duration.zero;
    final doublings = failures - freeAttempts - 1;
    // Clamp the exponent first so a long run of failures cannot overflow.
    final factor = 1 << doublings.clamp(0, 20);
    final lock = baseLock * factor;
    return lock > maxLock ? maxLock : lock;
  }
}

class _Entry {
  _Entry(this.failures, this.lockedUntil, this.last);
  int failures;
  DateTime? lockedUntil;

  /// When the latest failure happened, so old ones can age out.
  DateTime last;
}

/// Counts failures per key and locks the key once they pass the policy's
/// free attempts. A success [reset]s the key.
///
/// Held in memory and mirrored to [prefs] when given, so closing the app does
/// not clear a lock.
class Throttle {
  Throttle(
    this.name,
    this.policy, {
    this.prefs,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _load();
  }

  final String name;
  final ThrottlePolicy policy;
  final SharedPreferences? prefs;
  final DateTime Function() _now;
  final Map<String, _Entry> _entries = {};

  String get _prefsKey => 'rate_limit.$name';

  /// Time left on the lock for [key], or null when it is free to try.
  Duration? lockedFor(String key) {
    final until = _entries[key]?.lockedUntil;
    if (until == null) return null;
    final left = until.difference(_now());
    return left > Duration.zero ? left : null;
  }

  /// Records a failed attempt. Returns the lock that now applies, or null.
  Duration? recordFailure(String key) {
    final now = _now();
    final e = _entries.putIfAbsent(key, () => _Entry(0, null, now));
    if (now.difference(e.last) > ThrottlePolicy.decayAfter) e.failures = 0;
    e.last = now;
    e.failures += 1;
    final lock = policy.lockAfter(e.failures);
    e.lockedUntil = lock == Duration.zero ? null : now.add(lock);
    _save();
    return lock == Duration.zero ? null : lock;
  }

  void reset(String key) {
    if (_entries.remove(key) != null) _save();
  }

  void _load() {
    final raw = prefs?.getString(_prefsKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        final v = e.value as Map<String, dynamic>;
        final until = v['until'] as int?;
        _entries[e.key] = _Entry(
          v['n'] as int,
          until == null ? null : DateTime.fromMillisecondsSinceEpoch(until),
          DateTime.fromMillisecondsSinceEpoch(v['last'] as int),
        );
      }
    } catch (_) {
      // A damaged record is the same as none.
      prefs?.remove(_prefsKey);
    }
  }

  void _save() {
    final p = prefs;
    if (p == null) return;
    final now = _now();
    // Keep only keys that still matter: locked now, or with failures to count.
    final map = {
      for (final e in _entries.entries)
        if (e.value.failures > 0 &&
            now.difference(e.value.last) <= ThrottlePolicy.decayAfter)
          e.key: {
            'n': e.value.failures,
            'last': e.value.last.millisecondsSinceEpoch,
            'until': e.value.lockedUntil != null &&
                    e.value.lockedUntil!.isAfter(now)
                ? e.value.lockedUntil!.millisecondsSinceEpoch
                : null,
          },
    };
    p.setString(_prefsKey, jsonEncode(map));
  }
}

/// A fixed wait between sends of the same email (resend verification, reset
/// password). Started after a send goes out.
class Cooldown {
  Cooldown(
    this.name,
    this.wait, {
    this.prefs,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _load();
  }

  final String name;
  final Duration wait;
  final SharedPreferences? prefs;
  final DateTime Function() _now;
  final Map<String, DateTime> _until = {};

  String get _prefsKey => 'cooldown.$name';

  /// Time left before [key] may send again, or null when it may.
  Duration? remaining(String key) {
    final until = _until[key];
    if (until == null) return null;
    final left = until.difference(_now());
    return left > Duration.zero ? left : null;
  }

  void start(String key) {
    _until[key] = _now().add(wait);
    _save();
  }

  void _load() {
    final raw = prefs?.getString(_prefsKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        _until[e.key] = DateTime.fromMillisecondsSinceEpoch(e.value as int);
      }
    } catch (_) {
      prefs?.remove(_prefsKey);
    }
  }

  void _save() {
    final p = prefs;
    if (p == null) return;
    final now = _now();
    _until.removeWhere((_, until) => !until.isAfter(now));
    p.setString(
      _prefsKey,
      jsonEncode({
        for (final e in _until.entries) e.key: e.value.millisecondsSinceEpoch,
      }),
    );
  }
}

/// "45 seconds", "1 minute", "3 minutes": rounded up, so a lock never reads
/// as shorter than it is.
String waitText(Duration d) {
  final seconds = d.inMilliseconds <= 0 ? 0 : (d.inMilliseconds + 999) ~/ 1000;
  if (seconds < 60) return '$seconds second${seconds == 1 ? '' : 's'}';
  final minutes = (seconds + 59) ~/ 60;
  return '$minutes minute${minutes == 1 ? '' : 's'}';
}

/// The limiters the auth screens share. Created once so a lock survives
/// leaving and re-entering a screen.
class AuthLimits {
  AuthLimits(SharedPreferences? prefs)
    : loginPerEmail = Throttle('login_email', ThrottlePolicy.loginPerEmail,
          prefs: prefs),
      loginPerDevice = Throttle('login_device', ThrottlePolicy.loginPerDevice,
          prefs: prefs),
      resendVerification = Cooldown(
        'resend_verification',
        const Duration(seconds: 60),
        prefs: prefs,
      ),
      passwordReset = Cooldown(
        'password_reset',
        const Duration(seconds: 60),
        prefs: prefs,
      );

  final Throttle loginPerEmail;
  final Throttle loginPerDevice;
  final Cooldown resendVerification;
  final Cooldown passwordReset;

  /// Key for one account's sign-in attempts: the email, lower-cased.
  static String emailKey(String email) => email.trim().toLowerCase();

  /// Key for the whole device.
  static const deviceKey = 'device';

  /// Longest lock currently on a sign-in for [email], or null.
  Duration? loginLock(String email) {
    final a = loginPerEmail.lockedFor(emailKey(email));
    final b = loginPerDevice.lockedFor(deviceKey);
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }

  void loginFailed(String email) {
    loginPerEmail.recordFailure(emailKey(email));
    loginPerDevice.recordFailure(deviceKey);
  }

  void loginSucceeded(String email) {
    loginPerEmail.reset(emailKey(email));
    loginPerDevice.reset(deviceKey);
  }
}

/// Falls back to memory when stored preferences are not available (tests,
/// or a platform where they fail to open).
final authLimitsProvider = Provider<AuthLimits>((ref) {
  SharedPreferences? prefs;
  try {
    prefs = ref.read(sharedPrefsProvider);
  } catch (_) {
    prefs = null;
  }
  return AuthLimits(prefs);
});
