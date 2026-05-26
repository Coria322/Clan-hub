import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final householdRepositoryProvider = Provider<HouseholdRepository>((ref) {
  return HouseholdRepository(ref.watch(firestoreProvider));
});

class HouseholdException implements Exception {
  final String message;
  HouseholdException(this.message);
  @override
  String toString() => message;
}

class HouseholdRepository {
  final FirebaseFirestore _firestore;

  HouseholdRepository(this._firestore);

  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return String.fromCharCodes(Iterable.generate(
      6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Future<String> createHousehold(String name, String adminUid, String adminDisplayName) async {
    try {
      final householdRef = _firestore.collection('households').doc();
      final inviteCode = _generateInviteCode();

      final batch = _firestore.batch();
      
      batch.set(householdRef, {
        'id': householdRef.id,
        'name': name,
        'inviteCode': inviteCode,
        'adminUid': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final adminMemberRef = householdRef.collection('members').doc(adminUid);
      batch.set(adminMemberRef, {
        'uid': adminUid,
        'displayName': adminDisplayName,
        'role': 'admin',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      // set con merge:true funciona aunque el campo no exista aún en el documento
      final userRef = _firestore.collection('users').doc(adminUid);
      batch.set(userRef, {
        'households': FieldValue.arrayUnion([householdRef.id])
      }, SetOptions(merge: true));

      await batch.commit();
      return householdRef.id;
    } catch (e) {
      throw HouseholdException('Error al crear el hogar: $e');
    }
  }

  Future<void> updateHouseholdNote(String householdId, String note) async {
    try {
      await _firestore.collection('households').doc(householdId).update({
        'note': note,
      });
    } catch (e) {
      throw HouseholdException('Error al actualizar la nota: $e');
    }
  }

  Future<String> joinHousehold(String inviteCode, String userUid, String userDisplayName) async {
    try {
      final querySnapshot = await _firestore
          .collection('households')
          .where('inviteCode', isEqualTo: inviteCode.toUpperCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw HouseholdException('Código de invitación no válido o no encontrado.');
      }

      final householdDoc = querySnapshot.docs.first;
      final householdId = householdDoc.id;

      final memberRef = _firestore.collection('households').doc(householdId).collection('members').doc(userUid);

      final batch = _firestore.batch();
      
      batch.set(memberRef, {
        'uid': userUid,
        'displayName': userDisplayName,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      final userRef = _firestore.collection('users').doc(userUid);
      batch.set(userRef, {
        'households': FieldValue.arrayUnion([householdId])
      }, SetOptions(merge: true));

      await batch.commit();

      return householdId;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw HouseholdException('No tienes permiso o ya eres miembro de este hogar.');
      }
      throw HouseholdException('Error de base de datos: ${e.message}');
    } on HouseholdException {
      rethrow;
    } catch (e) {
      throw HouseholdException('Error al unirse al hogar: $e');
    }
  }

  Future<void> deleteHousehold(String householdId, String adminUid) async {
    try {
      final batch = _firestore.batch();

      // 1. Eliminar todos los miembros de la subcolección
      final membersSnapshot = await _firestore
          .collection('households')
          .doc(householdId)
          .collection('members')
          .get();
      for (final doc in membersSnapshot.docs) {
        batch.delete(doc.reference);
        // Solo podemos limpiar el perfil del propio admin (regla: solo el dueño puede escribir su perfil)
        // Los perfiles de otros miembros se limpian en el siguiente login (splash inteligente)
        if (doc.id == adminUid) {
          batch.set(
            _firestore.collection('users').doc(adminUid),
            {'households': FieldValue.arrayRemove([householdId])},
            SetOptions(merge: true),
          );
        }
      }

      // 2. Eliminar todas las categorías de la subcolección
      final categoriesSnapshot = await _firestore
          .collection('households')
          .doc(householdId)
          .collection('categories')
          .get();
      for (final doc in categoriesSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // 3. Eliminar el documento del hogar
      final householdRef = _firestore.collection('households').doc(householdId);
      batch.delete(householdRef);

      await batch.commit();
    } on FirebaseException catch (e) {
      throw HouseholdException('Error al eliminar el hogar: ${e.message}');
    } catch (e) {
      throw HouseholdException('Error al eliminar el hogar: $e');
    }
  }

  /// El admin elimina a un miembro (que no es él mismo) del hogar.
  Future<void> removeMember(String householdId, String targetUid) async {
    try {
      final memberRef = _firestore
          .collection('households')
          .doc(householdId)
          .collection('members')
          .doc(targetUid);

      // Solo eliminamos el doc del miembro.
      // La limpieza del perfil del usuario eliminado queda pendiente para su próximo login
      // (ya que el admin no puede escribir en perfiles ajenos - regla isOwner).
      await memberRef.delete();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw HouseholdException('Solo el administrador puede eliminar miembros.');
      }
      throw HouseholdException('Error al eliminar miembro: ${e.message}');
    } catch (e) {
      throw HouseholdException('Error al eliminar miembro: $e');
    }
  }

  Future<String?> leaveHousehold(String householdId, String userUid) async {
    try {
      final batch = _firestore.batch();
      
      // Eliminar el doc de miembro
      final memberRef = _firestore
          .collection('households')
          .doc(householdId)
          .collection('members')
          .doc(userUid);
      batch.delete(memberRef);

      // Quitar el hogar del perfil del usuario
      batch.set(_firestore.collection('users').doc(userUid), {
        'households': FieldValue.arrayRemove([householdId])
      }, SetOptions(merge: true));

      await batch.commit();
      return null;
    } on FirebaseException catch (e) {
      throw HouseholdException('Error al abandonar el hogar: ${e.message}');
    }
  }

  Future<List<Map<String, String>>> getUserHouseholds(String userUid) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userUid).get();
      if (!userDoc.exists) return [];

      final data = userDoc.data() ?? {};
      final rawHouseholds = List<String>.from(data['households'] ?? []);

      final List<Map<String, String>> households = [];
      final staleIds = <String>[];

      for (final id in rawHouseholds) {
        final hDoc = await _firestore.collection('households').doc(id).get();
        if (hDoc.exists) {
          final memberDoc = await _firestore
              .collection('households')
              .doc(id)
              .collection('members')
              .doc(userUid)
              .get();

          if (memberDoc.exists) {
            households.add({
              'id': id,
              'name': (hDoc.data()?['name'] as String?) ?? 'Sin nombre',
            });
          } else {
            staleIds.add(id);
          }
        } else {
          staleIds.add(id);
        }
      }

      if (staleIds.isNotEmpty) {
        // Clean up orphaned households in the background
        _firestore.collection('users').doc(userUid).set({
          'households': FieldValue.arrayRemove(staleIds)
        }, SetOptions(merge: true));
      }

      return households;
    } catch (e) {
      throw HouseholdException('Error al obtener los hogares: $e');
    }
  }
}

