import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../di/service_locator.dart';
import '../database/hive_task_cache.dart';

class TamperResult {
  final bool isTampered;
  final String? reason;
  final DateTime systemTime;
  final DateTime? realTime;

  TamperResult({
    required this.isTampered,
    this.reason,
    required this.systemTime,
    this.realTime,
  });
}

class AntiTamperService {
  static const MethodChannel _channel =
      MethodChannel('com.hagbes.workshop_mechanic/anti_tamper');

  static const String _keyLastTrustedTime = 'anti_tamper_last_trusted_time';
  static const String _keyBootAnchor = 'anti_tamper_boot_anchor';

  /// Verifies system time integrity against hardware settings, monotonic clock, and historical anchors.
  static Future<TamperResult> checkTimeIntegrity() async {
    final systemTime = DateTime.now();

    // 1. Enforce Android Automatic Date & Time + Time Zone hardware settings
    try {
      final isAutoTime = await _channel.invokeMethod<bool>('isAutoTimeEnabled');
      if (isAutoTime == false) {
        return TamperResult(
          isTampered: true,
          reason:
              'Automatic Date & Time is disabled in your phone settings. To prevent duty hour tampering, you MUST enable "Automatic Date & Time" and "Automatic Time Zone" in phone settings.',
          systemTime: systemTime,
        );
      }
    } catch (_) {
      // Platform call optional fallback on non-Android platforms
    }

    final cache = sl<HiveTaskCache>();

    // 2. Hardware Monotonic Clock Shift Detection (SystemClock.elapsedRealtime)
    try {
      final elapsedRealtime = await _channel.invokeMethod<int>('getElapsedRealtime');
      if (elapsedRealtime != null && elapsedRealtime > 0) {
        final currentBootAnchor = systemTime.millisecondsSinceEpoch - elapsedRealtime;
        final storedBootAnchorMap = cache.getMap(_keyBootAnchor);

        if (storedBootAnchorMap != null && storedBootAnchorMap['anchor'] != null) {
          final storedAnchor = storedBootAnchorMap['anchor'] as int;
          final diff = (currentBootAnchor - storedAnchor).abs();
          // If the system time was shifted by more than 2 minutes relative to hardware CPU uptime
          if (diff > 120000) {
            return TamperResult(
              isTampered: true,
              reason:
                  'Manual system clock shift detected. Phone clock was changed manually while device was running.',
              systemTime: systemTime,
            );
          }
        }
        // Save current boot anchor
        await cache.saveMap(_keyBootAnchor, {'anchor': currentBootAnchor});
      }
    } catch (_) {}

    // 3. Time-Travel Backwards Check (System time < Last Recorded Action Time)
    final lastTimeMap = cache.getMap(_keyLastTrustedTime);
    if (lastTimeMap != null && lastTimeMap['timestamp'] != null) {
      final lastMs = lastTimeMap['timestamp'] as int;
      final lastTime = DateTime.fromMillisecondsSinceEpoch(lastMs);

      // If phone time is earlier than a previously recorded timestamp by > 1 minute
      if (systemTime.isBefore(lastTime.subtract(const Duration(minutes: 1)))) {
        final sysStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(systemTime);
        final lastStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(lastTime);
        return TamperResult(
          isTampered: true,
          reason:
              'Phone system clock was turned back in time. Current time ($sysStr) is earlier than previous recorded activity ($lastStr).',
          systemTime: systemTime,
          realTime: lastTime,
        );
      }
    }

    // 4. Android Network Hardware Time Check (if synchronized)
    try {
      final netTimeMs = await _channel.invokeMethod<int>('getNetworkTime');
      if (netTimeMs != null && netTimeMs > 0) {
        final netTime = DateTime.fromMillisecondsSinceEpoch(netTimeMs);
        final diff = (systemTime.difference(netTime).inSeconds).abs();
        if (diff > 120) {
          return TamperResult(
            isTampered: true,
            reason:
                'System date/clock mismatch with network time server (Difference: ${diff ~/ 60} minutes).',
            systemTime: systemTime,
            realTime: netTime,
          );
        }
      }
    } catch (_) {}

    // If passed all checks, record current system time as trusted timestamp
    await cache.saveMap(_keyLastTrustedTime, {
      'timestamp': systemTime.millisecondsSinceEpoch,
    });

    return TamperResult(
      isTampered: false,
      systemTime: systemTime,
    );
  }
}
