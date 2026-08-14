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

  Map<String, dynamic> _nominationMap({
    required String name,
    required NominationPosition position,
    required bool exOfficio,
    required ConformeStatus conformeStatus,
  }) => {
        'nomineeName': name,
        'position': position.value,
        'exOfficio': exOfficio,
        'conformeStatus': conformeStatus.value,
        'respondedAt': null,
        'declineReason': null,
      };

  /// Writes every nomination and advances the thesis in one batch, so a
  /// half-submitted nomination cannot exist.
  ///
  /// A nominee's uid can collide across roles — the Dean or a Research
  /// Coordinator may also be nominated by name as adviser or panelist "for
  /// the sake of records". Precedence is resolved explicitly here, by
  /// building one map of uid -> nomination doc before writing anything, so
  /// the result never depends on write/batch ordering:
  ///
  ///   adviser  >  ex officio  >  panelist
  ///
  /// - A panelist nomination that collides with an ex-officio seat collapses
  ///   into that single ex-officio entry (`exOfficio: true`, no Conforme
  ///   asked) — sitting on the panel already follows from holding the
  ///   office.
  /// - An adviser nomination always wins, even over an ex-officio seat:
  ///   supervising a specific thesis is a personal commitment distinct from
  ///   an office-holder's panel seat, and Form 1 prints them on the Conforme
  ///   line as Thesis Adviser, so they must accept (`exOfficio: false`,
  ///   `conformeStatus: pending`).
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

    // Lowest precedence first, each later pass deliberately overwriting the
    // uid's entry so the final map reflects `adviser > ex officio > panelist`
    // regardless of what order the input lists happen to be in.
    final writes = <String, Map<String, dynamic>>{};

    for (final p in panelists) {
      writes[p.uid] = _nominationMap(
        name: p.fullName,
        position: NominationPosition.panelist,
        exOfficio: false,
        conformeStatus: ConformeStatus.pending,
      );
    }

    for (final e in exOfficio) {
      writes[e.uid] = _nominationMap(
        name: e.fullName,
        position: e.role == 'dean'
            ? NominationPosition.dean
            : NominationPosition.coordinator,
        exOfficio: true,
        conformeStatus: ConformeStatus.exOfficio,
      );
    }

    writes[adviser.uid] = _nominationMap(
      name: adviser.fullName,
      position: NominationPosition.adviser,
      exOfficio: false,
      conformeStatus: ConformeStatus.pending,
    );

    for (final entry in writes.entries) {
      batch.set(noms.doc(entry.key), entry.value);
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
