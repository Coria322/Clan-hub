import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(FirebaseFirestore.instance);
});

class CategoryException implements Exception {
  final String message;
  CategoryException(this.message);
  @override
  String toString() => message;
}

class CategoryModel {
  final String id;
  final String name;
  final int colorValue;
  final int iconCode;
  final bool isArchived;
  final String? createdBy;
  final DateTime? createdAt;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconCode,
    required this.isArchived,
    this.createdBy,
    this.createdAt,
  });

  factory CategoryModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return CategoryModel(
      id: doc.id,
      name: d['name'] as String? ?? 'Sin nombre',
      colorValue: d['colorValue'] as int? ?? 0xFF4CAF82,
      iconCode: d['iconCode'] as int? ?? 0xe532, // Icons.label
      isArchived: d['isArchived'] as bool? ?? false,
      createdBy: d['createdBy'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class CategoryRepository {
  final FirebaseFirestore _firestore;

  CategoryRepository(this._firestore);

  CollectionReference _col(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('categories');

  // ── Streams ──────────────────────────────────────────
  Stream<List<CategoryModel>> watchActive(String householdId) {
    return _col(householdId)
        .where('isArchived', isEqualTo: false)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(CategoryModel.fromFirestore).toList());
  }

  Stream<List<CategoryModel>> watchArchived(String householdId) {
    return _col(householdId)
        .where('isArchived', isEqualTo: true)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(CategoryModel.fromFirestore).toList());
  }

  // ── Checks ───────────────────────────────────────────
  Future<bool> _isDuplicate(String householdId, String nameLower, {String? excludeId}) async {
    try {
      // Usamos timeout para no bloquear la UI si estamos offline
      final snap = await _col(householdId)
          .where('nameLower', isEqualTo: nameLower)
          .get()
          .timeout(const Duration(seconds: 2));
      if (excludeId != null) {
        return snap.docs.any((d) => d.id != excludeId);
      }
      return snap.docs.isNotEmpty;
    } catch (e) {
      // Si falla por timeout (offline), asumimos que no es duplicado para permitir crear
      return false;
    }
  }

  // ── Create ───────────────────────────────────────────
  Future<void> createCategory({
    required String householdId,
    required String name,
    required int colorValue,
    required int iconCode,
    String? createdBy,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw CategoryException('El nombre no puede estar vacío.');
    if (trimmed.length > 30) throw CategoryException('El nombre no puede superar 30 caracteres.');

    final isDup = await _isDuplicate(householdId, trimmed.toLowerCase());
    if (isDup) throw CategoryException('Ya existe una categoría con ese nombre.');

    try {
      _col(householdId).add({
        'name': trimmed,
        'nameLower': trimmed.toLowerCase(),
        'colorValue': colorValue,
        'iconCode': iconCode,
        'isArchived': false,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      }).then<void>((_) {}).catchError((e) {});
    } catch (e) {
      throw CategoryException('Error al crear la categoría: $e');
    }
  }

  // ── Update ───────────────────────────────────────────
  Future<void> updateCategory({
    required String householdId,
    required String docId,
    required String name,
    required int colorValue,
    required int iconCode,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw CategoryException('El nombre no puede estar vacío.');
    if (trimmed.length > 30) throw CategoryException('El nombre no puede superar 30 caracteres.');

    final isDup = await _isDuplicate(householdId, trimmed.toLowerCase(), excludeId: docId);
    if (isDup) throw CategoryException('Ya existe otra categoría con ese nombre.');

    try {
      _col(householdId).doc(docId).update({
        'name': trimmed,
        'nameLower': trimmed.toLowerCase(),
        'colorValue': colorValue,
        'iconCode': iconCode,
      }).catchError((e) {});
    } catch (e) {
      throw CategoryException('Error al actualizar la categoría: $e');
    }
  }

  // ── Archive / Restore ────────────────────────────────
  Future<void> archiveCategory(String householdId, String docId) async {
    try {
      _col(householdId).doc(docId).update({'isArchived': true}).catchError((e) {});
    } catch (e) {
      throw CategoryException('Error al archivar: $e');
    }
  }

  Future<void> restoreCategory(String householdId, String docId) async {
    try {
      _col(householdId).doc(docId).update({'isArchived': false}).catchError((e) {});
    } catch (e) {
      throw CategoryException('Error al restaurar: $e');
    }
  }

  // ── Delete permanent ─────────────────────────────────
  Future<void> deleteCategory(String householdId, String docId) async {
    try {
      _col(householdId).doc(docId).delete().catchError((e) {});
    } catch (e) {
      throw CategoryException('Error al eliminar: $e');
    }
  }
}
