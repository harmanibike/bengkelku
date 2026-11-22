import 'package:flutter_test/flutter_test.dart';
import 'package:bengkelku/features/services/data/service_repository.dart';

void main() {
  group('Service status workflow', () {
    test('waiting can move to checking or cancelled', () {
      expect(
        ServiceRepository.allowedStatusTransitions['waiting'],
        containsAll(['checking', 'cancelled']),
      );
    });

    test('completed can be delivered or returned to in progress', () {
      expect(
        ServiceRepository.allowedStatusTransitions['completed'],
        containsAll(['delivered', 'in_progress']),
      );
    });

    test('delivered and cancelled are terminal statuses', () {
      expect(ServiceRepository.allowedStatusTransitions['delivered'], isEmpty);
      expect(ServiceRepository.allowedStatusTransitions['cancelled'], isEmpty);
    });

    test('every transition target is a known service status', () {
      for (final targets
          in ServiceRepository.allowedStatusTransitions.values) {
        expect(ServiceRepository.serviceStatuses, containsAll(targets));
      }
    });
  });
}
