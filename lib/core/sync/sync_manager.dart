import 'dart:async';
import 'dart:convert';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:workshop_mechanic/core/database/database_helper.dart';
import 'package:workshop_mechanic/core/network/odoo_client.dart';
import 'package:logger/logger.dart';

enum SyncFailureKind { permissionDenied, serverRejected }

class SyncResult {
  final bool hasNetwork;
  final int syncedCount;
  final int remainingCount;
  final SyncFailureKind? failureKind;
  final String? failedActionType;

  const SyncResult({
    required this.hasNetwork,
    required this.syncedCount,
    required this.remainingCount,
    this.failureKind,
    this.failedActionType,
  });
}

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  final _dbHelper = DatabaseHelper();
  late OdooClient _client;
  final _logger = Logger();

  StreamSubscription<InternetStatus>? _connectivitySubscription;
  Timer? _automaticSyncTimer;
  final _connectionController = StreamController<bool>.broadcast();
  final _syncResultController = StreamController<SyncResult>.broadcast();
  bool _isOnline = true;
  bool _isSyncing = false;

  Future<void> initialize(OdooClient client) async {
    _client = client;
    await _checkInitialConnectivity();
    _connectivitySubscription =
        InternetConnection().onStatusChange.listen(_updateConnectionStatus);
    _automaticSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isOnline && !_isSyncing && _client.session != null) {
        syncPendingActions();
      }
    });
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _automaticSyncTimer?.cancel();
  }

  bool get isOnline => _isOnline;
  Stream<bool> get connectionChanges => _connectionController.stream;
  Stream<SyncResult> get syncResults => _syncResultController.stream;

  Future<void> _checkInitialConnectivity() async {
    final hasInternet = await InternetConnection().hasInternetAccess;
    _updateConnectionStatus(
      hasInternet ? InternetStatus.connected : InternetStatus.disconnected,
    );
  }

  void _updateConnectionStatus(
    InternetStatus status, {
    bool syncWhenRestored = true,
  }) {
    final online = status == InternetStatus.connected;
    final changed = online != _isOnline;
    if (online && !_isOnline) {
      _logger.i('Network restored. Starting sync...');
      _isOnline = true;
      if (syncWhenRestored) syncPendingActions();
    } else {
      _isOnline = online;
    }
    if (changed) _connectionController.add(_isOnline);
  }

  Future<int> getPendingCount() => _dbHelper.getPendingActionCount();

  Future<SyncResult> manualSync() async {
    final hasInternet = await InternetConnection().hasInternetAccess;
    _updateConnectionStatus(
      hasInternet ? InternetStatus.connected : InternetStatus.disconnected,
      syncWhenRestored: false,
    );
    return syncPendingActions();
  }

  Future<SyncResult> syncPendingActions() async {
    final pendingBefore = await _dbHelper.getPendingActionCount();
    if (!_isOnline || _isSyncing || _client.session == null) {
      return SyncResult(
        hasNetwork: _isOnline,
        syncedCount: 0,
        remainingCount: pendingBefore,
      );
    }

    _isSyncing = true;
    var syncedCount = 0;
    SyncFailureKind? failureKind;
    String? failedActionType;
    try {
      final actions = await _dbHelper.getPendingActions();

      for (var action in actions) {
        final id = action['id'] as int;
        final type = action['action_type'] as String;
        final taskId = action['task_id'] as int;
        final payload = _parsePayload(action['payload'] as String? ?? '');
        final eventTimestamp =
            payload['timestamp'] ?? action['created_at'] as String?;

        try {
          if (type == 'claim') {
            await _client.callKw(
              model: 'workshop.task',
              method: 'action_take_task',
              args: [
                [taskId]
              ],
            );
          } else if (type == 'start_timer') {
            await _client.callKw(
              model: 'workshop.task',
              method: 'action_start_timer',
              args: [
                [taskId],
                eventTimestamp,
              ],
            );
          } else if (type == 'stop_timer') {
            await _client.callKw(
              model: 'workshop.task',
              method: 'action_stop_timer',
              args: [
                [taskId],
                eventTimestamp,
              ],
            );
          } else if (type == 'mark_done') {
            await _client.callKw(
              model: 'workshop.task',
              method: 'action_done',
              args: [
                [taskId],
                eventTimestamp,
              ],
            );
          } else if (type == 'check_in') {
            final p = action['payload'] as String;
            final map = _parsePayload(p);
            await _client.callKw(
              model: 'workshop.duty.log',
              method: 'action_mobile_check_in',
              args: [map['lat'], map['lng'], map['timestamp']],
            );
          } else if (type == 'check_out') {
            final p = action['payload'] as String;
            final map = _parsePayload(p);
            await _client.callKw(
              model: 'workshop.duty.log',
              method: 'action_mobile_check_out',
              args: [map['lat'], map['lng'], map['timestamp']],
            );
          } else if (type == 'select_pms_interval') {
            final p = action['payload'] as String;
            final map = _parsePayload(p);
            await _client.callKw(
              model: 'workshop.order',
              method: 'action_select_pms_interval',
              args: [
                [taskId],
                map['km']
              ],
            );
          } else if (type == 'proceed_pms_replacement') {
            await _client.callKw(
              model: 'workshop.order',
              method: 'action_proceed_pms_replacement',
              args: [
                [taskId]
              ],
            );
          } else if (type == 'save_field_notes') {
            final p = action['payload'] as String;
            final map = _parsePayload(p);
            final writeVals = <String, dynamic>{};
            if (map.containsKey('remark')) writeVals['remark'] = map['remark'];
            if (map.containsKey('missing_parts')) writeVals['missing_parts'] = map['missing_parts'];

            await _client.callKw(
              model: 'workshop.order',
              method: 'write',
              args: [
                [taskId],
                writeVals,
              ],
            );
          }

          await _dbHelper.markActionCompleted(id);
          syncedCount++;
          _logger.i('Successfully synced action $id ($type) for task $taskId');
        } catch (e) {
          final errorText = e.toString().toLowerCase();
          failureKind = errorText.contains('not allowed') ||
                  errorText.contains('accesserror') ||
                  errorText.contains('permission')
              ? SyncFailureKind.permissionDenied
              : SyncFailureKind.serverRejected;
          failedActionType = type;
          _logger.w('Sync rejected for action $id ($type): $e');
          // Preserve queue order. A later action (for example check-out) must
          // never overtake an earlier action (for example check-in).
          break;
        }
      }
    } finally {
      _isSyncing = false;
    }

    final result = SyncResult(
      hasNetwork: true,
      syncedCount: syncedCount,
      remainingCount: await _dbHelper.getPendingActionCount(),
      failureKind: failureKind,
      failedActionType: failedActionType,
    );
    _syncResultController.add(result);
    return result;
  }

  Map<String, dynamic> _parsePayload(String payload) {
    try {
      return jsonDecode(payload);
    } catch (_) {
      return {};
    }
  }
}
