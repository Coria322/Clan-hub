import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../application/providers/household_provider.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addCategory(String householdId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva Categoría'),
        content: TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Nombre (ej. Limpieza)'),
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final name = _nameController.text.trim();
              if (name.isNotEmpty) {
                // TODO: Obtener el UID actual para enviar a Firestore
                // Como es base, lo dejamos pendiente de conectar al authRepository
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Operación simulada. Falta conectar al Repositorio.')),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(activeHouseholdProvider);
    if (householdId == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addCategory(householdId),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('households').doc(householdId).collection('categories').where('isArchived', isEqualTo: false).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final categories = snapshot.data!.docs;

          if (categories.isEmpty) {
            return const Center(child: Text('Aún no hay categorías. Crea una.'));
          }

          return ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final catData = categories[index].data() as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.label_outline),
                title: Text(catData['name'] ?? 'Sin nombre'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    // TODO: Mover a isArchived: true
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No implementado'))
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
