class LockoutService {
  static DateTime? _lockoutTime;
  static int _failedAttempts = 0;
  static const Duration _lockoutDuration = Duration(minutes: 2); // Reduced to 2 minutes for testing
  static const int _maxFailedAttempts = 5; // Lockout after 5 failed attempts (more lenient)

  static void setLockout() {
    _lockoutTime = DateTime.now();
    _failedAttempts++;
    print('🚨 LOCKOUT ACTIVATED: Failed attempt $_failedAttempts/$_maxFailedAttempts');
  }

  static void recordFailedAttempt() {
    _failedAttempts++;
    print('🚨 FAILED ATTEMPT: $_failedAttempts/$_maxFailedAttempts');
    
    if (_failedAttempts >= _maxFailedAttempts) {
      setLockout();
    }
  }

  static bool isLockedOut() {
    if (_lockoutTime == null) return false;

    final now = DateTime.now();
    final timeSinceLockout = now.difference(_lockoutTime!);

    if (timeSinceLockout > _lockoutDuration) {
      // Reset lockout after duration
      _lockoutTime = null;
      _failedAttempts = 0;
      return false;
    }

    return true;
  }

  static Duration? getRemainingTime() {
    if (_lockoutTime == null) return null;

    final now = DateTime.now();
    final timeSinceLockout = now.difference(_lockoutTime!);

    if (timeSinceLockout > _lockoutDuration) {
      _lockoutTime = null;
      _failedAttempts = 0;
      return null;
    }

    return _lockoutDuration - timeSinceLockout;
  }

  static void clearLockout() {
    _lockoutTime = null;
    _failedAttempts = 0;
  }

  static int getFailedAttempts() {
    return _failedAttempts;
  }

  static bool shouldBlockAccess() {
    return isLockedOut() || _failedAttempts >= _maxFailedAttempts;
  }

  /// Reset lockout on app restart (for development/testing)
  static void resetLockout() {
    _lockoutTime = null;
    _failedAttempts = 0;
    print('🔄 Lockout reset for testing');
  }

  /// Force clear lockout immediately (for debugging)
  static void forceClearLockout() {
    _lockoutTime = null;
    _failedAttempts = 0;
    print('🔄 FORCE CLEAR: Lockout cleared immediately');
  }

  /// Get lockout status for debugging
  static Map<String, dynamic> getLockoutStatus() {
    return {
      'isLockedOut': isLockedOut(),
      'failedAttempts': _failedAttempts,
      'maxFailedAttempts': _maxFailedAttempts,
      'lockoutTime': _lockoutTime?.toIso8601String(),
      'remainingTime': getRemainingTime()?.inSeconds,
    };
  }
}





