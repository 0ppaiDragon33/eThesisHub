import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/repositories/faculty_directory_repository.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';

/// Stands in for `facultyDirectory` under the REAL security rules.
///
/// `fake_cloud_firestore` answers `not-found` when you update a document that
/// does not exist, and `UserRepository.setDesignation` already swallows that
/// — so a test built on the fake alone passes whether or not the bug is
/// present, and proves nothing.
///
/// Firestore does not behave that way. `mayCoordinatorSetDesignation` in
/// `firestore.rules` requires `resource != null` — it is update-only — so
/// when the entry is missing that arm cannot pass, and a refused rule is
/// reported as **permission-denied**, never as not-found. That is the case
/// this fake reproduces: `setDesignation` refuses unless the uid is known.
///
/// Creating the entry is a separate arm
/// (`mayCoordinatorCreateDirectoryEntry`), which is why the fake accepts
/// `createForDesignation` for a uid it would refuse to update.
class _RulesLikeDirectory implements FacultyDirectoryRepository {
  _RulesLikeDirectory({required this.existingUids});

  final Set<String> existingUids;
  final List<String> designationWrites = [];
  final List<String> created = [];

  @override
  Future<void> createForDesignation({
    required AppUser user,
    required bool adviser,
    required bool panelist,
  }) async {
    created.add(user.uid);
    existingUids.add(user.uid);
  }

  @override
  Future<void> setDesignation({
    required String uid,
    required bool adviser,
    required bool panelist,
  }) async {
    designationWrites.add(uid);
    if (!existingUids.contains(uid)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
    }
  }

  @override
  Future<FacultyDirectoryEntry?> fetch(String uid) async =>
      existingUids.contains(uid)
          ? FacultyDirectoryEntry(
              uid: uid,
              fullName: 'Seeded',
              role: 'faculty',
              college: 'CICT',
              specialization: null,
              nominableAsAdviser: false,
              nominableAsPanelist: false,
            )
          : null;

  @override
  Future<void> upsertOwnEntry(AppUser user) async {}

  @override
  Future<List<FacultyDirectoryEntry>> fetchExOfficio() async => const [];

  @override
  Stream<List<FacultyDirectoryEntry>> watchAllDirectory() =>
      const Stream.empty();
}

void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('f1').set({
      'fullName': 'Jepte Solinap',
      'email': 'jepte_solinap12@isufst.edu.ph',
      'role': 'faculty',
      'active': true,
      'nominableAsAdviser': false,
      'nominableAsPanelist': false,
    });
  });

  // Spec §4.2.1 names this window: an invited faculty account that has never
  // signed in has no directory entry, because the entry is only written
  // client-side at sign-in. Designating them must still work — the
  // authoritative flags live on `users`, and the directory is only a mirror
  // the student-facing picker can read.
  test('designating an account that has never signed in still succeeds',
      () async {
    final directory = _RulesLikeDirectory(existingUids: <String>{});
    final repo = UserRepository(db, directory);

    await repo.setDesignation(uid: 'f1', adviser: true, panelist: true);

    final saved = (await db.collection('users').doc('f1').get()).data()!;
    expect(saved['nominableAsAdviser'], isTrue);
    expect(saved['nominableAsPanelist'], isTrue);
  });

  test('the entry is created rather than updated when none exists', () async {
    final directory = _RulesLikeDirectory(existingUids: <String>{});
    final repo = UserRepository(db, directory);

    await repo.setDesignation(uid: 'f1', adviser: true, panelist: false);

    // An update here would be refused — `mayCoordinatorSetDesignation` is
    // update-only. Creating instead is what stops the designation sitting
    // inert on `users` until this person's first sign-in. Swallowing the
    // refusal would also have silenced the error, but it would have
    // swallowed a genuine authorization failure with it.
    expect(directory.designationWrites, isEmpty);
    expect(directory.created, ['f1']);
  });

  test('an existing entry is still mirrored', () async {
    final directory = _RulesLikeDirectory(existingUids: <String>{'f1'});
    final repo = UserRepository(db, directory);

    await repo.setDesignation(uid: 'f1', adviser: true, panelist: false);

    expect(directory.designationWrites, ['f1']);
  });

  // The narrow swallow must not become a blanket one: if the entry exists and
  // the rules still refuse, the coordinator has to hear about it.
  test('a refusal on an entry that DOES exist is still surfaced', () async {
    final directory = _AlwaysRefuses();
    final repo = UserRepository(db, directory);

    await expectLater(
      repo.setDesignation(uid: 'f1', adviser: true, panelist: false),
      throwsA(isA<FirebaseException>()
          .having((e) => e.code, 'code', 'permission-denied')),
    );
  });
}

/// An entry that exists but whose write is refused anyway — a coordinator who
/// has lost the role, or a rules change. This must still reach the screen.
class _AlwaysRefuses extends _RulesLikeDirectory {
  _AlwaysRefuses() : super(existingUids: const {'f1'});

  @override
  Future<void> setDesignation({
    required String uid,
    required bool adviser,
    required bool panelist,
  }) async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Missing or insufficient permissions.',
    );
  }
}
