import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/odoo_client.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/hive_task_cache.dart';
import '../domain/models/workshop_task.dart';

class FieldWorkReportSheet extends StatefulWidget {
  final WorkshopTask task;

  const FieldWorkReportSheet({super.key, required this.task});

  @override
  State<FieldWorkReportSheet> createState() => _FieldWorkReportSheetState();
}

class _FieldWorkReportSheetState extends State<FieldWorkReportSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _orderDetails;
  List<Map<String, dynamic>> _previewTasks = [];
  bool _isLoadingPreview = false;

  final _remarkController = TextEditingController();
  final _missingPartsController = TextEditingController();
  bool _isSavingNotes = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchJobOrderDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _remarkController.dispose();
    _missingPartsController.dispose();
    super.dispose();
  }

  Future<void> _fetchJobOrderDetails() async {
    final jobId = widget.task.jobId;
    if (jobId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Task is not linked to any Job Order.";
      });
      return;
    }

    final isOnline = SyncManager().isOnline;
    final cachedDetails = sl<HiveTaskCache>().getJobDetails(jobId);

    if (!isOnline && cachedDetails != null) {
      if (mounted) {
        setState(() {
          _orderDetails = cachedDetails;
          _remarkController.text =
              cachedDetails['remark'] is String ? cachedDetails['remark'] as String : '';
          _missingPartsController.text =
              cachedDetails['missing_parts'] is String ? cachedDetails['missing_parts'] as String : '';
          _isLoading = false;
        });
        final selectedKm = cachedDetails['selected_pms_interval'];
        if (selectedKm is int) _fetchPreviewTasks(selectedKm);
      }
      return;
    }

    try {
      final client = sl<OdooClient>();
      final records = await client.searchRead(
        model: 'workshop.order',
        domain: [
          ['id', '=', jobId]
        ],
        fields: [
          'id',
          'name',
          'vehicle_id',
          'selected_pms_interval',
          'nearest_pms_interval',
          'show_pms_warning',
          'remark',
          'missing_parts',
          'task_ids',
        ],
        limit: 1,
      );

      if (records.isNotEmpty) {
        final order = records.first;
        _remarkController.text =
            order['remark'] is String ? order['remark'] as String : '';
        _missingPartsController.text =
            order['missing_parts'] is String ? order['missing_parts'] as String : '';

        final taskIds = order['task_ids'] is List ? (order['task_ids'] as List).cast<int>() : <int>[];
        List<Map<String, dynamic>> tasksList = [];
        if (taskIds.isNotEmpty) {
          tasksList = await client.searchRead(
            model: 'workshop.task',
            domain: [
              ['id', 'in', taskIds]
            ],
            fields: [
              'id',
              'description',
              'status',
              'is_field_reported',
              'estimated_hours',
              'technician_id',
              'notes',
            ],
          );
        }

        order['tasks_list'] = tasksList;
        await sl<HiveTaskCache>().saveJobDetails(jobId, order);

        if (mounted) {
          setState(() {
            _orderDetails = order;
            _isLoading = false;
          });

          final selectedKm = order['selected_pms_interval'];
          if (selectedKm != null && selectedKm is int) {
            _fetchPreviewTasks(selectedKm);
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "Job Order record not found.";
          });
        }
      }
    } catch (e) {
      if (cachedDetails != null && mounted) {
        setState(() {
          _orderDetails = cachedDetails;
          _remarkController.text =
              cachedDetails['remark'] is String ? cachedDetails['remark'] as String : '';
          _isLoading = false;
        });
        final selectedKm = cachedDetails['selected_pms_interval'];
        if (selectedKm is int) _fetchPreviewTasks(selectedKm);
        return;
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to load job details: $e";
        });
      }
    }
  }

  Future<void> _fetchPreviewTasks(int km) async {
    setState(() => _isLoadingPreview = true);
    final jobId = widget.task.jobId;
    final cacheKey = 'pms_preview_${jobId}_$km';
    final isOnline = SyncManager().isOnline;
    final cachedPreview = sl<HiveTaskCache>().getMap(cacheKey);

    if (!isOnline && cachedPreview != null) {
      if (mounted) {
        final items = (cachedPreview['items'] as List? ?? []).cast<Map<String, dynamic>>();
        setState(() {
          _previewTasks = items;
          _isLoadingPreview = false;
        });
      }
      return;
    }

    try {
      final client = sl<OdooClient>();
      final lines = await client.searchRead(
        model: 'workshop.pm.interval.line',
        domain: [
          ['interval', '=', km],
          ['action', 'in', ['R', 'I', 'A', 'C']]
        ],
        fields: ['item_id', 'action'],
      );

      List<Map<String, dynamic>> items = [];
      for (final line in lines) {
        final itemVal = line['item_id'];
        int? itemId;
        String itemName = '';
        if (itemVal is List && itemVal.length == 2) {
          itemId = itemVal[0] as int;
          itemName = itemVal[1] as String;
        }

        String serviceInterval = 'Regular Check';
        if (itemId != null) {
          final itemRecs = await client.searchRead(
            model: 'workshop.pm.item',
            domain: [
              ['id', '=', itemId]
            ],
            fields: ['instruction', 'description'],
            limit: 1,
          );
          if (itemRecs.isNotEmpty) {
            final inst = itemRecs.first['instruction'];
            if (inst is String && inst.isNotEmpty) {
              serviceInterval = inst;
            }
          }
        }

        final code = line['action'] as String?;
        String actionName = 'Check';
        if (code == 'R') actionName = 'Replace';
        if (code == 'I') actionName = 'Inspect';
        if (code == 'A') actionName = 'Adjust';
        if (code == 'C') actionName = 'Clean';

        items.add({
          'description': itemName,
          'action_label': '$actionName $itemName',
          'service_interval': serviceInterval,
          'action': code,
        });
      }

      await sl<HiveTaskCache>().saveMap(cacheKey, {'items': items});

      if (mounted) {
        setState(() {
          _previewTasks = items;
          _isLoadingPreview = false;
        });
      }
    } catch (_) {
      if (cachedPreview != null && mounted) {
        final items = (cachedPreview['items'] as List? ?? []).cast<Map<String, dynamic>>();
        setState(() {
          _previewTasks = items;
          _isLoadingPreview = false;
        });
        return;
      }
      if (mounted) {
        setState(() {
          _previewTasks = [];
          _isLoadingPreview = false;
        });
      }
    }
  }

  Future<void> _selectPmsInterval(int km) async {
    setState(() => _isLoading = true);
    final isOnline = SyncManager().isOnline;
    if (!isOnline) {
      await DatabaseHelper().queueAction(
        'select_pms_interval',
        widget.task.jobId!,
        payload: jsonEncode({'km': km}),
      );
      if (mounted) {
        setState(() {
          _orderDetails?['selected_pms_interval'] = km;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline: PMS interval queued for sync.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    try {
      final client = sl<OdooClient>();
      await client.callKw(
        model: 'workshop.order',
        method: 'action_select_pms_interval',
        args: [
          [widget.task.jobId!],
          km
        ],
      );
      await _fetchJobOrderDetails();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select interval: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _proceedAndReplaceTasks() async {
    setState(() => _isLoading = true);
    final isOnline = SyncManager().isOnline;
    if (!isOnline) {
      await DatabaseHelper().queueAction(
        'proceed_pms_replacement',
        widget.task.jobId!,
      );

      final selectedKm = _orderDetails?['selected_pms_interval'] ?? 0;
      final newPmsTasks = _previewTasks.map((pt) {
        return {
          'id': DateTime.now().millisecondsSinceEpoch,
          'description': 'PMS ($selectedKm KM): ${pt['action_label'] ?? pt['description']}',
          'status': 'created',
          'is_field_reported': true,
          'estimated_hours': 1.0,
        };
      }).toList();

      if (_orderDetails != null) {
        final existingList = (_orderDetails!['tasks_list'] as List? ?? []).cast<Map<String, dynamic>>();
        // Retain assigned tasks (where technician_id is assigned or task is already in progress/done)
        final assignedTasks = existingList.where((t) {
          final hasTech = t['technician_id'] != null && t['technician_id'] != false;
          final isNotCreated = t['status'] != 'created';
          return hasTech || isNotCreated;
        }).toList();

        final mergedTasks = [...assignedTasks, ...newPmsTasks];
        _orderDetails!['tasks_list'] = mergedTasks;
        await sl<HiveTaskCache>().saveJobDetails(widget.task.jobId!, _orderDetails!);
      }

      if (mounted) {
        _tabController.animateTo(0);
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline: PMS Tasks replaced locally & queued for sync.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    try {
      final client = sl<OdooClient>();
      await client.callKw(
        model: 'workshop.order',
        method: 'action_proceed_pms_replacement',
        args: [
          [widget.task.jobId!]
        ],
      );
      await _fetchJobOrderDetails();
      if (mounted) {
        _tabController.animateTo(0);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PMS Tasks successfully updated & replaced in Checklist!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to replace tasks: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveFieldNotes() async {
    setState(() => _isSavingNotes = true);
    final remarkText = _remarkController.text;
    final missingPartsText = _missingPartsController.text;
    final isOnline = SyncManager().isOnline;

    if (!isOnline) {
      await DatabaseHelper().queueAction(
        'save_field_notes',
        widget.task.jobId!,
        payload: jsonEncode({
          'remark': remarkText,
          'missing_parts': missingPartsText,
        }),
      );

      if (_orderDetails != null) {
        _orderDetails!['remark'] = remarkText;
        _orderDetails!['missing_parts'] = missingPartsText;
        await sl<HiveTaskCache>().saveJobDetails(widget.task.jobId!, _orderDetails!);
      }

      if (mounted) {
        setState(() {
          _isSavingNotes = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline: Field Notes saved locally & queued for sync.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pop(true);
      }
      return;
    }

    try {
      final client = sl<OdooClient>();
      await client.callKw(
        model: 'workshop.order',
        method: 'write',
        args: [
          [widget.task.jobId!],
          {
            'remark': remarkText,
            'missing_parts': missingPartsText,
          }
        ],
      );

      if (_orderDetails != null) {
        _orderDetails!['remark'] = remarkText;
        _orderDetails!['missing_parts'] = missingPartsText;
        await sl<HiveTaskCache>().saveJobDetails(widget.task.jobId!, _orderDetails!);
      }

      if (mounted) {
        setState(() {
          _isSavingNotes = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Field Notes saved successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save field notes: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingNotes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.appColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B4D8).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.assignment_outlined,
                      color: Color(0xFF00B4D8)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Report Discovered Tasks',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.appColors.text,
                        ),
                      ),
                      Text(
                        widget.task.jobName ?? 'Field Job',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: context.appColors.primary,
            unselectedLabelColor: context.appColors.textMuted,
            indicatorColor: context.appColors.primary,
            tabs: const [
              Tab(
                  icon: Icon(Icons.checklist_rounded, size: 18),
                  text: 'Checklist'),
              Tab(
                  icon: Icon(Icons.insert_chart_outlined, size: 18),
                  text: 'PMS Charts'),
              Tab(
                  icon: Icon(Icons.note_alt_outlined, size: 18),
                  text: 'Field Notes'),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTasksChecklistTab(),
                          _buildPmsChartTab(),
                          _buildFieldNotesTab(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksChecklistTab() {
    final tasks = (_orderDetails?['tasks_list'] as List? ?? []);
    if (tasks.isEmpty) {
      return const Center(child: Text('No tasks found in checklist.'));
    }
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).viewPadding.bottom;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final t = tasks[index];
        final isReported = t['is_field_reported'] == true;
        return ListTile(
          leading: Icon(
            isReported ? Icons.add_task_rounded : Icons.task_outlined,
            color: isReported ? Colors.orange : context.appColors.primary,
          ),
          title: Text(
            t['description'] is String ? t['description'] as String : '',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text('Status: ${t['status']}'),
          trailing: isReported
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'On-Site Reported',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildPmsChartTab() {
    final showWarning = _orderDetails?['show_pms_warning'] == true;
    final selectedKm = _orderDetails?['selected_pms_interval'] ?? 0;
    final nearestKm = _orderDetails?['nearest_pms_interval'] ?? 0;

    final intervals = [
      5000,
      10000,
      15000,
      20000,
      25000,
      30000,
      35000,
      40000,
      45000,
      50000,
      55000,
      60000
    ];

    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).viewPadding.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Preventive Maintenance Interval (KM)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: intervals.map((km) {
              final isSelected = selectedKm == km;
              final isNearest = nearestKm == km;
              return ChoiceChip(
                label: Text('${km ~/ 1000}k KM'),
                selected: isSelected,
                selectedColor: context.appColors.primary,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : context.appColors.text,
                  fontWeight: isNearest ? FontWeight.bold : FontWeight.normal,
                ),
                avatar: isNearest
                    ? const Icon(Icons.star_rounded,
                        size: 16, color: Colors.amber)
                    : null,
                onSelected: (_) => _selectPmsInterval(km),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // PREVIEW OF TASKS FOR SELECTED KM
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.appColors.surfaceHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.appColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.list_alt_rounded, size: 18, color: Color(0xFF00B4D8)),
                    const SizedBox(width: 8),
                    Text(
                      'Maintenance Items & Service Intervals (${selectedKm ~/ 1000}k KM)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_isLoadingPreview)
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_previewTasks.isEmpty)
                  Text(
                    'No maintenance items or service interval rules configured for this interval.',
                    style: TextStyle(color: context.appColors.textMuted, fontSize: 12),
                  )
                else
                  Column(
                    children: _previewTasks.map((pt) {
                      final actionCode = pt['action'] as String?;
                      final color = actionCode == 'R'
                          ? Colors.red
                          : actionCode == 'I'
                              ? Colors.blue
                              : Colors.orange;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.appColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.appColors.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                actionCode ?? '•',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pt['description'] as String,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.repeat_rounded,
                                          size: 13, color: context.appColors.textMuted),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Service Interval: ${pt['service_interval']}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: context.appColors.textMuted,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),

          if (showWarning) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFE0B2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFE6A100)),
                      SizedBox(width: 8),
                      Text(
                        'Odometer Mismatch Warning',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB78103),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'You selected ${selectedKm ~/ 1000}k KM, which differs from the nearest odometer reading of ${nearestKm ~/ 1000}k KM. Review the tasks above before replacing.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB78103),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.appColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isLoading ? null : _proceedAndReplaceTasks,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Proceed & Replace Tasks'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldNotesTab() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).viewPadding.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Missing / Damaged Parts Observed On-Site',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _missingPartsController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'List any missing or damaged parts...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Field Technician Inspection Notes / Remarks',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _remarkController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Enter technical inspection findings or remarks...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.appColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isSavingNotes ? null : _saveFieldNotes,
              icon: _isSavingNotes
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded),
              label: const Text('Save Field Notes'),
            ),
          ),
        ],
      ),
    );
  }
}
