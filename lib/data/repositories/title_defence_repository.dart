import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
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
}
