import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/user_role.dart';

void main() {
  group('ownership', () {
    test('a destination owns its own route', () {
      final d = destinationsFor(role: UserRole.dean)
          .firstWhere((d) => d.route == '/overview');
      expect(d.owns('/overview'), isTrue);
    });

    test('a destination owns routes nested beneath it', () {
      // Chapter detail must light up Chapters. This is the case the
      // sidebar exists to get right.
      final chapters = destinationsFor(
        role: UserRole.student,
        chaptersUnlocked: true,
      ).firstWhere((d) => d.route == '/thesis/chapters');

      expect(chapters.owns('/thesis/chapters/chapterIII'), isTrue);
    });

    test('a destination does NOT own a route that merely shares a prefix', () {
      // Spec D24. '/defences' and '/defence/room/:id' are one character
      // apart and are different screens. Naive `startsWith` would light
      // Defences for the defence room, telling the reader they are
      // somewhere they are not.
      final defences = destinationsFor(role: UserRole.dean)
          .firstWhere((d) => d.route == '/defences');

      expect(defences.owns('/defence/room/d1'), isFalse);
      expect(defences.owns('/defence/schedule'), isFalse);
    });

    test('an unowned location resolves to no destination at all', () {
      final ds = destinationsFor(role: UserRole.dean);
      expect(destinationForLocation(ds, '/defence/room/d1'), isNull);
    });
  });

  group('depth', () {
    test('a destination route is not deeper than itself', () {
      final ds = destinationsFor(role: UserRole.student, chaptersUnlocked: true);
      expect(isDeeperThanDestination(ds, '/thesis/chapters'), isFalse);
    });

    test('a route nested under a destination is deeper', () {
      final ds = destinationsFor(role: UserRole.student, chaptersUnlocked: true);
      expect(isDeeperThanDestination(ds, '/thesis/chapters/chapterIII'), isTrue);
    });

    test('a route no destination owns is deeper', () {
      // The sidebar cannot return the reader anywhere useful from here,
      // so a back control must appear.
      final ds = destinationsFor(role: UserRole.student, chaptersUnlocked: true);
      expect(isDeeperThanDestination(ds, '/defence/room/d1'), isTrue);
    });
  });

  group('per-role lists', () {
    test('every role gets Overview first', () {
      for (final role in UserRole.values) {
        expect(destinationsFor(role: role).first.route, '/overview',
            reason: '$role does not land on the overview');
      }
    });

    test('a student without an approved title gets no Chapters or Defences', () {
      // A destination that leads to "not open yet" reads as a broken app.
      final ds = destinationsFor(role: UserRole.student);
      expect(ds.map((d) => d.route), isNot(contains('/thesis/chapters')));
      expect(ds.map((d) => d.route), isNot(contains('/defences')));
    });

    test('a student with an approved title gets both', () {
      final ds =
          destinationsFor(role: UserRole.student, chaptersUnlocked: true);
      expect(ds.map((d) => d.route), contains('/thesis/chapters'));
      expect(ds.map((d) => d.route), contains('/defences'));
    });

    test('faculty sees Advisees in adviser mode and Panels in panelist mode',
        () {
      // Spec D5: the mode is the primary axis and each mode is its own
      // clean list. Both directions, or a filter left in one branch
      // passes.
      final adviser = destinationsFor(
        role: UserRole.faculty,
        facultyMode: FacultyMode.adviser,
      ).map((d) => d.route);
      expect(adviser, contains('/advisees'));
      expect(adviser, isNot(contains('/panels')));

      final panelist = destinationsFor(
        role: UserRole.faculty,
        facultyMode: FacultyMode.panelist,
      ).map((d) => d.route);
      expect(panelist, contains('/panels'));
      expect(panelist, isNot(contains('/advisees')));
    });

    test('the coordinator gets Faculty and the dean does not', () {
      expect(
        destinationsFor(role: UserRole.coordinator).map((d) => d.route),
        contains('/invites'),
      );
      expect(
        destinationsFor(role: UserRole.dean).map((d) => d.route),
        isNot(contains('/invites')),
      );
    });

    test('no role is given a route that does not exist in the app', () {
      // Every destination must be a real registered path. A destination
      // that leads nowhere reads as a broken app, not an unfinished one.
      const known = {
        '/overview', '/thesis', '/thesis/chapters', '/defences',
        '/advisees', '/panels', '/nominations', '/approvals',
        '/recommendations', '/title-defences', '/readiness', '/invites',
      };
      for (final role in UserRole.values) {
        for (final d in destinationsFor(
          role: role,
          chaptersUnlocked: true,
        )) {
          expect(known, contains(d.route), reason: '$role → ${d.route}');
        }
      }
    });
  });
}
