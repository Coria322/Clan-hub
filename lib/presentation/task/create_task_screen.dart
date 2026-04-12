import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../application/providers/household_provider.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../infrastructure/task/task_repository.dart';
import '../../infrastructure/household/category_repository.dart';

class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  ConsumerState<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends ConsumerState<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  TaskPriority _priority = TaskPriority.media;
  String? _categoryId;
  String? _categoryName;
  String? _assignedTo; // null = sin asignar
  DateTime? _deadline;
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 20, minute: 0),
    );
    if (!mounted) return;
    setState(() {
      _deadline = time == null
          ? date
          : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una categoría')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final householdId = ref.read(activeHouseholdProvider)!;
      final user = ref.read(authRepositoryProvider).currentUser!;

      await ref.read(taskRepositoryProvider).createTask(
        householdId: householdId,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        deadline: _deadline,
        priority: _priority,
        categoryId: _categoryId!,
        categoryName: _categoryName!,
        assignedTo: _assignedTo,
        createdBy: user.uid,
      );

      if (mounted) {
        FocusScope.of(context).unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Tarea creada exitosamente')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(activeHouseholdProvider);
    if (householdId == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Tarea'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Título ──
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Título *',
                hintText: 'ej. Limpiar la cocina',
                border: OutlineInputBorder(),
              ),
              maxLength: 100,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'El título es obligatorio' : null,
            ),
            const SizedBox(height: 12),

            // ── Descripción ──
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

            // ── Prioridad ──
            const Text('Prioridad *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            SegmentedButton<TaskPriority>(
              segments: const [
                ButtonSegment(value: TaskPriority.alta, label: Text('Alta'), icon: Icon(Icons.keyboard_double_arrow_up, size: 16)),
                ButtonSegment(value: TaskPriority.media, label: Text('Media'), icon: Icon(Icons.drag_handle, size: 16)),
                ButtonSegment(value: TaskPriority.baja, label: Text('Baja'), icon: Icon(Icons.keyboard_double_arrow_down, size: 16)),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 16),

            // ── Categoría ──
            const Text('Categoría *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            _CategoryPicker(
              householdId: householdId,
              selectedId: _categoryId,
              onSelected: (id, name) => setState(() {
                _categoryId = id;
                _categoryName = name;
              }),
            ),
            const SizedBox(height: 16),

            // ── Deadline ──
            const Text('Fecha límite (opcional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickDeadline,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(_deadline == null
                  ? 'Sin fecha límite'
                  : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year}  ${_deadline!.hour.toString().padLeft(2,'0')}:${_deadline!.minute.toString().padLeft(2,'0')}'),
            ),
            if (_deadline != null)
              TextButton(
                onPressed: () => setState(() => _deadline = null),
                child: const Text('Quitar fecha', style: TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 16),

            // ── Asignado a ──
            const Text('Asignar a (opcional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            _MemberPicker(
              householdId: householdId,
              selectedUid: _assignedTo,
              onSelected: (uid) => setState(() => _assignedTo = uid),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Category Picker ──
class _CategoryPicker extends ConsumerWidget {
  final String householdId;
  final String? selectedId;
  final void Function(String id, String name) onSelected;

  const _CategoryPicker({
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
          return OutlinedButton.icon(
            onPressed: () => context.push('/home/settings/categories'),
            icon: const Icon(Icons.add),
            label: const Text('Crear primera categoría'),
          );
        }

        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(border: OutlineInputBorder()),
          value: selectedId,
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
                    backgroundColor: color.withOpacity(0.18),
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

// ── Member Picker ──
class _MemberPicker extends StatelessWidget {
  final String householdId;
  final String? selectedUid;
  final void Function(String? uid) onSelected;

  const _MemberPicker({
    required this.householdId,
    required this.selectedUid,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('households').doc(householdId)
          .collection('members')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final members = snap.data!.docs;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Opción "Sin asignar"
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
              color: selected ? color : color.withOpacity(0.2),
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
