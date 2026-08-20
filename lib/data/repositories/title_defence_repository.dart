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

  /// Every candidate title on a thesis, in the order the group submitted
  /// them, oldest round first.
  ///
  /// Sorted here rather than with `orderBy('position')` for two reasons: a
  /// document written before positions existed carries no such field and an
  /// ordered query would drop it from the list entirely, and the set is
  /// capped at [maxCandidates], so ordering it in Dart costs nothing and
  /// needs no Firestore index. The id is the last tie-break, so the order is
  /// total and cannot flicker between snapshots.
  Stream<List<CandidateTitle>> watchCandidateTitles(String thesisId) {
    return _candidates(thesisId).snapshots().map((s) {
      final candidates =
          s.docs.map((d) => _toCandidate(d.id, d.data())).toList();
      candidates.sort((a, b) {
        final byRound = a.round.compareTo(b.round);
        if (byRound != 0) return byRound;
        final byPosition = a.position.compareTo(b.position);
        if (byPosition != 0) return byPosition;
        return a.id.compareTo(b.id);
      });
      return candidates;
    });
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
    for (var i = 0; i < titles.length; i++) {
      final t = titles[i];
      batch.set(_candidates(thesisId).doc(), {
        'titleText': t.titleText.trim(),
        'justificationPath': t.justificationPath,
        'justificationUrl': t.justificationUrl,
        'round': nextRound,
        // The order the group typed them in. Without it the panel sees the
        // set shuffled: ids are random and one batch shares one timestamp.
        'position': i,
        'submittedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.update(_thesis(thesisId), {
      'status': ThesisStatus.titlePendingDefence.value,
      'titleRound': nextRound,
      'titlesSubmittedAt': FieldValue.serverTimestamp(),
      'presentationPath': presentationPath,
      'presentationUrl': presentationUrl,
      // The previous round's decision is erased by the same write that opens
      // the new one. Leaving it behind kept `titleDecided()` true in
      // `firestore.rules` for the rest of the thesis's life, so from round 2
      // onward the leader could read the panel's remarks live during their
      // own defence. A no-op on a first submission, where the keys have
      // never existed.
      'titleDecidedAt': FieldValue.delete(),
      'titleDecidedBy': FieldValue.delete(),
      'titleRejectionRemark': FieldValue.delete(),
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

  /// The Dean records which candidate the panel approved.
  ///
  /// Guarded on the CURRENT persisted status, not on anything the caller
  /// supplies. M1a shipped a transition without that guard and a stale tab
  /// could walk an approved thesis backwards.
  Future<void> approveTitle({
    required String thesisId,
    required String candidateTitleId,
    required String deanUid,
  }) async {
    await _requirePendingDefence(thesisId);

    final candidate = await _candidates(thesisId).doc(candidateTitleId).get();
    if (!candidate.exists) {
      throw ArgumentError('That candidate title is not on this thesis.');
    }

    await _thesis(thesisId).update({
      'status': ThesisStatus.titleApproved.value,
      'approvedTitleId': candidateTitleId,
      'titleDecidedBy': deanUid,
      'titleDecidedAt': FieldValue.serverTimestamp(),
    });

    await _writeAuditLog(
      deanUid: deanUid,
      thesisId: thesisId,
      action: 'title.approved',
      metadata: {'approvedTitleId': candidateTitleId},
    );
  }

  /// The Dean rejects the whole set. The remark is required: the student must
  /// know what to fix, and the panel's comments may not say it plainly.
  Future<void> rejectTitles({
    required String thesisId,
    required String deanUid,
    required String remark,
  }) async {
    final text = remark.trim();
    if (text.isEmpty) {
      throw ArgumentError('Say why the set is being rejected.');
    }
    await _requirePendingDefence(thesisId);

    await _thesis(thesisId).update({
      'status': ThesisStatus.titleRejected.value,
      'titleRejectionRemark': text,
      'titleDecidedBy': deanUid,
      'titleDecidedAt': FieldValue.serverTimestamp(),
    });

    await _writeAuditLog(
      deanUid: deanUid,
      thesisId: thesisId,
      action: 'title.rejected',
      metadata: {'remark': text},
    );
  }

  Future<void> _requirePendingDefence(String thesisId) async {
    final snap = await _thesis(thesisId).get();
    if (!snap.exists) throw StateError('That thesis no longer exists.');
    final status = ThesisStatus.fromString(snap.data()!['status'] as String?);
    if (status != ThesisStatus.titlePendingDefence) {
      throw StateError('This title defence has already been decided.');
    }
  }

  /// Best-effort, and deliberately after the decision has committed. The
  /// decision is the point; the log must never be able to prevent one.
  Future<void> _writeAuditLog({
    required String deanUid,
    required String thesisId,
    required String action,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      await _audit.log(
        actorUid: deanUid,
        action: action,
        targetType: 'thesis',
        targetId: thesisId,
        metadata: metadata,
      );
    } catch (_) {
      // Swallowed on purpose. A thesis must not be left undecided because a
      // log write failed — the same posture the sign-in path takes.
    }
  }

  /// The id of every thesis this person holds a position on.
  ///
  /// A collection-group query on `nominations`, not a query on `theses`: the
  /// rules allow a faculty member to LIST theses only if they are the leader,
  /// a coordinator or the dean. They may however read their own nominations
  /// across every thesis, which is the same query
  /// `watchMyPendingNominations` uses — and it reuses that query's existing
  /// COLLECTION_GROUP index on `nomineeUid`, so no index change is needed.
  ///
  /// No `conformeStatus` filter: a coordinator and the dean sit on every
  /// panel ex officio and never accept, so filtering on acceptance would hide
  /// exactly the people who chair the defence.
  Stream<List<String>> watchMyThesisIds(String uid) {
    return _db
        .collectionGroup('nominations')
        .where('nomineeUid', isEqualTo: uid)
        .snapshots()
        .map((s) => s.docs
            .map((d) => d.reference.parent.parent!.id)
            .toSet()
            .toList());
  }
}
