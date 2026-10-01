import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/app_notification.dart';
import 'package:ethesishub/features/notifications/notifications_screen.dart';

AppNotification released({String? defenceId}) => AppNotification(
      id: 'n1',
      type: NotificationType.highlightsReleased,
      thesisId: 't1',
      message: "The panel's highlights on your pre-oral defence are ready "
          'to read.',
      read: false,
      createdAt: DateTime(2026, 10, 1),
      defenceId: defenceId,
    );

void main() {
  test('released highlights open the manuscript with the highlights', () {
    expect(notificationDestination(released(defenceId: 'd1')).route,
        '/defence/room/d1/manuscript');
  });

  test('without a defence id they fall back to the defences list', () {
    expect(notificationDestination(released()).route,
        '/defences?stage=preOral');
  });
}
