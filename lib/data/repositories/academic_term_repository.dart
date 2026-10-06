import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/academic_term.dart';

/// The college's current term, `settings/academicTerm`. Anyone signed in
/// reads it; only the Coordinator sets it (see `firestore.rules`).
class AcademicTermRepository {
  AcademicTermRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('settings').doc('academicTerm');

  /// Null until the Coordinator sets one.
  Stream<AcademicTerm?> watchCurrent() => _doc.snapshots().map((s) {
        final d = s.data();
        if (d == null) return null;
        final term = AcademicTerm.fromMap(d);
        return term.isValid ? term : null;
      });

  Future<void> setCurrent(AcademicTerm term, {required String coordinatorUid}) {
    if (!term.isValid) {
      throw ArgumentError('Choose a semester and an academic year.');
    }
    return _doc.set({
      'semester': term.semester,
      'academicYear': term.academicYear,
      'updatedBy': coordinatorUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
