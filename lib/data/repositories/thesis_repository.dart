import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

class ThesisRepository {
  ThesisRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _theses =>
      _db.collection('theses');

  CollectionReference<Map<String, dynamic>> _nominations(String thesisId) =>
      _theses.doc(thesisId).collection('nominations');

  static DateTime? _date(Object? v) =>
      v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

  Thesis _toThesis(String id, Map<String, dynamic> data) {
    final raw = Map<String, dynamic>.from(data);
    raw['createdAt'] = _date(raw['createdAt']) ?? DateTime.now().toUtc();
    raw['coordinatorRecommendedAt'] = _date(raw['coordinatorRecommendedAt']);
    raw['deanApprovedAt'] = _date(raw['deanApprovedAt']);
    return Thesis.fromMap(id, raw);
  }

  Nomination _toNomination(String uid, Map<String, dynamic> data) {
    final raw = Map<String, dynamic>.from(data);
    raw['respondedAt'] = _date(raw['respondedAt']);
    return Nomination.fromMap(uid, raw);
  }

  Future<String> createThesis({
    required String leaderUid,
    required String workingTitle,
    required List<String> memberNames,
    required String college,
    required String program,
    required String semester,
    required String academicYear,
  }) async {
    final doc = _theses.doc();
    await doc.set({
      'leaderUid': leaderUid,
      'workingTitle': workingTitle.trim(),
      'memberNames': memberNames,
      'college': college,
      'program': program,
      'semester': semester,
      'academicYear': academicYear,
      'status': ThesisStatus.draft.value,
      'adviserUid': null,
      'panelistUids': <String>[],
      'coordinatorRecommendedAt': null,
      'coordinatorRecommendedBy': null,
      'deanApprovedAt': null,
      'deanApprovedBy': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Stream<Thesis?> watchThesis(String thesisId) {
    return _theses.doc(thesisId).snapshots().map(
        (s) => s.exists ? _toThesis(s.id, s.data()!) : null);
  }

  Stream<Thesis?> watchThesisForLeader(String leaderUid) {
    return _theses
        .where('leaderUid', isEqualTo: leaderUid)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isEmpty
            ? null
            : _toThesis(s.docs.first.id, s.docs.first.data()));
  }

  Stream<List<Nomination>> watchNominations(String thesisId) {
    return _nominations(thesisId).snapshots().map((s) =>
        s.docs.map((d) => _toNomination(d.id, d.data())).toList());
  }

  /// Writes every nomination and advances the thesis in one batch, so a
  /// half-submitted nomination cannot exist.
  ///
  /// Ex officio entries are written by the leader's client too, but the rules
  /// pin their `exOfficio` and `conformeStatus` values so a student cannot
  /// forge an acceptance.
  Future<void> submitNominations({
    required String thesisId,
    required FacultyDirectoryEntry adviser,
    required List<FacultyDirectoryEntry> panelists,
    required List<FacultyDirectoryEntry> exOfficio,
  }) async {
    if (panelists.length < 3) {
      throw ArgumentError('At least three panel members are required.');
    }

    final batch = _db.batch();
    final noms = _nominations(thesisId);

    batch.set(noms.doc(adviser.uid), {
      'nomineeName': adviser.fullName,
      'position': NominationPosition.adviser.value,
      'exOfficio': false,
      'conformeStatus': ConformeStatus.pending.value,
      'respondedAt': null,
      'declineReason': null,
    });

    for (final p in panelists) {
      batch.set(noms.doc(p.uid), {
        'nomineeName': p.fullName,
        'position': NominationPosition.panelist.value,
        'exOfficio': false,
        'conformeStatus': ConformeStatus.pending.value,
        'respondedAt': null,
        'declineReason': null,
      });
    }

    for (final e in exOfficio) {
      batch.set(noms.doc(e.uid), {
        'nomineeName': e.fullName,
        'position': e.role == 'dean'
            ? NominationPosition.dean.value
            : NominationPosition.coordinator.value,
        'exOfficio': true,
        'conformeStatus': ConformeStatus.exOfficio.value,
        'respondedAt': null,
        'declineReason': null,
      });
    }

    batch.update(_theses.doc(thesisId), {
      'status': ThesisStatus.nominationPendingConforme.value,
    });

    await batch.commit();
  }

  Stream<List<Thesis>> watchByStatus(ThesisStatus status) {
    return _theses
        .where('status', isEqualTo: status.value)
        .snapshots()
        .map((s) => s.docs.map((d) => _toThesis(d.id, d.data())).toList());
  }
}
