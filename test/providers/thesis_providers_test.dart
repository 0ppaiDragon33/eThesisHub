import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/faculty_directory_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

void main() {
  test('selectableFacultyProvider exposes only faculty', () async {
    final db = FakeFirebaseFirestore();
    final repo = FacultyDirectoryRepository(db);
    await repo.upsertOwnEntry(AppUser(
      uid: 'f1', fullName: 'Dr. Armada', email: 'a@isufst.edu.ph',
      role: UserRole.faculty, active: true, createdAt: DateTime.utc(2026),
    ));
    await repo.upsertOwnEntry(AppUser(
      uid: 'd1', fullName: 'Dr. Siason', email: 'd@isufst.edu.ph',
      role: UserRole.dean, active: true, createdAt: DateTime.utc(2026),
    ));

    final container = ProviderContainer(
      overrides: [firestoreProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final faculty = await container.read(selectableFacultyProvider.future);
    expect(faculty.map((e) => e.uid), ['f1']);
  });
}
