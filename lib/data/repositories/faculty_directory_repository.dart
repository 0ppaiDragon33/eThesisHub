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
  Future<void> upsertOwnEntry(AppUser user) async {
    if (user.role == UserRole.student) return;
    await _col.doc(user.uid).set({
      'fullName': user.fullName,
      'role': user.role.value,
      'college': user.college,
      'specialization': user.specialization,
    });
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
