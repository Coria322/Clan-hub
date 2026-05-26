import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../task/task_repository.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(FirebaseFirestore.instance);
});

class CategoryWeeklyStat {
  final String id; // uid del miembro o 'overdue'
  final String displayName;
  final int count;
  final double percentage;
  final bool isOverdueCategory;

  const CategoryWeeklyStat({
    required this.id,
    required this.displayName,
    required this.count,
    required this.percentage,
    this.isOverdueCategory = false,
  });
}

class DashboardOverview {
  final int completedCount;
  final int pendingCount;
  final int overdueCount;

  const DashboardOverview({
    required this.completedCount,
    required this.pendingCount,
    required this.overdueCount,
  });
}

class DashboardRepository {
  final FirebaseFirestore _firestore;

  DashboardRepository(this._firestore);

  Stream<List<TaskModel>> watchTasksForWeek(String householdId, String weekKey) {
    return _firestore
        .collection('tasks')
        .where('householdId', isEqualTo: householdId)
        .where('weekKey', isEqualTo: weekKey)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((snap) => snap.docs.map(TaskModel.fromFirestore).toList());
  }

  Stream<List<TaskModel>> watchPendingTasks(String householdId) {
    return _firestore
        .collection('tasks')
        .where('householdId', isEqualTo: householdId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map(TaskModel.fromFirestore).toList());
  }

  Future<Map<String, String>> getHouseholdMemberNames(String householdId) async {
    try {
      final membersSnapshot = await _firestore
          .collection('households')
          .doc(householdId)
          .collection('members')
          .get()
          .timeout(const Duration(seconds: 2));
          
      final memberNames = <String, String>{};
      for (var doc in membersSnapshot.docs) {
        final data = doc.data();
        memberNames[doc.id] = data['displayName'] as String? ?? 'Miembro';
      }
      return memberNames;
    } catch (e) {
      // Fallback a caché local si estamos offline (timeout o error de red)
      try {
        final cachedSnapshot = await _firestore
            .collection('households')
            .doc(householdId)
            .collection('members')
            .get(const GetOptions(source: Source.cache));
            
        final memberNames = <String, String>{};
        for (var doc in cachedSnapshot.docs) {
          final data = doc.data();
          memberNames[doc.id] = data['displayName'] as String? ?? 'Miembro';
        }
        return memberNames;
      } catch (_) {
        return {};
      }
    }
  }
}
