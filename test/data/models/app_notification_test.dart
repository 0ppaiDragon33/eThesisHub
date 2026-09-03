// test/data/models/app_notification_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/app_notification.dart';

void main() {
  group('NotificationType', () {
    test('round-trips through its string value', () {
      for (final type in NotificationType.values) {
        expect(NotificationType.fromString(type.value), type);
      }
    });

    test('an unrecognised or null string falls back to chapterFeedback', () {
      expect(NotificationType.fromString('made_up'), NotificationType.chapterFeedback);
      expect(NotificationType.fromString(null), NotificationType.chapterFeedback);
    });
  });

  group('notificationId', () {
    test('is deterministic for the same type and source key', () {
      final a = notificationId(NotificationType.defenceComment, 'c1');
      final b = notificationId(NotificationType.defenceComment, 'c1');
      expect(a, b);
    });

    test('differs across types for the same source key', () {
      final a = notificationId(NotificationType.defenceComment, 'x1');
      final b = notificationId(NotificationType.evaluationAwaits, 'x1');
      expect(a, isNot(b));
    });
  });

  group('AppNotification', () {
    test('round-trips through fromMap/toMap', () {
      final n = AppNotification(
        id: notificationId(NotificationType.archivePublished, 't1'),
        type: NotificationType.archivePublished,
        thesisId: 't1',
        message: 'Your thesis was published to the archive.',
        read: false,
        createdAt: DateTime(2026, 9, 3, 10, 30),
      );
      final back = AppNotification.fromMap(n.id, n.toMap());

      expect(back.id, n.id);
      expect(back.type, n.type);
      expect(back.thesisId, n.thesisId);
      expect(back.message, n.message);
      expect(back.read, n.read);
      expect(back.createdAt, n.createdAt);
    });

    test('copyWith(read: true) changes only read', () {
      final n = AppNotification(
        id: 'x',
        type: NotificationType.chapterFeedback,
        thesisId: 't1',
        message: 'm',
        read: false,
        createdAt: DateTime(2026, 1, 1),
      );
      final read = n.copyWith(read: true);

      expect(read.read, isTrue);
      expect(read.id, n.id);
      expect(read.message, n.message);
      expect(read.createdAt, n.createdAt);
    });
  });
}
