import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../application/providers/household_provider.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../infrastructure/household/category_repository.dart';

// ── Paleta de colores disponibles ──────────────────────────────────────────
const _kColors = [
  Color(0xFF4CAF82),
  Color(0xFF64B5F6),
  Color(0xFFFF8A65),
  Color(0xFFE57373),
  Color(0xFFFFD54F),
  Color(0xFFBA68C8),
  Color(0xFF4DB6AC),
  Color(0xFFF06292),
  Color(0xFF9575CD),
  Color(0xFFAED581),
  Color(0xFF90A4AE),
  Color(0xFFFF8F00),
];

// ── Set de iconos disponibles ─────────────────────────────────────────────
const _kIcons = <IconData>[
  Icons.label,
  Icons.cleaning_services,
  Icons.shopping_cart,
  Icons.kitchen,
  Icons.local_laundry_service,
  Icons.yard,
  Icons.pets,
  Icons.car_repair,
  Icons.build,
  Icons.medical_services,
  Icons.school,
  Icons.fitness_center,
  Icons.restaurant,
  Icons.local_grocery_store,
  Icons.home_repair_service,
  Icons.directions_car,
  Icons.recycling,
  Icons.water_drop,
  Icons.electric_bolt,
  Icons.child_care,
];

Color _colorOf(int value) {
  try {
    return _kColors.firstWhere((c) => c.value == value);
  } catch (_) {
    return _kColors.first;
  }
}

IconData _iconOf(int code) {
  try {
    return _kIcons.firstWhere((i) => i.codePoint == code);
  } catch (_) {
    return Icons.label;
  }
}

