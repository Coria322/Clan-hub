import 'package:flutter_test/flutter_test.dart';
import 'package:clanhub/infrastructure/task/task_repository.dart';

void main() {
  group('TaskModel', () {
    test('isPending is true when status is pending', () {
      final task = TaskModel(
        id: '1',
        householdId: 'h1',
        title: 'Test',
        priority: TaskPriority.media,
        priorityLevel: 2,
        categoryId: 'c1',
        categoryName: 'Cat',
        createdBy: 'u1',
        createdAt: DateTime.now(),
        status: 'pending',
      );
      expect(task.isPending, isTrue);
      expect(task.isCompleted, isFalse);
    });

    test('isOverdue is true when deadline is in the past and status is pending', () {
      final task = TaskModel(
        id: '1',
        householdId: 'h1',
        title: 'Test',
        priority: TaskPriority.media,
        priorityLevel: 2,
        categoryId: 'c1',
        categoryName: 'Cat',
        createdBy: 'u1',
        createdAt: DateTime.now(),
        status: 'pending',
        deadline: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(task.isOverdue, isTrue);
    });

    test('isOverdue is false when deadline is in the future', () {
      final task = TaskModel(
        id: '1',
        householdId: 'h1',
        title: 'Test',
        priority: TaskPriority.media,
        priorityLevel: 2,
        categoryId: 'c1',
        categoryName: 'Cat',
        createdBy: 'u1',
        createdAt: DateTime.now(),
        status: 'pending',
        deadline: DateTime.now().add(const Duration(days: 1)),
      );
      expect(task.isOverdue, isFalse);
    });

    test('isOverdue is false when task is completed even if deadline is in past', () {
      final task = TaskModel(
        id: '1',
        householdId: 'h1',
        title: 'Test',
        priority: TaskPriority.media,
        priorityLevel: 2,
        categoryId: 'c1',
        categoryName: 'Cat',
        createdBy: 'u1',
        createdAt: DateTime.now(),
        status: 'completed',
        deadline: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(task.isOverdue, isFalse);
    });
  });
}
