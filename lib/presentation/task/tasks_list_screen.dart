import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../application/providers/household_provider.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../infrastructure/task/task_repository.dart';
import '../../infrastructure/notifications/notification_service.dart';

class TasksListScreen extends ConsumerStatefulWidget {
  const TasksListScreen({super.key});

  @override
  ConsumerState<TasksListScreen> createState() => _TasksListScreenState();
}

class _AssignedChip extends StatelessWidget {
  final String householdId;
  final String uid;
  final Color backgroundColor;
  final Color textColor;

  const _AssignedChip({
    required this.householdId,
    required this.uid,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('households')
          .doc(householdId)
          .collection('members')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final name = snap.hasData && snap.data!.exists
            ? (snap.data!.data() as Map<String, dynamic>)['displayName']
                      as String? ??
                  'Miembro'
            : 'Miembro';

        return _Chip(
          label: name,
          color: backgroundColor,
          textColor: textColor,
          icon: Icons.person,
        );
      },
    );
  }
}

class _TasksListScreenState extends ConsumerState<TasksListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showOnlyMine = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(activeHouseholdProvider);
    final currentUser = ref.read(authRepositoryProvider).currentUser;

    if (householdId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }



    return Scaffold(
      appBar: AppBar(
        title: const Text('Tareas'),
        actions: [
          Row(
            children: [
              Text('Mías', style: TextStyle(fontSize: 14)),
              Switch(
                value: _showOnlyMine,
                onChanged: (val) => setState(() => _showOnlyMine = val),
              ),
              const SizedBox(width: 8),
            ],
          )
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pendientes'),
            Tab(text: 'Completadas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab Pendientes ──
          _TaskStreamList(
            stream: ref
                .read(taskRepositoryProvider)
                .watchPendingTasks(householdId),
            currentUserUid: currentUser?.uid ?? '',
            householdId: householdId,
            showOnlyMine: _showOnlyMine,
            emptyMessage: 'No hay tareas pendientes.\n¡Crea la primera!',
            emptyIcon: Icons.check_circle_outline,
          ),
          // ── Tab Completadas ──
          _TaskStreamList(
            stream: ref
                .read(taskRepositoryProvider)
                .watchCompletedTasks(householdId),
            currentUserUid: currentUser?.uid ?? '',
            householdId: householdId,
            showOnlyMine: _showOnlyMine,
            emptyMessage: 'Aún no hay tareas completadas esta semana.',
            emptyIcon: Icons.emoji_events_outlined,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/home/tasks/create'),
        icon: const Icon(Icons.add),
        label: const Text('Nueva tarea'),
      ),
    );
  }
}

class _TaskStreamList extends ConsumerWidget {
  final Stream<List<TaskModel>> stream;
  final String currentUserUid;
  final String householdId;
  final bool showOnlyMine;
  final String emptyMessage;
  final IconData emptyIcon;

  const _TaskStreamList({
    required this.stream,
    required this.currentUserUid,
    required this.householdId,
    required this.showOnlyMine,
    required this.emptyMessage,
    required this.emptyIcon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('households').doc(householdId).snapshots(),
      builder: (context, hSnap) {
        bool isAdmin = false;
        if (hSnap.hasData && hSnap.data != null && hSnap.data!.exists) {
          final data = hSnap.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            isAdmin = data['adminUid'] == currentUserUid;
          }
        }
            
        return StreamBuilder<List<TaskModel>>(
          stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton();
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final originalTasks = snapshot.data ?? [];

        // Sincronizar alarmas si estamos cargando el stream de "Pendientes"
        if (emptyIcon == Icons.check_circle_outline) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
             ref.read(notificationServiceProvider).syncTaskAlarms(originalTasks, currentUserUid);
          });
        }

        final tasks = showOnlyMine 
            ? originalTasks.where((t) => t.assignedTo == currentUserUid).toList() 
            : originalTasks;

        if (tasks.isEmpty) {
          return _buildEmpty(context, emptyMessage, emptyIcon);
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            return TaskCardWidget(
              task: tasks[index],
              currentUserUid: currentUserUid,
              isAdmin: isAdmin,
            );
          },
        );
      },
    );
      },
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 3,
      itemBuilder: (_, _) => const _SkeletonCard(),
    );
  }

  Widget _buildEmpty(BuildContext context, String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ── Skeleton shimmer ──
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade800
        : Colors.grey.shade200;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 14, width: 220, color: base),
            const SizedBox(height: 10),
            Container(height: 10, width: 140, color: base),
            const SizedBox(height: 6),
            Container(height: 10, width: 90, color: base),
          ],
        ),
      ),
    );
  }
}

