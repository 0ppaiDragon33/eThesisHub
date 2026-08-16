import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/composing_indicator.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/title_comment.dart';
import 'package:ethesishub/data/services/audit_service.dart';

/// One candidate as the screen has it: text plus an already-uploaded file.
/// The upload happens before this, so a failed Firestore write leaves an
/// orphaned object in the bucket rather than a document pointing at nothing.
typedef CandidateTitleDraft = ({
  String titleText,
  String justificationPath,
  String justificationUrl,
});

/// Every read and write for the title defence.
class TitleDefenceRepository {
  TitleDefenceRepository(FirebaseFirestore db, {AuditService? audit})
      : _db = db,
        _audit = audit ?? AuditService(db);

  final FirebaseFirestore _db;

  // Unused in this task — the Dean's title decision methods (added in a
  // later task on this plan) log to the audit trail through this.
  // ignore: unused_field
  final AuditService _audit;

  /// Three is the floor; ten is the ceiling and it is a rules constraint, not
  /// a taste one. Each candidate's create rule costs a `get()` on the thesis,
  /// and M1a measured that a batch of 20 is denied while 19 commits.
  static const int minCandidates = 3;
  static const int maxCandidates = 10;

  DocumentReference<Map<String, dynamic>> _thesis(String id) =>
      _db.collection('theses').doc(id);

  CollectionReference<Map<String, dynamic>> _candidates(String thesisId) =>
      _thesis(thesisId).collection('candidateTitles');

  CandidateTitle _toCandidate(String id, Map<String, dynamic> raw) {
    return CandidateTitle.fromMap(id, {
      ...raw,
      'submittedAt': (raw['submittedAt'] as Timestamp?)?.toDate(),
    });
  }

  Stream<List<CandidateTitle>> watchCandidateTitles(String thesisId) {
    return _candidates(thesisId).snapshots().map(
        (s) => s.docs.map((d) => _toCandidate(d.id, d.data())).toList());
  }

  /// Writes the candidates and moves the thesis to `titlePendingDefence`, in
  /// one batch.
  ///
  /// Batched writes are each evaluated against the state BEFORE the batch, so
  /// the candidate creates are judged against the thesis's current status —
  /// which is exactly why they are permitted while it is still
  /// `nominationApproved` or `titleRejected`. M1a verified this behaviour
  /// against the emulator rather than assuming it.
  Future<void> submitCandidateTitles({
    required String thesisId,
    required List<CandidateTitleDraft> titles,
    required String presentationPath,
    required String presentationUrl,
  }) async {
    if (titles.length < minCandidates) {
      throw ArgumentError(
          'At least $minCandidates candidate titles are required.');
    }
    if (titles.length > maxCandidates) {
      throw ArgumentError(
          'At most $maxCandidates candidate titles may be submitted at once.');
    }

    final snap = await _thesis(thesisId).get();
    if (!snap.exists) throw StateError('That thesis no longer exists.');
    final data = snap.data()!;
    final status = ThesisStatus.fromString(data['status'] as String?);
    if (status != ThesisStatus.nominationApproved &&
        status != ThesisStatus.titleRejected) {
      throw StateError(
          'Candidate titles can only be submitted once the nomination is '
          'approved, or after a set has been rejected.');
    }

    final nextRound = ((data['titleRound'] as num?)?.toInt() ?? 0) + 1;

    final batch = _db.batch();
    for (final t in titles) {
      batch.set(_candidates(thesisId).doc(), {
        'titleText': t.titleText.trim(),
        'justificationPath': t.justificationPath,
        'justificationUrl': t.justificationUrl,
        'round': nextRound,
        'submittedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.update(_thesis(thesisId), {
      'status': ThesisStatus.titlePendingDefence.value,
      'titleRound': nextRound,
      'titlesSubmittedAt': FieldValue.serverTimestamp(),
      'presentationPath': presentationPath,
      'presentationUrl': presentationUrl,
    });
    await batch.commit();
  }

  CollectionReference<Map<String, dynamic>> _comments(String thesisId) =>
      _thesis(thesisId).collection('titleComments');

  TitleComment _toComment(String id, Map<String, dynamic> raw) {
    return TitleComment.fromMap(id, {
      ...raw,
      'createdAt': (raw['createdAt'] as Timestamp?)?.toDate(),
    });
  }

  /// Every comment on the thesis, oldest first.
  ///
  /// One listener for the whole defence rather than one per candidate:
  /// comments carry `candidateTitleId` and the screen groups them. Nesting
  /// them under each candidate would have meant N listeners or a
  /// collection-group query, and the latter needs an index Firestore never
  /// creates on its own.
  Stream<List<TitleComment>> watchComments(String thesisId) {
    return _comments(thesisId)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map((d) => _toComment(d.id, d.data())).toList());
  }

  /// Records a remark against one candidate title.
  ///
  /// Append-only: there is deliberately no `editComment` and no
  /// `deleteComment` on this class. A comment is part of the record the
  /// student eventually reads, and once the panel has seen it, rewriting or
  /// removing it would rewrite history rather than correct it. That
  /// property is enforced where it can actually be enforced — the security
  /// rules — and by review of this class; it is not something a unit test
  /// against this API can prove, since the absence of a method cannot fail
  /// a test that never calls it.
  Future<void> addComment({
    required String thesisId,
    required String candidateTitleId,
    required String authorUid,
    required String authorName,
    required String authorRole,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError('A comment cannot be empty.');

    await _comments(thesisId).add({
      'candidateTitleId': candidateTitleId,
      'authorUid': authorUid,
      'authorName': authorName,
      'authorRole': authorRole,
      'body': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  CollectionReference<Map<String, dynamic>> _composing(String thesisId) =>
      _thesis(thesisId).collection('titleComposing');

  /// Live "is writing" markers, stale ones included — the reader expires
  /// them via [ComposingIndicator.isStaleAt], because there are no Cloud
  /// Functions to sweep a laptop that was closed mid-comment.
  Stream<List<ComposingIndicator>> watchComposing(String thesisId) {
    return _composing(thesisId).snapshots().map((s) => s.docs
        .map((d) => ComposingIndicator.fromMap(d.id, {
              ...d.data(),
              'updatedAt': (d.data()['updatedAt'] as Timestamp?)?.toDate(),
            }))
        .toList());
  }

  /// Called on focus and then roughly every 5 seconds while a comment field
  /// is open. Deliberately not per keystroke: Spark allows 20,000 writes a
  /// day, and keystroke-level writes would exhaust that in a few defences.
  ///
  /// Keyed by uid, so one person composing cannot produce two indicators.
  Future<void> markComposing({
    required String thesisId,
    required String uid,
    required String name,
    required String role,
    required String candidateTitleId,
  }) {
    return _composing(thesisId).doc(uid).set({
      'name': name,
      'role': role,
      'candidateTitleId': candidateTitleId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// On submit or on blur. A double clear is normal and must not throw.
  Future<void> clearComposing({
    required String thesisId,
    required String uid,
  }) {
    return _composing(thesisId).doc(uid).delete();
  }
}
