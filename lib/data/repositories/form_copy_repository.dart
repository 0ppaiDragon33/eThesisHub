import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/form_copy.dart';

/// The longest copy name `firestore.rules` accepts.
const int kFormCopyNameMax = 100;

/// A person's saved form copies, at `users/{uid}/formCopies`.
class FormCopyRepository {
  FormCopyRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _copies(String uid) =>
      _db.collection('users').doc(uid).collection('formCopies');

  /// This person's copies of [formId], most recently edited first.
  ///
  /// Filtered and sorted here rather than in the query: one person holds a
  /// handful of copies, and a `where` + `orderBy` pair would need a
  /// composite index deployed before the screen could load at all.
  Stream<List<FormCopy>> watchCopies(String uid, {required String formId}) {
    return _copies(uid).snapshots().map((s) {
      final copies = [
        for (final d in s.docs) FormCopy.fromMap(d.id, d.data()),
      ].where((c) => c.formId == formId).toList();
      copies.sort((a, b) {
        final at = a.updatedAt;
        final bt = b.updatedAt;
        // Not yet stamped means written a moment ago: newest.
        if (at == null && bt == null) return 0;
        if (at == null) return -1;
        if (bt == null) return 1;
        return bt.compareTo(at);
      });
      return copies;
    });
  }

  /// One copy, or null once it has been deleted.
  Stream<FormCopy?> watchCopy(String uid, String copyId) =>
      _copies(uid).doc(copyId).snapshots().map(
            (d) => d.exists ? FormCopy.fromMap(d.id, d.data()!) : null,
          );

  /// Creates an unedited copy and returns its id.
  Future<String> create({
    required String uid,
    required String formId,
    required String name,
  }) async {
    final ref = _copies(uid).doc();
    await ref.set({
      'formId': formId,
      'name': _checkedName(name),
      'overrides': <String, String>{},
      'folderId': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Replaces the copy's stored edits with [overrides].
  Future<void> saveOverrides({
    required String uid,
    required String copyId,
    required Map<String, String> overrides,
  }) =>
      _copies(uid).doc(copyId).update({
        'overrides': overrides,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> rename({
    required String uid,
    required String copyId,
    required String name,
  }) =>
      _copies(uid).doc(copyId).update({
        'name': _checkedName(name),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> delete({required String uid, required String copyId}) =>
      _copies(uid).doc(copyId).delete();

  static String _checkedName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > kFormCopyNameMax) {
      throw ArgumentError.value(
          name, 'name', 'must be 1 to $kFormCopyNameMax characters');
    }
    return trimmed;
  }
}