// ── TaskCardWidget ──
class TaskCardWidget extends ConsumerWidget {
  final TaskModel task;
  final String currentUserUid;
  final bool isAdmin;

  const TaskCardWidget({
    super.key,
    required this.task,
    required this.currentUserUid,
    this.isAdmin = false,
  });

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.alta:
        return const Color(0xFFE53935);
      case TaskPriority.media:
        return const Color(0xFFFB8C00);
      case TaskPriority.baja:
        return const Color(0xFF43A047);
    }
  }

  String _priorityLabel(TaskPriority p) {
    switch (p) {
      case TaskPriority.alta:
        return 'Alta';
      case TaskPriority.media:
        return 'Media';
      case TaskPriority.baja:
        return 'Baja';
    }
  }

  bool _canComplete() {
    if (task.isCompleted) {
        // Reglas para reabrir
        if (isAdmin) return true;
        if (task.assignedTo == null) return task.completedBy == currentUserUid;
        // Si estaba asignada: el dueño original o el que la completó (si estaba vencida)
        return task.assignedTo == currentUserUid || task.completedBy == currentUserUid;
    }
    
    // Reglas para completar
    if (isAdmin) return true;
    if (task.isOverdue || task.assignedTo == null) return true;
    return task.assignedTo == currentUserUid;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final borderColor = task.isOverdue
        ? Colors.red.shade300
        : theme.colorScheme.outlineVariant;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: task.isOverdue ? 1.5 : 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Zona 1: Toggle circle — hitbox propia ──────────────────
            Tooltip(
              message: task.isCompleted
                  ? 'Desmarcar como completada'
                  : _canComplete()
                  ? 'Marcar como completada'
                  : 'Solo el asignado puede completar',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque, // consume el tap sin competir
                onTap: _canComplete()
                    ? () => _toggleComplete(context, ref)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: task.isCompleted
                          ? const Color(0xFF4CAF82)
                          : Colors.transparent,
                      border: Border.all(
                        color: task.isCompleted
                            ? const Color(0xFF4CAF82)
                            : _canComplete()
                            ? theme.colorScheme.primary
                            : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                    child: task.isCompleted
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                ),
              ),
            ),

            // ── Zona 2: Contenido — navega a detalle ───────────────────
            Expanded(
              child: InkWell(
                onTap: () => context.push('/home/tasks/${task.id}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Título
                      Text(
                        task.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.isCompleted
                              ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                              : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Chips: prioridad + categoría + deadline
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Chip(
                            label: _priorityLabel(task.priority),
                            color: _priorityColor(task.priority),
                          ),
                          _Chip(
                            label: task.categoryName,
                            color: theme.colorScheme.secondaryContainer,
                            textColor: theme.colorScheme.onSecondaryContainer,
                          ),
                          if (task.deadline != null)
                            _Chip(
                              label: _formatDeadline(task.deadline!),
                              color: task.isOverdue
                                  ? Colors.red.shade100
                                  : Colors.blue.shade50,
                              textColor: task.isOverdue
                                  ? Colors.red.shade800
                                  : Colors.blue.shade800,
                              icon: Icons.schedule,
                            ),
                          if (task.assignedTo != null)
                            _AssignedChip(
                              householdId: ref.watch(activeHouseholdProvider)!,
                              uid: task.assignedTo!,
                              backgroundColor:
                                  theme.colorScheme.tertiaryContainer,
                              textColor: theme.colorScheme.onTertiaryContainer,
                            ),
                        ],
                      ),

                      // Quién completó
                      if (task.isCompleted && task.completedBy != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Completada',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(0xFF4CAF82),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDeadline(DateTime d) {
    final now = DateTime.now();
    final diff = d.difference(now);
    if (diff.isNegative) return 'Vencida';
    if (diff.inDays == 0) {
      return 'Hoy ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) return 'Mañana';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _toggleComplete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(taskRepositoryProvider);
    try {
      if (task.isPending) {
        await repo.completeTask(
          taskId: task.id,
          completedByUid: currentUserUid,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Tarea completada'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        // Desmarcar / reabrir
        await repo.reopenTask(task.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔄 Tarea reabierta'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;
  final IconData? icon;

  const _Chip({
    required this.label,
    required this.color,
    this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
