import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

/// A change of adviser is allowed while the thesis is at titleApproved and
/// chapter writing is still on, no defence of any kind has been scheduled
/// (a cancelled one does not count; ).
///
/// Asked twice: when the group files the request (to offer the button), and
/// again when the Coordinator recommends and the Dean approves it, because
/// the answer can change in between: a defence scheduled while the request
/// waited. Firestore rules cannot ask it (they cannot query a thesis's
/// defences), so the repository does, at each sign-off that can read them.
bool canRequestAdviserChange(Thesis thesis, List<Defence> defences) =>
    thesis.status == ThesisStatus.titleApproved &&
    !defences.any((d) => d.status != DefenceStatus.cancelled);

/// A change of title is allowed while the thesis is at titleApproved and no
/// final defence has passed. Asked again at sign-off, as above.
bool canRequestTitleChange(Thesis thesis, List<Defence> defences) =>
    thesis.status == ThesisStatus.titleApproved &&
    !defences.any((d) =>
        d.type == DefenceType.final_ && d.panelVerdict == PassFail.pass);
