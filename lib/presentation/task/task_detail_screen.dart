import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../application/providers/household_provider.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../infrastructure/task/task_repository.dart';
import '../../infrastructure/household/category_repository.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  final String taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  TaskPriority _priority = TaskPriority.media;
  String? _categoryId;
  String? _categoryName;
  String? _assignedTo;
  DateTime? _deadline;

  bool _editing = false;
  bool _loading = false;
  TaskModel? _task;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Refresco pasivo de UI para la fecha de vencimiento cada 30 seg
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _populateFrom(TaskModel task) {
    _titleCtrl.text = task.title;
    _descCtrl.text = task.description ?? '';
    _priority = task.priority;
    _categoryId = task.categoryId.isEmpty ? null : task.categoryId;
    _categoryName = task.categoryName.isEmpty ? null : task.categoryName;
    _assignedTo = task.assignedTo;
    _deadline = task.deadline;
  }

  // ── Guardar edición ─────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona una categoría')));
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(taskRepositoryProvider)
          .updateTask(
            taskId: widget.taskId,
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            deadline: _deadline,
            priority: _priority,
            categoryId: _categoryId!,
            categoryName: _categoryName!,
            assignedTo: _assignedTo,
          );
      if (mounted) {
        setState(() => _editing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Tarea actualizada!!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Desmarcar como completada ─────────────────────────────────────────
  Future<void> _reopen() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Reabrir tarea?'),
        content: const Text(
          'La tarea volverá a estar pendiente y podrá ser completada de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await ref.read(taskRepositoryProvider).reopenTask(widget.taskId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('🔄 Tarea reabierta')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Eliminar ──────────────────────────────────────────────────────────
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar tarea?'),
        content: const Text('Esta acción es irreversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await ref.read(taskRepositoryProvider).deleteTask(widget.taskId);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
        setState(() => _loading = false);
      }
    }
  }

  // ── Date picker ───────────────────────────────────────────────────────
  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _deadline != null
          ? TimeOfDay.fromDateTime(_deadline!)
          : const TimeOfDay(hour: 20, minute: 0),
    );
    if (!mounted) return;
    setState(() {
      _deadline = time == null
          ? date
          : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────
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

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}  '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(activeHouseholdProvider);
    final currentUser = ref.read(authRepositoryProvider).currentUser;
    if (householdId == null || currentUser == null) return const Scaffold();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tasks')
          .doc(widget.taskId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snap.data!.exists) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('La tarea ya no existe.')),
          );
        }

        final task = TaskModel.fromFirestore(snap.data!);

        // Inicializar campos la primera vez (o si salimos del modo edición)
        if (_task == null || _task!.id != task.id) {
          _task = task;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _populateFrom(task);
          });
        }

        final isCreator = task.createdBy == currentUser.uid;

        // Admin check via household doc
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('households')
              .doc(householdId)
              .snapshots(),
          builder: (context, hSnap) {
            final adminUid =
                (hSnap.data?.data() as Map<String, dynamic>?)?['adminUid']
                    as String?;
            final isAdmin = currentUser.uid == adminUid;
            final canEdit = task.isPending && (isCreator || isAdmin);
            final canDelete = isAdmin || isCreator;
            final canReopen = task.isCompleted && (
               isAdmin || 
               task.completedBy == currentUser.uid
            );

            return Scaffold(
              appBar: AppBar(
                title: Text(_editing ? 'Editar tarea' : 'Detalle de tarea'),
                actions: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else ...[
                    // Botón editar / guardar
                    if (!_editing && canEdit)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Editar',
                        onPressed: () {
                          _populateFrom(task);
                          setState(() => _editing = true);
                        },
                      ),
                    if (_editing) ...[
                      TextButton(
                        onPressed: () => setState(() => _editing = false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: _save,
                        child: const Text(
                          'Guardar',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    // Menú de opciones
                    if (!_editing)
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'reopen') _reopen();
                          if (v == 'delete') _delete();
                        },
                        itemBuilder: (_) => [
                          if (canReopen)
                            const PopupMenuItem(
                              value: 'reopen',
                              child: ListTile(
                                leading: Icon(Icons.replay, color: Colors.blue),
                                title: Text('Desmarcar / Reabrir'),
                              ),
                            ),
                          if (canDelete)
                            const PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(
                                  Icons.delete_forever,
                                  color: Colors.red,
                                ),
                                title: Text(
                                  'Eliminar tarea',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
              body: _editing
                  ? _buildEditForm(householdId, task)
                  : _buildReadView(context, task),
            );
          },
        );
      },
    );
  }

  // ── Vista de lectura ──────────────────────────────────────────────────
  Widget _buildReadView(BuildContext context, TaskModel task) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Estado badge
        Row(
          children: [
            _StatusBadge(task: task),
            const Spacer(),
            if (task.isOverdue)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  'VENCIDA',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Título
        Text(
          task.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            color: task.isCompleted
                ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                : null,
          ),
        ),

        // Descripción
        if (task.description != null && task.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            task.description!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],

        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),

        // Info grid
        _InfoRow(
          icon: Icons.flag_outlined,
          label: 'Prioridad',
          value: _priorityLabel(task.priority),
          valueColor: _priorityColor(task.priority),
        ),
        _InfoRow(
          icon: Icons.label_outline,
          label: 'Categoría',
          value: task.categoryName,
        ),
        if (task.deadline != null)
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Fecha límite',
            value: _formatDate(task.deadline!),
            valueColor: task.isOverdue ? Colors.red : null,
          ),
        if (task.assignedTo != null)
          _AssignedRow(
            householdId: ref.watch(activeHouseholdProvider)!,
            uid: task.assignedTo!,
          ),
        if (task.isCompleted && task.completedAt != null)
          _InfoRow(
            icon: Icons.check_circle_outline,
            label: 'Completada',
            value: _formatDate(task.completedAt!),
            valueColor: const Color(0xFF4CAF82),
          ),
      ],
    );
  }

  // ── Formulario de edición ─────────────────────────────────────────────
  Widget _buildEditForm(String householdId, TaskModel task) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Título
          TextFormField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Título *',
              border: OutlineInputBorder(),
            ),
            maxLength: 100,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'El título es obligatorio'
                : null,
          ),
          const SizedBox(height: 12),

          // Descripción
          TextFormField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            maxLength: 300,
          ),
          const SizedBox(height: 4),

          // Prioridad
          const Text(
            'Prioridad *',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          SegmentedButton<TaskPriority>(
            segments: const [
              ButtonSegment(
                value: TaskPriority.alta,
                label: Text('Alta'),
                icon: Icon(Icons.keyboard_double_arrow_up, size: 16),
              ),
              ButtonSegment(
                value: TaskPriority.media,
                label: Text('Media'),
                icon: Icon(Icons.drag_handle, size: 16),
              ),
              ButtonSegment(
                value: TaskPriority.baja,
                label: Text('Baja'),
                icon: Icon(Icons.keyboard_double_arrow_down, size: 16),
              ),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const SizedBox(height: 16),

          // Categoría
          const Text(
            'Categoría *',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _CategoryPickerEdit(
            householdId: householdId,
            selectedId: _categoryId,
            onSelected: (id, name) => setState(() {
              _categoryId = id;
              _categoryName = name;
            }),
          ),
          const SizedBox(height: 16),

          // Deadline
          const Text(
            'Fecha límite (opcional)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickDeadline,
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(
              _deadline == null ? 'Sin fecha límite' : _formatDate(_deadline!),
            ),
          ),
          if (_deadline != null)
            TextButton(
              onPressed: () => setState(() => _deadline = null),
              child: const Text(
                'Quitar fecha',
                style: TextStyle(color: Colors.red),
              ),
            ),
          const SizedBox(height: 16),

          // Asignado a
          const Text(
            'Asignar a (opcional)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _MemberPickerEdit(
            householdId: householdId,
            selectedUid: _assignedTo,
            onSelected: (uid) => setState(() => _assignedTo = uid),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Status badge ─────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final TaskModel task;
  const _StatusBadge({required this.task});

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.isCompleted;
    final color = isCompleted ? const Color(0xFF4CAF82) : Colors.orange;
    final label = isCompleted ? 'Completada' : 'Pendiente';
    final icon = isCompleted ? Icons.check_circle : Icons.pending_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info row ─────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color:
                    valueColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Assigned row (loaded by uid) ─────────────────────────────────────────────
class _AssignedRow extends StatelessWidget {
  final String householdId;
  final String uid;

  const _AssignedRow({required this.householdId, required this.uid});

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
        return _InfoRow(
          icon: Icons.person_outline,
          label: 'Asignada a',
          value: name,
        );
      },
    );
  }
}

// ── Category picker (edit mode) ───────────────────────────────────────────────
class _CategoryPickerEdit extends ConsumerWidget {
  final String householdId;
  final String? selectedId;
  final void Function(String id, String name) onSelected;

  const _CategoryPickerEdit({
    required this.householdId,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<CategoryModel>>(
      stream: ref.read(categoryRepositoryProvider).watchActive(householdId),
      builder: (context, snap) {
        if (!snap.hasData) return const LinearProgressIndicator();
        final cats = snap.data!;
        if (cats.isEmpty) {
          return const Text('Sin categorías activas');
        }
        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(border: OutlineInputBorder()),
          initialValue: selectedId,
          hint: const Text('Seleccionar categoría'),
          items: cats.map((cat) {
            final color = Color(cat.colorValue);
            final icon = IconData(cat.iconCode, fontFamily: 'MaterialIcons');
            return DropdownMenuItem(
              value: cat.id,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: color.withValues(alpha: 0.18),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  const SizedBox(width: 10),
                  Text(cat.name),
                ],
              ),
            );
          }).toList(),
          onChanged: (id) {
            if (id == null) return;
            final cat = cats.firstWhere((c) => c.id == id);
            onSelected(id, cat.name);
          },
        );
      },
    );
  }
}

// ── Member picker (edit mode) ─────────────────────────────────────────────────
class _MemberPickerEdit extends StatelessWidget {
  final String householdId;
  final String? selectedUid;
  final void Function(String? uid) onSelected;

  const _MemberPickerEdit({
    required this.householdId,
    required this.selectedUid,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('households')
          .doc(householdId)
          .collection('members')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final members = snap.data!.docs;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _MemberAvatar(
                label: '–',
                tooltip: 'Sin asignar',
                selected: selectedUid == null,
                onTap: () => onSelected(null),
                color: Colors.grey.shade400,
              ),
              ...members.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final uid = data['uid'] as String? ?? doc.id;
                final name = data['displayName'] as String? ?? 'U';
                final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                return _MemberAvatar(
                  label: initial,
                  tooltip: name,
                  selected: selectedUid == uid,
                  onTap: () => onSelected(uid),
                  color: const Color(0xFF4CAF82),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _MemberAvatar({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? color : color.withValues(alpha: 0.2),
              border: Border.all(
                color: selected ? color : Colors.transparent,
                width: 3,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
