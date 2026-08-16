import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/user_role.dart';

/// Exposes faculty names to students without exposing their emails.
///
/// Firestore has no field-level read security, so a rule letting a student
/// read a faculty `users` document would expose that document's email too.
/// This collection holds only what the nomination picker needs.
class FacultyDirectoryRepository {
  FacultyDirectoryRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('facultyDirectory');

  /// Written by the subject's own client — there are no Cloud Functions on
  /// Spark, so the directory is maintained client-side at sign-in.
  ///
  /// Ownership is split, and deliberately so.
  ///
  /// `fullName` and `role` are owned by the app: registration collects the
  /// name and [UserRepository.promoteFromInvite] sets the role, so both are
  /// always authoritative here and are always written.
  ///
  /// `college` and `specialization` are not. Registration never collects a
  /// college (only a program), `createStudentProfile` hardcodes
  /// `specialization: null`, and `promoteFromInvite` touches only `role` — so
  /// no code path ever fills either one, and for a real faculty account both
  /// arrive here null. They are therefore written **only when the profile
  /// actually has a value**, and a plain `set` has become a merge.
  ///
  /// Without that, this method overwrote both with null on every single
  /// sign-in. An administrator filling them in through the Firebase Console —
  /// the only way they can currently be set at all — would watch the values
  /// disappear the next time that person signed in, with no error anywhere.
  /// They feed [FacultyDirectoryEntry.subtitle], the "— CICT" that
  /// disambiguates two faculty who share a surname in the nomination picker.
  ///
  /// The merge is safe against the security rules: under `SetOptions(merge:
  /// true)` `request.resource.data` is the merged *result*, not the written
  /// subset, so `keys().hasOnly([...])` and the `role == myRole()` pin both
  /// still apply to the whole document.
  Future<void> upsertOwnEntry(AppUser user) async {
    if (user.role == UserRole.student) return;
    final college = user.college;
    final specialization = user.specialization;
    await _col.doc(user.uid).set({
      'fullName': user.fullName,
      'role': user.role.value,
      if (college != null && college.isNotEmpty) 'college': college,
      if (specialization != null && specialization.isNotEmpty)
        'specialization': specialization,
    }, SetOptions(merge: true));
  }

  Future<FacultyDirectoryEntry?> fetch(String uid) async {
    final snap = await _col.doc(uid).get();
    if (!snap.exists) return null;
    return FacultyDirectoryEntry.fromMap(uid, snap.data()!);
  }

  Future<List<FacultyDirectoryEntry>> fetchExOfficio() async {
    final snap =
        await _col.where('role', whereIn: ['coordinator', 'dean']).get();
    return snap.docs
        .map((d) => FacultyDirectoryEntry.fromMap(d.id, d.data()))
        .toList();
  }

  /// Every directory entry regardless of role: faculty, coordinators and the
  /// dean alike. The project owner ruled that coordinators and the dean can
  /// still be nominated by name as an ordinary adviser or panelist "for the
  /// sake of records," even though they also sit on every panel ex officio
  /// (via [fetchExOfficio]) without being asked to accept — so the picker
  /// that offers ordinary nominees needs the whole directory.
  ///
  /// A faculty-only slice (`watchSelectableFaculty`, with a
  /// `selectableFacultyProvider` over it) used to sit beside this one and has
  /// been removed. Under that ruling it can never be the right source for a
  /// nomination picker — it would silently drop exactly the people the owner
  /// asked to keep nominable — and nothing in `lib/` watched it. Leaving it
  /// available only invited someone to wire up the wrong one.
  Stream<List<FacultyDirectoryEntry>> watchAllDirectory() {
    return _col.snapshots().map((s) {
      final list = s.docs
          .map((d) => FacultyDirectoryEntry.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => a.fullName.compareTo(b.fullName));
      return list;
    });
  }
}
