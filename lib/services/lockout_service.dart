import 'package:shared_preferences/shared_preferences.dart';

class LockoutService {
  static const String _lockoutTimeKey = 'lockout_time';
  static const String _failedAttemptsKey = 'failed_attempts';
  static const Duration _lockoutDuration = Duration(minutes: 2);
  static const int _maxFailedAttempts = 5;

  /// Get lockout time from storage
  static Future<DateTime?> _getLockoutTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lockoutTimeKey);
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      print('❌ Error getting lockout time: $e');
    }
    return null;
  }

  /// Save lockout time to storage
  static Future<void> _setLockoutTime(DateTime? time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (time == null) {
        await prefs.remove(_lockoutTimeKey);
      } else {
        await prefs.setInt(_lockoutTimeKey, time.millisecondsSinceEpoch);
      }
    } catch (e) {
      print('❌ Error setting lockout time: $e');
    }
  }

  /// Get failed attempts from storage
  static Future<int> _getFailedAttempts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_failedAttemptsKey) ?? 0;
    } catch (e) {
      print('❌ Error getting failed attempts: $e');
      return 0;
    }
  }

  /// Save failed attempts to storage
  static Future<void> _setFailedAttempts(int attempts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_failedAttemptsKey, attempts);
    } catch (e) {
      print('❌ Error setting failed attempts: $e');
    }
  }

  static Future<void> setLockout() async {
    final now = DateTime.now();
    final currentAttempts = await _getFailedAttempts();
    await _setLockoutTime(now);
    await _setFailedAttempts(currentAttempts + 1);
    print('🚨 LOCKOUT ACTIVATED: Failed attempt ${currentAttempts + 1}/$_maxFailedAttempts');
  }

  static Future<void> recordFailedAttempt() async {
    final currentAttempts = await _getFailedAttempts();
    final newAttempts = currentAttempts + 1;
    await _setFailedAttempts(newAttempts);
    print('🚨 FAILED ATTEMPT: $newAttempts/$_maxFailedAttempts');
    
    if (newAttempts >= _maxFailedAttempts) {
      await setLockout();
    }
  }

  static Future<bool> isLockedOut() async {
    final lockoutTime = await _getLockoutTime();
    if (lockoutTime == null) return false;

    final now = DateTime.now();
    final timeSinceLockout = now.difference(lockoutTime);

    if (timeSinceLockout > _lockoutDuration) {
      // Reset lockout after duration
      await _setLockoutTime(null);
      await _setFailedAttempts(0);
      return false;
    }

    return true;
  }

  static Future<Duration?> getRemainingTime() async {
    final lockoutTime = await _getLockoutTime();
    if (lockoutTime == null) return null;

    final now = DateTime.now();
    final timeSinceLockout = now.difference(lockoutTime);

    if (timeSinceLockout > _lockoutDuration) {
      await _setLockoutTime(null);
      await _setFailedAttempts(0);
      return null;
    }

    return _lockoutDuration - timeSinceLockout;
  }

  static Future<void> clearLockout() async {
    await _setLockoutTime(null);
    await _setFailedAttempts(0);
  }

  static Future<int> getFailedAttempts() async {
    return await _getFailedAttempts();
  }

  static Future<bool> shouldBlockAccess() async {
    final isLocked = await isLockedOut();
    final attempts = await getFailedAttempts();
    return isLocked || attempts >= _maxFailedAttempts;
  }

  /// Reset lockout on app restart (for development/testing)
  static Future<void> resetLockout() async {
    await clearLockout();
    print('🔄 Lockout reset for testing');
  }

  /// Force clear lockout immediately (for debugging)
  static Future<void> forceClearLockout() async {
    await clearLockout();
    print('🔄 FORCE CLEAR: Lockout cleared immediately');
  }

  /// Get lockout status for debugging
  static Future<Map<String, dynamic>> getLockoutStatus() async {
    final lockoutTime = await _getLockoutTime();
    final attempts = await getFailedAttempts();
    final remaining = await getRemainingTime();
    
    return {
      'isLockedOut': await isLockedOut(),
      'failedAttempts': attempts,
      'maxFailedAttempts': _maxFailedAttempts,
      'lockoutTime': lockoutTime?.toIso8601String(),
      'remainingTime': remaining?.inSeconds,
    };
  }
}
