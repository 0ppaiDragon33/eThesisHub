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

  /// Only `faculty` — the dean and coordinators are ex officio and must not
  /// appear in the picker.
  Stream<List<FacultyDirectoryEntry>> watchSelectableFaculty() {
    return _col.where('role', isEqualTo: 'faculty').snapshots().map((s) {
      final list = s.docs
          .map((d) => FacultyDirectoryEntry.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => a.fullName.compareTo(b.fullName));
      return list;
    });
  }

  Future<List<FacultyDirectoryEntry>> fetchExOfficio() async {
    final snap =
        await _col.where('role', whereIn: ['coordinator', 'dean']).get();
    return snap.docs
        .map((d) => FacultyDirectoryEntry.fromMap(d.id, d.data()))
        .toList();
  }
}
