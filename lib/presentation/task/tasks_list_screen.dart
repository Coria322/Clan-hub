import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../application/providers/household_provider.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../infrastructure/task/task_repository.dart';
import '../../infrastructure/notifications/notification_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

class TasksListScreen extends ConsumerStatefulWidget {
  const TasksListScreen({super.key});

  @override
  ConsumerState<TasksListScreen> createState() => _TasksListScreenState();
}

class _TasksListScreenState extends ConsumerState<TasksListScreen> {
  String _activeFilter = 'all'; // 'all' | 'mine' | 'unassigned' | 'overdue'
  int _selectedTab = 0; // 0 = Pendientes, 1 = Completadas
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Passive UI refresh for due dates every 30 seconds
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _buildMemberAvatars(List<QueryDocumentSnapshot> memberDocs) {
    if (memberDocs.isEmpty) return const SizedBox.shrink();

    final limit = 3;
    final displayDocs = memberDocs.take(limit).toList();
    final hasMore = memberDocs.length > limit;
    final moreCount = memberDocs.length - limit;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < displayDocs.length; i++)
          Align(
            widthFactor: 0.6,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.0),
                color: const Color(0xFFE8EAF6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0C4352A5),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  () {
                    final data = displayDocs[i].data() as Map<String, dynamic>?;
                    final name = data?['displayName'] as String?;
                    return (name != null && name.isNotEmpty) ? name[0].toUpperCase() : '?';
                  }(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4352A5),
                  ),
                ),
              ),
            ),
          ),
        if (hasMore)
          Align(
            widthFactor: 0.6,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.0),
                color: const Color(0xFFECEFF1),
              ),
              child: Center(
                child: Text(
                  '+$moreCount',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF454651),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusCard({
    required String title,
    required int count,
    required Color color,
  }) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x084352A5),
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF454651),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({required String label, required String value}) {
    final theme = Theme.of(context);
    final isActive = _activeFilter == value;

    return GestureDetector(
      onTap: () => setState(() => _activeFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildCorkboardMemo(String householdId, String? clanNote, bool isAdmin) {
    // Si no hay nota y el usuario no es admin, no mostrar nada
    final hasNote = clanNote != null && clanNote.isNotEmpty;
    if (!hasNote && !isAdmin) return const SizedBox.shrink();

    final theme = Theme.of(context);

    // Admin sin nota: mostrar tarjeta de invitación punteada
    if (!hasNote && isAdmin) {
      return GestureDetector(
        onTap: () => _editClanNote(householdId, ''),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.25),
              style: BorderStyle.solid,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 16, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
              const SizedBox(width: 8),
              Text(
                'Agregar nota del Clan',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Nota existente
    return GestureDetector(
      onTap: isAdmin ? () => _editClanNote(householdId, clanNote!) : null,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.12)),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Nota del Clan',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4352A5),
                      ),
                    ),
                    if (isAdmin)
                      const Icon(Icons.edit, size: 14, color: Color(0xFF4352A5)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  clanNote!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF454651),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Positioned(
              right: 0,
              bottom: 0,
              child: Opacity(
                opacity: 0.08,
                child: Icon(
                  Icons.push_pin_outlined,
                  size: 40,
                  color: Color(0xFF4352A5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editClanNote(String householdId, String currentNote) async {
    final controller = TextEditingController(text: currentNote);
    
    final newNote = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nota del Clan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 150,
          decoration: InputDecoration(
            hintText: 'Escribe un mensaje para todos...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (newNote != null && mounted) {
      try {
        await FirebaseFirestore.instance.collection('households').doc(householdId).update({
          'note': newNote.isEmpty ? null : newNote,
        });
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _buildSliverTasksList(String householdId, String currentUserUid, bool isAdmin) {
    final Stream<List<TaskModel>> stream = _selectedTab == 0
        ? ref.read(taskRepositoryProvider).watchPendingTasks(householdId)
        : ref.read(taskRepositoryProvider).watchCompletedTasks(householdId);

    return StreamBuilder<List<TaskModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return SliverToBoxAdapter(
            child: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        final originalTasks = snapshot.data ?? [];

        // Sincronizar alarmas si estamos en Tab Pendientes
        if (_selectedTab == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(notificationServiceProvider).syncTaskAlarms(originalTasks, currentUserUid);
          });
        }

        // Aplicar Filtro de Píldoras
        var tasks = originalTasks;
        if (_activeFilter == 'mine') {
          tasks = originalTasks.where((t) => t.assignedTo == currentUserUid).toList();
        } else if (_activeFilter == 'unassigned') {
          tasks = originalTasks.where((t) => t.assignedTo == null).toList();
        } else if (_activeFilter == 'overdue') {
          tasks = originalTasks.where((t) => t.isOverdue && t.isPending).toList();
        }

        if (tasks.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _selectedTab == 0 ? Icons.check_circle_outline : Icons.emoji_events_outlined,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedTab == 0
                        ? 'No hay tareas pendientes con este filtro.'
                        : 'Aún no hay tareas completadas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return TaskCardWidget(
                  task: tasks[index],
                  currentUserUid: currentUserUid,
                  isAdmin: isAdmin,
                );
              },
              childCount: tasks.length,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(activeHouseholdProvider);
    final currentUser = ref.read(authRepositoryProvider).currentUser;

    if (householdId == null || currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('households').doc(householdId).snapshots(),
          builder: (context, hSnap) {
            final householdData = hSnap.data?.data() as Map<String, dynamic>?;
            final householdName = householdData?['name'] ?? 'Mi Hogar';
            final clanNote = householdData?['note'] as String?;
            final isAdmin = householdData?['adminUid'] == currentUser.uid;

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('households')
                  .doc(householdId)
                  .collection('members')
                  .snapshots(),
              builder: (context, membersSnap) {
                final memberDocs = membersSnap.data?.docs ?? [];

                return CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    // 1. Custom Top Header (mockup style with household switcher)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (ctx) => _HouseholdSwitcherSheet(currentHouseholdId: householdId),
                                    );
                                  },
                                  behavior: HitTestBehavior.opaque,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        householdName,
                                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.expand_more, color: Theme.of(context).colorScheme.primary),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '¡Hola, ${currentUser.displayName ?? 'Familia'}!',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            _buildMemberAvatars(memberDocs),
                          ],
                        ),
                      ),
                    ),

                    // 2. Scrolling Summary Columns Row
                    SliverToBoxAdapter(
                      child: StreamBuilder<List<TaskModel>>(
                        stream: ref.read(taskRepositoryProvider).watchPendingTasks(householdId),
                        builder: (context, pendingSnap) {
                          return StreamBuilder<List<TaskModel>>(
                            stream: ref.read(taskRepositoryProvider).watchCompletedTasks(householdId),
                            builder: (context, completedSnap) {
                              final pendingList = pendingSnap.data ?? [];
                              final completedList = completedSnap.data ?? [];
                              final overdueCount = pendingList.where((t) => t.isOverdue).length;

                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                                  children: [
                                    _buildStatusCard(
                                      title: 'Pendientes',
                                      count: pendingList.length - overdueCount,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 12),
                                    _buildStatusCard(
                                      title: 'Vencidas',
                                      count: overdueCount,
                                      color: Theme.of(context).colorScheme.secondary,
                                    ),
                                    const SizedBox(width: 12),
                                    _buildStatusCard(
                                      title: 'Completadas',
                                      count: completedList.length,
                                      color: Theme.of(context).colorScheme.tertiary,
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),

                    // 3. Horizontal Filter Bar
                    SliverToBoxAdapter(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            _buildFilterChip(label: 'Todas', value: 'all'),
                            const SizedBox(width: 8),
                            _buildFilterChip(label: 'Mías', value: 'mine'),
                            const SizedBox(width: 8),
                            _buildFilterChip(label: 'Sin Asignar', value: 'unassigned'),
                            const SizedBox(width: 8),
                            _buildFilterChip(label: 'Vencidas', value: 'overdue'),
                          ],
                        ),
                      ),
                    ),

                    // 4. Tab selection: "Pendientes" vs "Completadas"
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedTab == 0 ? 'Tareas de Hoy' : 'Tareas Completadas',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() => _selectedTab = 0),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _selectedTab == 0 ? Theme.of(context).colorScheme.primary : Colors.transparent,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Activas',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _selectedTab == 0 ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() => _selectedTab = 1),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _selectedTab == 1 ? Theme.of(context).colorScheme.primary : Colors.transparent,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Listas',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _selectedTab == 1 ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 5. Tasks List
                    _buildSliverTasksList(householdId, currentUser.uid, isAdmin),

                    // 6. Corkboard Memo Section
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
                        child: _buildCorkboardMemo(householdId, clanNote, isAdmin),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 120.0),
        child: FloatingActionButton.extended(
          onPressed: () => context.push('/home/tasks/create'),
          elevation: 4,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Nueva Tarea', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter')),
        ),
      ),
    );
  }
}