// ── Main Screen ───────────────────────────────────────────────────────────
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Admin status — actualizado por StreamSubscription para evitar
  // anidamiento de builders que causa _dependents.isEmpty
  bool _isAdmin = false;
  StreamSubscription<DocumentSnapshot>? _householdSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeHousehold();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  void _subscribeHousehold() {
    final householdId = ref.read(activeHouseholdProvider);
    final currentUser = ref.read(authRepositoryProvider).currentUser;
    if (householdId == null || currentUser == null) return;

    _householdSub?.cancel();
    _householdSub = FirebaseFirestore.instance
        .collection('households')
        .doc(householdId)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final adminUid = (snap.data())?['adminUid'] as String?;
          final isAdmin = currentUser.uid == adminUid;
          if (_isAdmin != isAdmin) setState(() => _isAdmin = isAdmin);
        });
  }

  @override
  void dispose() {
    _householdSub?.cancel();
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  // ── Diálogo crear / editar ──────────────────────────────────────────────
  Future<void> _showCategoryDialog(
    String householdId,
    String currentUserUid, {
    CategoryModel? editing,
  }) async {
    // Estado local del diálogo — fuera del árbol de widgets para evitar
    // problemas con InheritedWidget al reconstruir.
    var selectedColor = editing != null
        ? _colorOf(editing.colorValue)
        : _kColors.first;
    var selectedIcon = editing != null
        ? _iconOf(editing.iconCode)
        : _kIcons.first;
    final initialName = editing?.name ?? '';

    await showDialog(
      context: context, // <-- contexto estable del ConsumerState
      barrierDismissible: false,
      builder: (ctx) {
        return _CategoryDialog(
          initialName: initialName,
          initialColor: selectedColor,
          initialIcon: selectedIcon,
          editing: editing,
          onSave: (name, color, icon) async {
            final repo = ref.read(categoryRepositoryProvider);
            if (editing == null) {
              await repo.createCategory(
                householdId: householdId,
                name: name,
                colorValue: color.value,
                iconCode: icon.codePoint,
                createdBy: currentUserUid,
              );
            } else {
              await repo.updateCategory(
                householdId: householdId,
                docId: editing.id,
                name: name,
                colorValue: color.value,
                iconCode: icon.codePoint,
              );
            }
          },
        );
      },
    );
  }

  // ── Archivar ──────────────────────────────────────────────────────────
  Future<void> _archive(String householdId, CategoryModel cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Archivar categoría?'),
        content: Text(
          'Las tareas que usen "${cat.name}" conservarán la referencia, '
          'pero no aparecerá al crear nuevas tareas.\n\nPuedes restaurarla desde la pestaña Archivadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(categoryRepositoryProvider)
          .archiveCategory(householdId, cat.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // ── Restaurar ─────────────────────────────────────────────────────────
  Future<void> _restore(String householdId, CategoryModel cat) async {
    try {
      await ref
          .read(categoryRepositoryProvider)
          .restoreCategory(householdId, cat.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('"${cat.name}" restaurada')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // ── Eliminar permanente ───────────────────────────────────────────────
  Future<void> _deletePermanent(String householdId, CategoryModel cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar definitivamente?'),
        content: Text('¿Seguro que quieres borrar "${cat.name}" para siempre?'),
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
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(categoryRepositoryProvider)
          .deleteCategory(householdId, cat.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // ── Tiles ─────────────────────────────────────────────────────────────
  Widget _activeTile(
    String householdId,
    String currentUserUid,
    CategoryModel cat,
  ) {
    final color = _colorOf(cat.colorValue);
    final icon = _iconOf(cat.iconCode);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.18),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          cat.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: _isAdmin
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Editar',
                    onPressed: () => _showCategoryDialog(
                      householdId,
                      currentUserUid,
                      editing: cat,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.archive_outlined,
                      color: Colors.orange,
                    ),
                    tooltip: 'Archivar',
                    onPressed: () => _archive(householdId, cat),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _archivedTile(String householdId, CategoryModel cat) {
    final icon = _iconOf(cat.iconCode);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: Colors.grey.shade50,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey.shade200,
          child: Icon(icon, color: Colors.grey.shade400, size: 22),
        ),
        title: Text(cat.name, style: TextStyle(color: Colors.grey.shade500)),
        subtitle: const Text('Archivada'),
        trailing: _isAdmin
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.restore, color: Colors.green),
                    tooltip: 'Restaurar',
                    onPressed: () => _restore(householdId, cat),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    tooltip: 'Eliminar definitivamente',
                    onPressed: () => _deletePermanent(householdId, cat),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(activeHouseholdProvider);
    if (householdId == null) return const Scaffold();

    final currentUserUid =
        ref.read(authRepositoryProvider).currentUser?.uid ?? '';
    final repo = ref.read(categoryRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.label_outline), text: 'Activas'),
            Tab(icon: Icon(Icons.archive_outlined), text: 'Archivadas'),
          ],
        ),
      ),
      // FAB solo en tab 0 y solo si es admin — sin builders anidados
      floatingActionButton: (_tabs.index == 0 && _isAdmin)
          ? FloatingActionButton.extended(
              onPressed: () => _showCategoryDialog(householdId, currentUserUid),
              icon: const Icon(Icons.add),
              label: const Text('Nueva categoría'),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          // ── Tab 0: Activas ──────────────────────────────────────────
          StreamBuilder<List<CategoryModel>>(
            stream: repo.watchActive(householdId),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final cats = snap.data!;
              if (cats.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.label_off_outlined,
                        size: 72,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aún no hay categorías.\n¡Crea la primera!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                itemCount: cats.length,
                itemBuilder: (_, i) =>
                    _activeTile(householdId, currentUserUid, cats[i]),
              );
            },
          ),

          // ── Tab 1: Archivadas ───────────────────────────────────────
          StreamBuilder<List<CategoryModel>>(
            stream: repo.watchArchived(householdId),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final cats = snap.data!;
              if (cats.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 72,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No hay categorías archivadas.',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                itemCount: cats.length,
                itemBuilder: (_, i) => _archivedTile(householdId, cats[i]),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Diálogo como StatefulWidget dedicado ─────────────────────────────────────
// Separar el dialog en su propio StatefulWidget evita el problema de
// _dependents.isEmpty que ocurre con StatefulBuilder dentro de AlertDialog
// cuando hay reconstrucciones por teclado u otras causas.
class _CategoryDialog extends StatefulWidget {
  final String initialName;
  final Color initialColor;
  final IconData initialIcon;
  final CategoryModel? editing;
  final Future<void> Function(String name, Color color, IconData icon) onSave;

  const _CategoryDialog({
    required this.initialName,
    required this.initialColor,
    required this.initialIcon,
    required this.editing,
    required this.onSave,
  });

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late TextEditingController _nameCtrl;
  late Color _selectedColor;
  late IconData _selectedIcon;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _selectedColor = widget.initialColor;
    _selectedIcon = widget.initialIcon;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.onSave(name, _selectedColor, _selectedIcon);
      if (mounted) {
        FocusScope.of(context).unfocus();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editing != null;

    return AlertDialog(
      title: Text(isEditing ? 'Editar Categoría' : 'Nueva Categoría'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Nombre ──
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                hintText: 'ej. Limpieza, Compras...',
                border: OutlineInputBorder(),
              ),
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              // autofocus removido — causaba problemas con _dependents
              // al mostrar/ocultar el teclado mientras se reconstruía
            ),
            const SizedBox(height: 16),

            // ── Color ──
            const Text(
              'Color',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kColors.map((color) {
                final selected = _selectedColor.value == color.value;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.black87 : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.5),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Icono ──
            const Text(
              'Ícono',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kIcons.map((icon) {
                final selected = _selectedIcon.codePoint == icon.codePoint;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIcon = icon),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: selected
                          ? _selectedColor
                          : _selectedColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: selected ? Colors.white : _selectedColor,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(isEditing ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}
