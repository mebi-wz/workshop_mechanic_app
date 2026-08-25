import 'package:equatable/equatable.dart';

class WorkshopTask extends Equatable {
  final int id;
  final String description;
  final double estimatedHours;
  final double actualHours;
  final String status;
  final bool isWorking;
  final DateTime? currentLogStart;
  final String? technicianName;
  final String? sectionName;
  final int? jobId;
  final String? jobName;
  final String? notes;
  final String? mrcvStatus;
  final String? mrcvRef;
  final bool isFieldWork;

  const WorkshopTask({
    required this.id,
    required this.description,
    this.estimatedHours = 0.0,
    this.actualHours = 0.0,
    required this.status,
    this.isWorking = false,
    this.currentLogStart,
    this.technicianName,
    this.sectionName,
    this.jobId,
    this.jobName,
    this.notes,
    this.mrcvStatus,
    this.mrcvRef,
    this.isFieldWork = false,
  });

  bool get isCompleted => ['completed', 'reviewed', 'closed'].contains(status);
  bool get canStartTimer => !isWorking && !isCompleted;

  String get statusLabel {
    const labels = {
      'created': 'Created',
      'assigned': 'Assigned',
      'working': 'In Progress',
      'completed': 'Completed',
      'reviewed': 'Reviewed',
      'closed': 'Closed',
    };
    return labels[status] ?? status;
  }

  factory WorkshopTask.fromOdoo(Map<String, dynamic> json) {
    int? jobId;
    String? jobName;
    if (json['job_id'] is List && (json['job_id'] as List).length == 2) {
      jobId = (json['job_id'] as List)[0] as int;
      jobName = (json['job_id'] as List)[1] as String;
    }

    String? technicianName;
    if (json['technician_id'] is List &&
        (json['technician_id'] as List).length == 2) {
      technicianName = (json['technician_id'] as List)[1] as String;
    }

    String? sectionName;
    if (json['workshop_section_id'] is List &&
        (json['workshop_section_id'] as List).length == 2) {
      sectionName = (json['workshop_section_id'] as List)[1] as String;
    }

    DateTime? logStart;
    if (json['current_log_start'] is String) {
      final str = json['current_log_start'] as String;
      logStart = DateTime.tryParse(str.endsWith('Z') ? str : '${str}Z');
    }

    String? mrcvStatus;
    String? mrcvRef;
    if (json['mrcv_status'] is String) {
      mrcvStatus = json['mrcv_status'] as String;
    }
    if (json['mrcv_ref'] is String) {
      mrcvRef = json['mrcv_ref'] as String;
    }

    String? parseString(dynamic val) {
      if (val is String) return val;
      return null;
    }

    return WorkshopTask(
      id: json['id'] as int,
      description: parseString(json['description']) ?? '',
      estimatedHours: (json['estimated_hours'] as num?)?.toDouble() ?? 0.0,
      actualHours: (json['actual_hours'] as num?)?.toDouble() ?? 0.0,
      status: parseString(json['status']) ?? 'created',
      isWorking: json['is_working'] as bool? ?? false,
      currentLogStart: logStart,
      technicianName: technicianName,
      sectionName: sectionName,
      jobId: jobId,
      jobName: jobName,
      notes: parseString(json['notes']),
      mrcvStatus: mrcvStatus,
      mrcvRef: mrcvRef,
      isFieldWork: json['is_field_work'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id, status, isWorking, actualHours, mrcvStatus, isFieldWork];
}