// ── AssignedChip ──
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

  IconData _getIconForCategory(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('cocina') || lower.contains('comida') || lower.contains('plato') || lower.contains('cena')) {
      return Icons.restaurant;
    }
    if (lower.contains('limpieza') || lower.contains('limpiar') || lower.contains('baño')) {
      return Icons.cleaning_services;
    }
    if (lower.contains('basura') || lower.contains('reciclar')) {
      return Icons.delete_outline;
    }
    if (lower.contains('compra') || lower.contains('super')) {
      return Icons.shopping_cart;
    }
    if (lower.contains('mascota') || lower.contains('perro') || lower.contains('gato')) {
      return Icons.pets;
    }
    if (lower.contains('jardín') || lower.contains('planta')) {
      return Icons.local_florist;
    }
    return Icons.task_alt;
  }

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.alta:
        return const Color(0xFFFBE9E7); // Light Warm Coral
      case TaskPriority.media:
        return const Color(0xFFE8EAF6); // Light Soft Indigo
      case TaskPriority.baja:
        return const Color(0xFFECEFF1); // Light Slate
    }
  }

  Color _priorityTextColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.alta:
        return const Color(0xFFAC3509);
      case TaskPriority.media:
        return const Color(0xFF4352A5);
      case TaskPriority.baja:
        return const Color(0xFF454651);
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
        if (isAdmin) return true;
        return task.completedBy == currentUserUid;
    }
    if (isAdmin) return true;
    if (task.isOverdue || task.assignedTo == null) return true;
    return task.assignedTo == currentUserUid;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final leftBorderColor = task.isOverdue
        ? theme.colorScheme.secondary
        : (task.priority == TaskPriority.alta
            ? Colors.amber.shade500
            : (task.priority == TaskPriority.media
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant));

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: task.isOverdue
            ? (isDark ? const Color(0xFF381B18) : const Color(0xFFFBE9E7))
            : (isDark ? const Color(0xFF202035) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x064352A5),
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: leftBorderColor, width: 4.0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Left Side: Category Icon ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: task.isOverdue
                        ? theme.colorScheme.error.withValues(alpha: 0.12)
                        : theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getIconForCategory(task.categoryName),
                    color: task.isOverdue ? theme.colorScheme.error : theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
              ),

              // ── Center Content: Task Details ──
              Expanded(
                child: InkWell(
                  onTap: () => context.push('/home/tasks/${task.id}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                            color: task.isCompleted
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                                : theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _Chip(
                              label: _priorityLabel(task.priority),
                              color: _priorityColor(task.priority),
                              textColor: _priorityTextColor(task.priority),
                            ),
                            _Chip(
                              label: task.categoryName,
                              color: theme.colorScheme.primary.withValues(alpha: 0.05),
                              textColor: theme.colorScheme.primary,
                            ),
                            if (task.deadline != null)
                              _Chip(
                                label: _formatDeadline(task.deadline!),
                                color: task.isOverdue
                                    ? const Color(0xFFFBE9E7)
                                    : const Color(0xFFE8F5E9),
                                textColor: task.isOverdue
                                    ? const Color(0xFFAC3509)
                                    : const Color(0xFF066721),
                                icon: Icons.schedule,
                              ),
                            if (task.assignedTo != null)
                              _AssignedChip(
                                householdId: ref.watch(activeHouseholdProvider)!,
                                uid: task.assignedTo!,
                                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.08),
                                textColor: theme.colorScheme.primary,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Right Side: Action Checkbox Bubble ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Tooltip(
                  message: task.isCompleted
                      ? 'Desmarcar como completada'
                      : _canComplete()
                      ? 'Marcar como completada'
                      : 'Solo el asignado puede completar',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _canComplete() ? () => _toggleComplete(context, ref) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6), // 6px rounded bubble
                        color: task.isCompleted ? theme.colorScheme.tertiary : Colors.transparent,
                        border: Border.all(
                          color: task.isCompleted
                              ? theme.colorScheme.tertiary
                              : _canComplete()
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: 2.0,
                        ),
                      ),
                      child: task.isCompleted
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¡Felicidades!'),
            content: const Text('¿Deseas enviar evidencia fotográfica de tu logro al Clan?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'solo_completar'),
                child: const Text('Solo Completar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'tomar_foto'),
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('Tomar Foto'),
              ),
            ],
          ),
        );

        if (action == null) return;
        final takePhoto = (action == 'tomar_foto');

        XFile? photo;
        if (takePhoto) {
           final picker = ImagePicker();
           photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
           if (photo == null) return;
        }

        if (photo != null) {
            final shareText = '¡He completado la tarea "${task.title}" en ClanHub! 🚀🛡️';
            await SharePlus.instance.share(
              ShareParams(
                files: [photo],
                text: shareText,
              ),
            );
        }

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
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final IconData? icon;

  const _Chip({
    required this.label,
    required this.color,
    required this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Custom Household Switcher Bottom Sheet ──
class _HouseholdSwitcherSheet extends ConsumerWidget {
  final String currentHouseholdId;

  const _HouseholdSwitcherSheet({required this.currentHouseholdId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final householdsAsync = ref.watch(userHouseholdsProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 48,
            height: 6,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Cambiar Hogar', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close), 
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          
          // Households List
          householdsAsync.when(
            data: (households) {
              if (households.isEmpty) return const SizedBox.shrink();
              return Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  itemCount: households.length,
                  itemBuilder: (context, index) {
                    final h = households[index];
                    final isActive = h['id'] == currentHouseholdId;
                    
                    return GestureDetector(
                      onTap: () {
                        if (!isActive) {
                          ref.read(activeHouseholdProvider.notifier).setHousehold(h['id']!);
                        }
                        Navigator.pop(context);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isActive 
                              ? (isDark ? theme.colorScheme.primary.withValues(alpha: 0.15) : const Color(0xFFE8EAF6))
                              : (isDark ? const Color(0xFF202035) : Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          border: isActive 
                              ? Border(left: BorderSide(color: theme.colorScheme.primary, width: 4))
                              : Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
                          boxShadow: isActive ? [] : const [
                            BoxShadow(color: Color(0x064352A5), blurRadius: 10, offset: Offset(0, 4)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isActive ? Colors.white : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: isActive ? const [
                                  BoxShadow(color: Color(0x0C4352A5), blurRadius: 4, offset: Offset(0, 2))
                                ] : [],
                              ),
                              child: Icon(isActive ? Icons.home : Icons.cabin, color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    h['name'] ?? 'Hogar',
                                    style: TextStyle(
                                      fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 15,
                                      color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Hogar Familiar', 
                                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (isActive)
                              Icon(Icons.check_circle, color: theme.colorScheme.primary),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            error: (e, st) => Center(child: Text('Error: $e')),
          ),
          
          const SizedBox(height: 16),
          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/onboarding/join');
                    },
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Unirse', style: TextStyle(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/onboarding/create');
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Crear nuevo', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.secondary,
                      foregroundColor: theme.colorScheme.onSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // SafeArea padding
          SafeArea(child: const SizedBox.shrink()),
        ],
      ),
    );
  }
}
