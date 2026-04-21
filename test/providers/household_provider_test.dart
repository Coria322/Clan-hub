import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:clanhub/application/providers/household_provider.dart';

void main() {
  group('ActiveHouseholdNotifier', () {
    test('initial state is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(activeHouseholdProvider);
      expect(state, isNull);
    });

    test('setHousehold updates the state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(activeHouseholdProvider.notifier).setHousehold('hogar_123');
      final state = container.read(activeHouseholdProvider);
      expect(state, 'hogar_123');
    });

    test('clear sets the state back to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(activeHouseholdProvider.notifier).setHousehold('hogar_123');
      expect(container.read(activeHouseholdProvider), 'hogar_123');

      container.read(activeHouseholdProvider.notifier).clear();
      expect(container.read(activeHouseholdProvider), isNull);
    });
  });
}
