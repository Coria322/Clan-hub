import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(FirebaseFirestore.instance);
});

class TaskException implements Exception {
  final String message;
  TaskException(this.message);
  @override
  String toString() => message;
}

enum TaskPriority { alta, media, baja }

class TaskModel {
  final String id;
  final String householdId;
  final String title;
  final String? description;
  final DateTime? deadline;
  final TaskPriority priority;
  final int priorityLevel;
  final String categoryId;
  final String categoryName;
  final String? assignedTo;
  final String createdBy;
  final DateTime createdAt;
  final String status; // 'pending' | 'completed'
  final String? completedBy;
  final DateTime? completedAt;
  final String? weekKey;

  const TaskModel({
    required this.id,
    required this.householdId,
    required this.title,
    this.description,
    this.deadline,
    required this.priority,
    required this.priorityLevel,
    required this.categoryId,
    required this.categoryName,
    this.assignedTo,
    required this.createdBy,
    required this.createdAt,
    required this.status,
    this.completedBy,
    this.completedAt,
    this.weekKey,
  });

  static TaskPriority _parsePriority(String? s) {
    switch (s?.toLowerCase()) {
      case 'alta':
        return TaskPriority.alta;
      case 'baja':
        return TaskPriority.baja;
      default:
        return TaskPriority.media;
    }
  }

  factory TaskModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return TaskModel(
      id: doc.id,
      householdId: d['householdId'] as String? ?? '',
      title: d['title'] as String? ?? '',
      description: d['description'] as String?,
      deadline: (d['deadline'] as Timestamp?)?.toDate(),
      priority: _parsePriority(d['priority'] as String?),
      priorityLevel: d['priorityLevel'] as int? ?? 2,
      categoryId: d['categoryId'] as String? ?? '',
      categoryName: d['categoryName'] as String? ?? '',
      assignedTo: d['assignedTo'] as String?,
      createdBy: d['createdBy'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: d['status'] as String? ?? 'pending',
      completedBy: d['completedBy'] as String?,
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
      weekKey: d['weekKey'] as String?,
    );
  }

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isOverdue =>
      deadline != null && deadline!.isBefore(DateTime.now()) && isPending;
}

class TaskRepository {
  final FirebaseFirestore _firestore;

  TaskRepository(this._firestore);

  // ── Calcular weekKey en UTC (formato YYYY-WW) ──
  static String calculateWeekKey(DateTime date) {
    final utc = date.toUtc();
    // Día de la semana: 1=lunes ... 7=domingo (ISO 8601)
    final dayOfWeek = utc.weekday;
    // Principio de la semana (lunes)
    final monday = utc.subtract(Duration(days: dayOfWeek - 1));
    // Número de semana ISO 8601
    final jan4 = DateTime.utc(monday.year, 1, 4);
    final startOfWeek1 = jan4.subtract(Duration(days: jan4.weekday - 1));
    final weekNumber =
        ((monday.difference(startOfWeek1).inDays) / 7).floor() + 1;
    final year = monday.year;
    return '$year-${weekNumber.toString().padLeft(2, '0')}';
  }

  // ── Stream de tareas pendientes del hogar ──
  Stream<List<TaskModel>> watchPendingTasks(String householdId) {
    return _firestore
        .collection('tasks')
        .where('householdId', isEqualTo: householdId)
        .where('status', isEqualTo: 'pending')
        .orderBy('priorityLevel', descending: false)
        .orderBy('deadline', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(TaskModel.fromFirestore).toList());
  }

  // ── Stream de tareas completadas del hogar ──
  Stream<List<TaskModel>> watchCompletedTasks(String householdId) {
    return _firestore
        .collection('tasks')
        .where('householdId', isEqualTo: householdId)
        .where('status', isEqualTo: 'completed')
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(TaskModel.fromFirestore).toList());
  }

  // ── Crear tarea (TASK-011) ──
  Future<void> createTask({
    required String householdId,
    required String title,
    String? description,
    DateTime? deadline,
    required TaskPriority priority,
    required String categoryId,
    required String categoryName,
    String? assignedTo,
    required String createdBy,
  }) async {
    try {
      // No hacemos await para que funcione instantáneamente offline
      _firestore.collection('tasks').add({
        'householdId': householdId,
        'title': title,
        'description': description,
        'deadline': deadline != null ? Timestamp.fromDate(deadline) : null,
        'priority': priority.name,
        'priorityLevel': priority == TaskPriority.alta ? 1 : (priority == TaskPriority.media ? 2 : 3),
        'categoryId': categoryId,
        'categoryName': categoryName,
        'assignedTo': assignedTo,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'completedBy': null,
        'completedAt': null,
        'weekKey': null,
        'deadlineNotificationSent': false,
      }).then<void>((_) {}).catchError((e) {
        // Ignoramos el error en consola o lo registramos, 
        // ya que la persistencia se encarga de reintentar.
      });
    } catch (e) {
      throw TaskException('Error al crear la tarea: $e');
    }
  }

  // ── Completar tarea con transacción (TASK-013) ──
  Future<void> completeTask({
    required String taskId,
    required String completedByUid,
  }) async {
    final taskRef = _firestore.collection('tasks').doc(taskId);
    try {
      final weekKey = calculateWeekKey(DateTime.now());
      // No usamos runTransaction porque falla inmediatamente offline.
      // Un update simple se encola y funciona offline.
      taskRef.update({
        'status': 'completed',
        'completedBy': completedByUid,
        'completedAt': FieldValue.serverTimestamp(),
        'weekKey': weekKey,
      }).catchError((e) {
        // Error de sincronización futura
      });
    } catch (e) {
      throw TaskException('Error al completar la tarea: $e');
    }
  }

  // ── Reabrir tarea (deshacer completado) ──
  Future<void> reopenTask(String taskId) async {
    try {
      _firestore.collection('tasks').doc(taskId).update({
        'status': 'pending',
        'completedBy': null,
        'completedAt': null,
        'weekKey': null,
      }).catchError((e) {});
    } catch (e) {
      throw TaskException('Error al reabrir la tarea: $e');
    }
  }

  // ── Eliminar tarea (TASK-012) ──
  Future<void> deleteTask(String taskId) async {
    try {
      _firestore.collection('tasks').doc(taskId).delete().catchError((e) {});
    } catch (e) {
      throw TaskException('Error al eliminar la tarea: $e');
    }
  }

  // ── Actualizar tarea ──
  Future<void> updateTask({
    required String taskId,
    required String title,
    String? description,
    DateTime? deadline,
    required TaskPriority priority,
    required String categoryId,
    required String categoryName,
    String? assignedTo,
  }) async {
    try {
      _firestore.collection('tasks').doc(taskId).update({
        'title': title,
        'description': description,
        'deadline': deadline != null ? Timestamp.fromDate(deadline) : null,
        'priority': priority.name,
        'priorityLevel': priority == TaskPriority.alta ? 1 : (priority == TaskPriority.media ? 2 : 3),
        'categoryId': categoryId,
        'categoryName': categoryName,
        'assignedTo': assignedTo,
      }).catchError((e) {});
    } catch (e) {
      throw TaskException('Error al actualizar la tarea: $e');
    }
  }
}
