import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/app_locale.dart';
import '../domain/models/workshop_task.dart';
import 'field_work_report_sheet.dart';

class TaskCard extends StatefulWidget {
  final WorkshopTask task;
  final bool isProcessing;
  final bool isCheckedIn;
  final VoidCallback onStartTimer;
  final VoidCallback onStopTimer;
  final VoidCallback onMarkDone;
  final VoidCallback? onTakeTask;
  final VoidCallback? onRequestOutsource;
  final VoidCallback? onRequestMrcv;

  const TaskCard({
    super.key,
    required this.task,
    required this.isProcessing,
    this.isCheckedIn = true,
    required this.onStartTimer,
    required this.onStopTimer,
    required this.onMarkDone,
    this.onTakeTask,
    this.onRequestOutsource,
    this.onRequestMrcv,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void didUpdateWidget(covariant TaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.isWorking != widget.task.isWorking ||
        oldWidget.task.currentLogStart != widget.task.currentLogStart) {
      _ticker?.cancel();
      _startTicker();
    }
  }

  void _startTicker() {
    final startedAt = widget.task.currentLogStart;
    if (!widget.task.isWorking || startedAt == null) return;
    _elapsed = DateTime.now().toUtc().difference(startedAt.toUtc());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final accent = _statusColor(task.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: task.isWorking
              ? context.appColors.success.withValues(alpha: .55)
              : context.appColors.border,
          width: task.isWorking ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    task.isWorking
                        ? Icons.build_circle_rounded
                        : Icons.assignment_outlined,
                    color: accent,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.jobName ?? 'Workshop task #${task.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        task.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appColors.text,
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StatusPill(label: _statusLabel(context, task), color: accent),
              ],
            ),
            if (task.isWorking) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    context.appColors.success.withValues(alpha: .16),
                    context.appColors.success.withValues(alpha: .05),
                  ]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const _PulseDot(),
                    const SizedBox(width: 10),
                    Text(
                      context.tr('workTimer'),
                      style: TextStyle(
                        color: context.appColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDuration(_elapsed),
                      style: TextStyle(
                        color: context.appColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: context.tr('estimated'),
                    value: '${_formatHours(task.estimatedHours)} h',
                    icon: Icons.schedule_rounded,
                  ),
                ),
                Container(
                    width: 1, height: 30, color: context.appColors.border),
                Expanded(
                  child: _Metric(
                    label: context.tr('logged'),
                    value:
                        '${_formatHours(task.actualHours + (task.isWorking ? _elapsed.inSeconds / 3600 : 0))} h',
                    icon: Icons.timer_outlined,
                  ),
                ),
              ],
            ),
            if (task.sectionName != null || task.mrcvStatus != null || task.isFieldWork) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (task.isFieldWork)
                    const _InfoChip(
                      icon: Icons.near_me_outlined,
                      label: 'FIELD WORK',
                      color: Color(0xFF00B4D8),
                    )
                  else
                    _InfoChip(
                      icon: Icons.build_circle_outlined,
                      label: 'WORKSHOP',
                      color: context.appColors.primary,
                    ),
                  if (task.sectionName != null)
                    _InfoChip(
                        icon: Icons.precision_manufacturing_outlined,
                        label: task.sectionName!),
                  if (task.mrcvStatus != null)
                    _InfoChip(
                      icon: Icons.inventory_2_outlined,
                      label:
                          '${task.mrcvRef ?? 'Material'} · ${task.mrcvStatus!.toUpperCase()}',
                      color: context.appColors.warning,
                    ),
                ],
              ),
            ],
            if (widget.onTakeTask != null || !task.isCompleted) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),
              if (widget.onTakeTask != null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.isProcessing ? null : widget.onTakeTask,
                    icon: _buttonIcon(Icons.add_task_rounded),
                    label: Text(context.tr('takeTask')),
                  ),
                )
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: Builder(
                    builder: (context) {
                      final requiresCheckIn = task.isFieldWork;
                      final canStart = !requiresCheckIn || widget.isCheckedIn;

                      return ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: task.isWorking
                              ? context.appColors.warning
                              : canStart
                                  ? context.appColors.success
                                  : context.appColors.textMuted,
                          foregroundColor: context.appColors.background,
                        ),
                        onPressed: widget.isProcessing
                            ? null
                            : task.isWorking
                                ? widget.onStopTimer
                                : () {
                                    if (!canStart) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please check in before starting Field Work.'),
                                          backgroundColor: Colors.orange,
                                          duration: Duration(seconds: 3),
                                        ),
                                      );
                                      return;
                                    }
                                    widget.onStartTimer();
                                  },
                        icon: _buttonIcon(task.isWorking
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded),
                        label: Text(task.isWorking
                            ? context.tr('stopWorkTimer')
                            : context.tr('startWork')),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (task.status == 'working')
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              widget.isProcessing ? null : widget.onMarkDone,
                          icon: const Icon(Icons.task_alt_rounded, size: 18),
                          label: Text(context.tr('complete')),
                        ),
                      ),
                    if (task.status == 'working' &&
                        (widget.onRequestMrcv != null ||
                            widget.onRequestOutsource != null))
                      const SizedBox(width: 8),
                    if (widget.onRequestMrcv != null)
                      _SecondaryAction(
                        tooltip: context.tr('requestMaterial'),
                        icon: Icons.inventory_2_outlined,
                        onPressed: widget.onRequestMrcv!,
                      ),
                    if (widget.onRequestOutsource != null) ...[
                      const SizedBox(width: 8),
                      _SecondaryAction(
                        tooltip: context.tr('requestOutsource'),
                        icon: Icons.north_east_rounded,
                        onPressed: widget.onRequestOutsource!,
                      ),
                    ],
                  ],
                ),
                if (task.isFieldWork && task.jobId != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00B4D8),
                        side: const BorderSide(color: Color(0xFF00B4D8)),
                      ),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => FieldWorkReportSheet(task: task),
                        );
                      },
                      icon: const Icon(Icons.note_add_outlined, size: 18),
                      label: const Text('Report Discovered Tasks & PMS'),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buttonIcon(IconData icon) {
    if (widget.isProcessing) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(icon, size: 20);
  }

  Color _statusColor(String status) => switch (status) {
        'working' => context.appColors.success,
        'assigned' => context.appColors.primary,
        'completed' || 'reviewed' => const Color(0xFFAD8CFF),
        'closed' => context.appColors.textSubtle,
        _ => context.appColors.textMuted,
      };

  String _statusLabel(BuildContext context, WorkshopTask task) {
    return switch (task.status) {
      'assigned' => context.tr('assigned'),
      'working' => context.tr('inProgress'),
      'completed' => context.tr('completed'),
      _ => task.statusLabel,
    };
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatHours(double hours) {
    if (hours == 0) return '0';
    return hours.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: context.appColors.success,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: context.appColors.success.withValues(alpha: .45),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Metric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: context.appColors.textSubtle),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: context.appColors.textSubtle, fontSize: 10)),
              Text(value,
                  style: TextStyle(
                      color: context.appColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? context.appColors.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color ?? context.appColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class _SecondaryAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  const _SecondaryAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => IconButton.outlined(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
      );
}
