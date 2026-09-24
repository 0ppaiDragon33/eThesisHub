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
    return _copies(uid).snapshots().map((s) => _newestFirst([
          for (final d in s.docs) FormCopy.fromMap(d.id, d.data()),
        ].where((c) => c.formId == formId)));
  }

  /// Every copy this person holds, of every form, newest first (My files).
  Stream<List<FormCopy>> watchAllCopies(String uid) {
    return _copies(uid).snapshots().map((s) => _newestFirst([
          for (final d in s.docs) FormCopy.fromMap(d.id, d.data()),
        ]));
  }

  // Not yet stamped by the server means written a moment ago: newest.
  static List<FormCopy> _newestFirst(Iterable<FormCopy> copies) {
    final list = copies.toList();
    list.sort((a, b) {
      final at = a.updatedAt;
      final bt = b.updatedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return -1;
      if (bt == null) return 1;
      return bt.compareTo(at);
    });
    return list;
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
  ///
  /// Uses a full-document write in a transaction rather than a field update,
  /// because fake_cloud_firestore 4.2.0 deep-merges map values on update(),
  /// while real Firestore replaces the field. A full set() ensures consistent
  /// replacement behavior under both libraries.
  Future<void> saveOverrides({
    required String uid,
    required String copyId,
    required Map<String, String> overrides,
  }) async {
    final ref = _copies(uid).doc(copyId);
    final failure = await _db.runTransaction<StateError?>((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) {
        return StateError('This copy no longer exists.');
      }
      final current = doc.data()!;
      tx.set(ref, {
        ...current,
        'overrides': overrides,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    });
    if (failure != null) throw failure;
  }

  Future<void> rename({
    required String uid,
    required String copyId,
    required String name,
  }) =>
      _copies(uid).doc(copyId).update({
        'name': _checkedName(name),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Puts the copy in a My files folder, or at the top level for null.
  /// Stamps `updatedAt`, as the rules require on every update.
  Future<void> moveToFolder({
    required String uid,
    required String copyId,
    String? folderId,
  }) =>
      _copies(uid).doc(copyId).update({
        'folderId': folderId,
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
