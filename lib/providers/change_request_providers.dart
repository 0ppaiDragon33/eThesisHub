import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/change_request_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final changeRequestRepositoryProvider = Provider<ChangeRequestRepository>(
  (ref) => ChangeRequestRepository(ref.watch(firestoreProvider)),
);

/// A change of adviser is allowed while the thesis is at titleApproved and
/// chapter writing is still on — no defence of any kind has been scheduled
/// (a cancelled one does not count; spec §5).
bool canRequestAdviserChange(Thesis thesis, List<Defence> defences) =>
    thesis.status == ThesisStatus.titleApproved &&
    !defences.any((d) => d.status != DefenceStatus.cancelled);

/// A change of title is allowed while the thesis is at titleApproved and no
/// final defence has passed (spec §5).
bool canRequestTitleChange(Thesis thesis, List<Defence> defences) =>
    thesis.status == ThesisStatus.titleApproved &&
    !defences.any((d) =>
        d.type == DefenceType.final_ && d.panelVerdict == PassFail.pass);

final changeRequestsForThesisProvider =
    StreamProvider.family<List<ChangeRequest>, String>((ref, thesisId) {
  ref.watch(signedInUidProvider);
  return ref.watch(changeRequestRepositoryProvider).watchForThesis(thesisId);
});

/// Requests awaiting a role the signed-in faculty member holds. A collection-
/// group read over open requests, kept to the ones this uid must sign. The
/// awaited signer of an open request is: the new/former adviser at
/// pendingAdvisers, the thesis's adviser at pendingAdviser, and — surfaced to
/// coordinators/deans through their own providers below, not here.
final mySignoffRequestsProvider = StreamProvider<
    List<({String thesisId, ChangeRequest request, String role})>>((ref) {
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) return Stream.value(const []);
  final db = ref.watch(firestoreProvider);
  return db
      .collectionGroup('changeRequests')
      .where('stage', whereIn: [
        ChangeRequestStage.pendingAdvisers.value,
        ChangeRequestStage.pendingAdviser.value,
      ])
      .snapshots()
      .map((s) {
    final out = <({String thesisId, ChangeRequest request, String role})>[];
    for (final d in s.docs) {
      final thesisId = d.reference.parent.parent!.id;
      final r = ChangeRequest.fromMap(d.id, d.data());
      String? role;
      if (r.stage == ChangeRequestStage.pendingAdvisers) {
        if (r.newAdviserUid == uid &&
            r.signoffs['newAdviser']?.status == SignoffStatus.pending) {
          role = 'newAdviser';
        } else if (r.formerAdviserUid == uid &&
            r.signoffs['formerAdviser']?.status == SignoffStatus.pending) {
          role = 'formerAdviser';
        }
      } else if (r.stage == ChangeRequestStage.pendingAdviser &&
          r.signoffs['adviser']?.status == SignoffStatus.pending) {
        // The title request's signer is the thesis's current adviser. The
        // rules authorise on the thesis's adviserUid; the client cannot read
        // it from the request alone, so a pendingAdviser request is shown to
        // whoever the app knows advises it. The screen resolves the adviser
        // from the thesis before offering the action.
        role = 'adviser';
      }
      if (role != null) {
        out.add((thesisId: thesisId, request: r, role: role));
      }
    }
    return out;
  });
});

final coordinatorChangeRequestsProvider =
    StreamProvider<List<({String thesisId, ChangeRequest request})>>((ref) =>
        _requestsAtStage(ref, ChangeRequestStage.pendingCoordinator));

final deanChangeRequestsProvider =
    StreamProvider<List<({String thesisId, ChangeRequest request})>>((ref) =>
        _requestsAtStage(ref, ChangeRequestStage.pendingDean));

Stream<List<({String thesisId, ChangeRequest request})>> _requestsAtStage(
    Ref ref, ChangeRequestStage stage) {
  ref.watch(signedInUidProvider);
  final db = ref.watch(firestoreProvider);
  return db
      .collectionGroup('changeRequests')
      .where('stage', isEqualTo: stage.value)
      .snapshots()
      .map((s) => [
            for (final d in s.docs)
              (
                thesisId: d.reference.parent.parent!.id,
                request: ChangeRequest.fromMap(d.id, d.data()),
              ),
          ]);
}
