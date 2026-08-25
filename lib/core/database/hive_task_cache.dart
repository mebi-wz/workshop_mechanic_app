import 'package:hive_ce_flutter/hive_flutter.dart';

/// Persistent cache for task records returned by Odoo.
///
/// Raw maps are stored so schema changes from Odoo do not require generated
/// Hive adapters or a local database migration.
class HiveTaskCache {
  static const _boxName = 'task_cache';
  late final Box<dynamic> _box;

  Future<void> initialize() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  Future<void> saveTasks(
    String key,
    List<Map<String, dynamic>> records,
  ) =>
      saveRecords(key, records);

  Future<void> saveRecords(
    String key,
    List<Map<String, dynamic>> records,
  ) async {
    await _box.put(key, {
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'records': records,
    });
  }

  List<Map<String, dynamic>> getTasks(String key) {
    return getRecords(key);
  }

  List<Map<String, dynamic>> getRecords(String key) {
    final cached = _box.get(key);
    if (cached is! Map) return const [];

    final records = cached['records'];
    if (records is! List) return const [];

    return records
        .whereType<Map>()
        .map((record) => _stringKeyedMap(record))
        .toList();
  }

  Future<void> saveMap(String key, Map<String, dynamic> value) async {
    await _box.put(key, {
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'value': value,
    });
  }

  Future<void> saveJobDetails(int jobId, Map<String, dynamic> details) async {
    await saveMap('job_details_$jobId', details);
  }

  Map<String, dynamic>? getJobDetails(int jobId) {
    return getMap('job_details_$jobId');
  }

  Map<String, dynamic>? getMap(String key) {
    final cached = _box.get(key);
    if (cached is! Map || cached['value'] is! Map) return null;
    return _stringKeyedMap(cached['value'] as Map);
  }

  Future<void> saveDutyStatus(int userId, bool isCheckedIn) async {
    await _box.put('duty_status_$userId', isCheckedIn);
  }

  bool getDutyStatus(int userId) {
    return _box.get('duty_status_$userId', defaultValue: false) == true;
  }

  Future<void> updateTask(
    int userId,
    int taskId,
    Map<String, dynamic> updates,
  ) async {
    final prefixes = ['my_tasks_${userId}_', 'available_tasks_$userId'];
    for (final key in _box.keys.whereType<String>()) {
      if (!prefixes.any(key.startsWith)) continue;

      final records = getTasks(key);
      var changed = false;
      final updatedRecords = records.map((record) {
        if (record['id'] != taskId) return record;
        changed = true;
        return <String, dynamic>{...record, ...updates};
      }).toList();

      if (changed) await saveTasks(key, updatedRecords);
    }
  }

  Future<void> finishTaskTimer(
    int userId,
    int taskId, {
    required DateTime stoppedAt,
    String? status,
  }) async {
    final prefixes = ['my_tasks_${userId}_', 'available_tasks_$userId'];
    for (final key in _box.keys.whereType<String>()) {
      if (!prefixes.any(key.startsWith)) continue;

      final records = getTasks(key);
      var changed = false;
      final updatedRecords = records.map((record) {
        if (record['id'] != taskId) return record;
        changed = true;

        final startedValue = record['current_log_start'];
        final startedAt = startedValue is String
            ? DateTime.tryParse(
                startedValue.endsWith('Z') ? startedValue : '${startedValue}Z')
            : null;
        final previousHours =
            (record['actual_hours'] as num?)?.toDouble() ?? 0.0;
        final elapsedHours = startedAt == null
            ? 0.0
            : stoppedAt.difference(startedAt.toUtc()).inMilliseconds /
                Duration.millisecondsPerHour;

        return <String, dynamic>{
          ...record,
          if (status != null) 'status': status,
          'actual_hours': previousHours + elapsedHours.clamp(0.0, 24.0),
          'is_working': false,
          'current_log_start': false,
        };
      }).toList();

      if (changed) await saveTasks(key, updatedRecords);
    }
  }

  Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> source) {
    return source.map(
      (key, value) => MapEntry(key.toString(), _normalizeValue(value)),
    );
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is Map) return _stringKeyedMap(value);
    if (value is List) return value.map(_normalizeValue).toList();
    return value;
  }
}
