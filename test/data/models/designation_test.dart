import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';

void main() {
  group('AppUser designation', () {
    test('a document with no designation keys reads as nominable for both',
        () {
      // Every account that exists today predates these fields. If absence
      // meant "not nominable", deploying this would make every current
      // faculty member unpickable at once, with no error anywhere.
      final u = AppUser.fromMap('u1', {
        'fullName': 'Dr. A',
        'email': 'a@isufst.edu.ph',
        'role': 'faculty',
        'active': true,
      });
      expect(u.nominableAsAdviser, isTrue);
      expect(u.nominableAsPanelist, isTrue);
    });

    test('an explicit false is honoured', () {
      final u = AppUser.fromMap('u1', {
        'fullName': 'Dr. A',
        'email': 'a@isufst.edu.ph',
        'role': 'faculty',
        'active': true,
        'nominableAsAdviser': false,
        'nominableAsPanelist': true,
      });
      expect(u.nominableAsAdviser, isFalse);
      expect(u.nominableAsPanelist, isTrue);
    });

    test('the two are independent', () {
      // Two booleans rather than one enum, because the four states are a
      // product of two independent facts.
      final u = AppUser.fromMap('u1', {
        'fullName': 'Dr. A',
        'email': 'a@isufst.edu.ph',
        'role': 'faculty',
        'active': true,
        'nominableAsAdviser': true,
        'nominableAsPanelist': false,
      });
      expect(u.nominableAsAdviser, isTrue);
      expect(u.nominableAsPanelist, isFalse);
    });
  });

  group('FacultyDirectoryEntry designation', () {
    test('a mirror with no designation keys reads as nominable for both', () {
      final e = FacultyDirectoryEntry.fromMap('u1', {
        'fullName': 'Dr. A',
        'role': 'faculty',
      });
      expect(e.nominableAsAdviser, isTrue);
      expect(e.nominableAsPanelist, isTrue);
    });

    test('an explicit false is honoured', () {
      final e = FacultyDirectoryEntry.fromMap('u1', {
        'fullName': 'Dr. A',
        'role': 'faculty',
        'nominableAsAdviser': false,
      });
      expect(e.nominableAsAdviser, isFalse);
      expect(e.nominableAsPanelist, isTrue);
    });

    test('toMap does NOT write designation', () {
      // upsertOwnEntry round-trips through toMap, and the subject may not
      // write their own designation -- that is spec D27's whole point.
      // Including it here would send the field on every sign-in.
      final e = FacultyDirectoryEntry.fromMap('u1', {
        'fullName': 'Dr. A',
        'role': 'faculty',
        'nominableAsAdviser': false,
      });
      expect(e.toMap().containsKey('nominableAsAdviser'), isFalse);
      expect(e.toMap().containsKey('nominableAsPanelist'), isFalse);
    });
  });
}
