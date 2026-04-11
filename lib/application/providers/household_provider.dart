import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../infrastructure/household/household_repository.dart';

// Este state guarda el ID del hogar activo
class ActiveHouseholdNotifier extends StateNotifier<String?> {
  ActiveHouseholdNotifier() : super(null);

  void setHousehold(String householdId) {
    state = householdId;
  }
  
  void clear() {
    state = null;
  }
}

final activeHouseholdProvider = StateNotifierProvider<ActiveHouseholdNotifier, String?>((ref) {
  return ActiveHouseholdNotifier();
});

// Proveedor para obtener de forma asíncrona los hogares a los que pertenece el usuario autenticado
final userHouseholdsProvider = FutureProvider<List<String>>((ref) async {
  final authState = ref.watch(authStateChangesProvider);
  final user = authState.value;

  if (user == null) {
    return [];
  }

  final repo = ref.watch(householdRepositoryProvider);
  return repo.getUserHouseholds(user.uid);
});
