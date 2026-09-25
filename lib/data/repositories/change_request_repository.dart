import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

/// Reads and writes the change-of-adviser / change-of-title requests under a
/// thesis (spec 2026-09-25). The stage machine and the Dean's apply-the-
/// change step live here; the security rules mirror every transition.
class ChangeRequestRepository {
  ChangeRequestRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _requests(String thesisId) =>
      _db.collection('theses').doc(thesisId).collection('changeRequests');

  DocumentReference<Map<String, dynamic>> _request(
    String thesisId,
    ChangeRequestType type,
  ) => _requests(thesisId).doc(type.id);

  ChangeRequest _toRequest(String id, Map<String, dynamic> raw) {
    Map<String, dynamic> withDates(Map<String, dynamic> m) => {
      ...m,
      'createdAt': (m['createdAt'] as Timestamp?)?.toDate(),
      'updatedAt': (m['updatedAt'] as Timestamp?)?.toDate(),
      'signoffs': {
        for (final e in ((m['signoffs'] as Map?) ?? const {}).entries)
          e.key: {
            ...(e.value as Map).cast<String, dynamic>(),
            'respondedAt': ((e.value as Map)['respondedAt'] as Timestamp?)
                ?.toDate(),
          },
      },
    };
    return ChangeRequest.fromMap(id, withDates(raw));
  }

  Stream<List<ChangeRequest>> watchForThesis(String thesisId) =>
      _requests(thesisId).snapshots().map(
        (s) => s.docs.map((d) => _toRequest(d.id, d.data())).toList(),
      );

  Map<String, dynamic> _freshSignoffs(List<String> roles) => {
    for (final r in roles)
      r: {
        'status': SignoffStatus.pending.value,
        'respondedAt': null,
        'reason': null,
      },
  };

  Future<void> submitAdviserChange({
    required Thesis thesis,
    required FacultyDirectoryEntry newAdviser,
    required String formerAdviserName,
    required String reasons,
  }) async {
    if (reasons.trim().isEmpty) throw ArgumentError('Give a reason.');
    await _request(thesis.id, ChangeRequestType.adviser).set({
      'type': ChangeRequestType.adviser.value,
      'stage': ChangeRequestStage.pendingAdvisers.value,
      'reasons': reasons.trim(),
      'leaderUid': thesis.leaderUid,
      'newAdviserUid': newAdviser.uid,
      'newAdviserName': newAdviser.fullName,
      'formerAdviserUid': thesis.adviserUid,
      'formerAdviserName': formerAdviserName,
      'signoffs': _freshSignoffs(signoffRolesFor(ChangeRequestType.adviser)),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> submitTitleChange({
    required Thesis thesis,
    required String newTitle,
    required String reasons,
  }) async {
    if (newTitle.trim().isEmpty) throw ArgumentError('Give a new title.');
    if (reasons.trim().isEmpty) throw ArgumentError('Give a reason.');
    await _request(thesis.id, ChangeRequestType.title).set({
      'type': ChangeRequestType.title.value,
      'stage': ChangeRequestStage.pendingAdviser.value,
      'reasons': reasons.trim(),
      'leaderUid': thesis.leaderUid,
      'newTitle': newTitle.trim(),
      'signoffs': _freshSignoffs(signoffRolesFor(ChangeRequestType.title)),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Records one role's accept or decline, advancing the stage when the step
  /// completes. A transaction so a concurrent sign-off cannot double-advance;
  /// the guard is RETURNED and thrown outside, never thrown inside the
  /// closure (Android MissingPluginException on cancel).
  Future<void> respond({
    required String thesisId,
    required ChangeRequestType type,
    required String role,
    required bool accept,
    String? reason,
  }) async {
    final ref = _request(thesisId, type);
    final failure = await _db.runTransaction<Object?>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return StateError('This request no longer exists.');
      final req = _toRequest(snap.id, snap.data()!);

      final expected = switch (role) {
        'newAdviser' || 'formerAdviser' => ChangeRequestStage.pendingAdvisers,
        'adviser' => ChangeRequestStage.pendingAdviser,
        'coordinator' => ChangeRequestStage.pendingCoordinator,
        'dean' => ChangeRequestStage.pendingDean,
        _ => null,
      };
      if (req.stage != expected) {
        return StateError('This request is no longer awaiting that step.');
      }
      if (req.signoffs[role]?.status != SignoffStatus.pending) {
        return StateError('You have already answered this request.');
      }

      final update = <String, Object?>{
        'signoffs.$role.status':
            (accept ? SignoffStatus.accepted : SignoffStatus.declined).value,
        'signoffs.$role.respondedAt': FieldValue.serverTimestamp(),
        'signoffs.$role.reason': accept ? null : reason,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!accept) {
        update['stage'] = ChangeRequestStage.returned.value;
      } else if (type == ChangeRequestType.adviser &&
          req.stage == ChangeRequestStage.pendingAdvisers) {
        // Advance only when this accept makes BOTH advisers accepted.
        final other = role == 'newAdviser' ? 'formerAdviser' : 'newAdviser';
        if (req.signoffs[other]?.status == SignoffStatus.accepted) {
          update['stage'] = ChangeRequestStage.pendingCoordinator.value;
        }
      } else {
        update['stage'] = nextStage(req.stage)!.value;
      }
      tx.update(ref, update);
      return null;
    });
    if (failure != null) throw failure;
  }

  /// The Dean's final step: the request goes `approved` and the thesis takes
  /// the change, in one batch, only while the thesis is still titleApproved.
  Future<void> approveAsDean({
    required String thesisId,
    required ChangeRequestType type,
  }) async {
    final reqRef = _request(thesisId, type);
    final thesisRef = _db.collection('theses').doc(thesisId);

    final reqSnap = await reqRef.get();
    if (!reqSnap.exists) throw StateError('This request no longer exists.');
    final req = _toRequest(reqSnap.id, reqSnap.data()!);
    if (req.stage != ChangeRequestStage.pendingDean) {
      throw StateError('This request is not awaiting the Dean.');
    }
    final thesisSnap = await thesisRef.get();
    final thesis = Thesis.fromMap(thesisSnap.id, thesisSnap.data()!);
    if (thesis.status != ThesisStatus.titleApproved) {
      throw StateError('This thesis can no longer take this change.');
    }

    final batch = _db.batch();
    batch.update(reqRef, {
      'signoffs.dean.status': SignoffStatus.accepted.value,
      'signoffs.dean.respondedAt': FieldValue.serverTimestamp(),
      'stage': ChangeRequestStage.approved.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(
      thesisRef,
      type == ChangeRequestType.adviser
          ? {'adviserUid': req.newAdviserUid}
          : {'workingTitle': req.newTitle},
    );
    await batch.commit();
  }
}
