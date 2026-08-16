import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Total nomination documents a submission may create: 1 adviser + the
/// chosen panelists + one seat per ex-officio member (the dean and every
/// research coordinator). The Firestore rules perform a `get()` per
/// nomination inside the batch; measured against the emulator, 19 nomination
/// creates commit and 20 are denied, and the documented Cloud limit is
/// stricter still. Capping the total at 9 here keeps every real submission
/// comfortably inside both.
const kMaxNominationDocs = 9;

/// Lets the thesis leader nominate an adviser and three or more panel
/// members from the faculty directory. The dean and every research
/// coordinator are recorded automatically as ex-officio panel members —
/// never chosen here, never asked to accept — but the project owner ruled
/// that they may still be nominated by name as an ordinary adviser or
/// panelist "for the sake of records," so they remain selectable in the
/// pickers alongside plain faculty.
///
/// Every nominee this screen submits is validated to still resolve against
/// the live directory, and the panel size is capped so the resulting batch
/// never approaches the security rules' per-batch `get()` ceiling.
///
/// Reached from the thesis status screen's "Nominate adviser and panel"
/// button, at `/thesis/nominate?id=<thesisId>`.
class NominateScreen extends ConsumerStatefulWidget {
  const NominateScreen({super.key, required this.thesisId});

  final String thesisId;

  @override
  ConsumerState<NominateScreen> createState() => _NominateScreenState();
}

class _NominateScreenState extends ConsumerState<NominateScreen> {
  String? _adviserUid;
  List<String?> _panelUids = [null, null, null];

  String? _error;
  bool _busy = false;
  bool _submitted = false;
  List<FacultyDirectoryEntry> _exOfficio = const [];

  @override
  void initState() {
    super.initState();
    _loadExOfficio();
  }

  Future<void> _loadExOfficio() async {
    final list =
        await ref.read(facultyDirectoryRepositoryProvider).fetchExOfficio();
    if (!mounted) return;
    setState(() {
      _exOfficio = list;
      final max = _maxPanelists;
      if (_panelUids.length > max) {
        _panelUids = _panelUids.sublist(0, max < 0 ? 0 : max);
      }
    });
  }

  /// `kMaxNominationDocs` minus 1 seat for the adviser minus one seat per
  /// ex-officio member, computed from the directory rather than hardcoded —
  /// the number of coordinators is not fixed.
  int get _maxPanelists {
    final cap = kMaxNominationDocs - 1 - _exOfficio.length;
    return cap < 0 ? 0 : cap;
  }

  FacultyDirectoryEntry? _byUid(List<FacultyDirectoryEntry> pool, String uid) {
    for (final f in pool) {
      if (f.uid == uid) return f;
    }
    return null;
  }

  Future<void> _submit(List<FacultyDirectoryEntry> faculty) async {
    if (_busy || _submitted) return;

    final chosenUids = _panelUids.whereType<String>().toSet();

    if (chosenUids.length < 3) {
      setState(() => _error = 'Choose at least three panel members.');
      return;
    }
    if (_adviserUid == null) {
      setState(() => _error = 'Choose a thesis adviser.');
      return;
    }
    if (chosenUids.length > _maxPanelists) {
      setState(() => _error =
          'Choose at most $_maxPanelists panel members. This thesis already '
          'reserves ${_exOfficio.length} ex-officio seat(s), and nominations '
          'per thesis are capped at $kMaxNominationDocs total.');
      return;
    }
    if (chosenUids.contains(_adviserUid)) {
      setState(() => _error = 'The adviser cannot also be a panel member.');
      return;
    }

    // The EFFECTIVE panel size — what survives `submitNominations`' collapse —
    // not the raw pick count.
    //
    // Coordinators and the dean stay in the picker on purpose (the owner
    // ruled they may be nominated by name "for the sake of records"), but
    // `submitNominations` resolves `adviser > ex officio > panelist`, so
    // picking one of them as a PANELIST collapses that pick into their single
    // automatic ex-officio seat (`exOfficio: true`) rather than adding a
    // panelist. Three picks including one office holder therefore commit as
    // two real panel members.
    //
    // That failure is invisible and terminal if it is not caught here. The
    // submission succeeds, every Conforme completes, the coordinator
    // recommends — and only then does `approve` fail, on the same `>= 3` floor
    // the Dean's own rule enforces (`firestore.rules`,
    // `panelistUids.size() >= 3`), on every attempt, forever: no rule lets the
    // leader back to `draft` to fix the roster. Raising it server-side cannot
    // help either — by then nobody can act. This screen, before submit, is the
    // last point at which the user can still change their selection.
    final exOfficioUids = _exOfficio.map((e) => e.uid).toSet();
    final collided = chosenUids.intersection(exOfficioUids);
    if (chosenUids.length - collided.length < 3) {
      final names = _exOfficio
          .where((e) => collided.contains(e.uid))
          .map((e) => e.fullName)
          .join(', ');
      final effective = chosenUids.length - collided.length;
      setState(() => _error =
          'Choose at least three panel members who are not already on this '
          'panel ex officio. $names already ${collided.length == 1 ? 'has' : 'have'} '
          'an automatic ex-officio seat on every panel, so choosing '
          '${collided.length == 1 ? 'that person' : 'them'} as a panel member '
          'adds nobody new — that leaves only $effective. '
          'Please choose ${3 - effective} more.');
      return;
    }

    final adviser = _byUid(faculty, _adviserUid!);
    if (adviser == null) {
      setState(() => _error =
          'The selected adviser is no longer in the faculty directory. '
          'Please choose again.');
      return;
    }

    final panelists = <FacultyDirectoryEntry>[];
    for (final uid in chosenUids) {
      final entry = _byUid(faculty, uid);
      if (entry == null) {
        setState(() => _error =
            'One of the selected panel members is no longer in the faculty '
            'directory. Please choose again.');
        return;
      }
      panelists.add(entry);
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(thesisRepositoryProvider).submitNominations(
            thesisId: widget.thesisId,
            adviser: adviser,
            panelists: panelists,
            exOfficio: _exOfficio,
          );
      if (mounted) setState(() => _submitted = true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'permission-denied'
            ? 'You do not have permission to submit this nomination.'
            : 'Could not submit the nomination. Please try again.';
      });
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not submit the nomination. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  DropdownButtonFormField<String> _picker(
    String key,
    String label,
    String? value,
    List<FacultyDirectoryEntry> faculty,
    ValueChanged<String?> onChanged,
  ) {
    // `DropdownButtonFormField` asserts, on every rebuild, that its
    // `initialValue` matches exactly one item in `items` — not just at
    // construction. A previous pick can vanish from the live directory
    // stream between selection and submit (someone edited the faculty
    // directory), which would otherwise crash the whole screen before the
    // submit-time "no longer resolves" validation ever runs. Falling back
    // to displaying no selection here keeps the widget alive; `_adviserUid`
    // / `_panelUids` still remember the stale uid so submit can reject it
    // with a proper message instead of a build-time assertion failure.
    final displayValue = faculty.any((f) => f.uid == value) ? value : null;
    return DropdownButtonFormField<String>(
      key: Key(key),
      initialValue: displayValue,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final f in faculty)
          DropdownMenuItem(
            value: f.uid,
            child: Text('${f.fullName} — ${f.subtitle}',
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read lazily inside the submit handler: watching in build
    // guarantees a settled value is already available by the time the user
    // can tap submit, so the handler never races the auth stream's first
    // event (see create_thesis_screen.dart for the bug this avoids).
    final leaderUid = ref.watch(authStateProvider).valueOrNull?.uid;
    final directoryAsync = ref.watch(allDirectoryProvider);
    final thesisAsync = ref.watch(myThesisProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nominate adviser and panel')),
      body: directoryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not load the faculty directory.')),
        data: (directory) {
          // A student can never be nominated, and the leader cannot nominate
          // themselves. The directory is not expected to contain students —
          // `FacultyDirectoryRepository.upsertOwnEntry` never writes one —
          // but both exclusions are enforced here too, defensively, rather
          // than trusted from upstream data shape.
          final faculty = directory
              .where((f) => f.role != 'student')
              .where((f) => leaderUid == null || f.uid != leaderUid)
              .toList();

          final thesis = thesisAsync.valueOrNull;
          final stillDraft = thesis != null && thesis.status == ThesisStatus.draft;

          if (thesisAsync.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!stillDraft) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nominations can only be submitted while this thesis is '
                  'still a draft. This thesis has already moved past that '
                  'stage.',
                  key: const Key('notDraft'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final atCap = _panelUids.length >= _maxPanelists;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _picker('adviser', 'Thesis Adviser', _adviserUid, faculty,
                        (v) => setState(() => _adviserUid = v)),
                    const SizedBox(height: 20),
                    Text('Panel members (minimum 3, at most $_maxPanelists)'),
                    for (var i = 0; i < _panelUids.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _picker('panel$i', 'Panel member ${i + 1}',
                            _panelUids[i], faculty,
                            (v) => setState(() => _panelUids[i] = v)),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const Key('addPanelist'),
                        onPressed: atCap
                            ? null
                            : () => setState(() => _panelUids.add(null)),
                        child: const Text('+ Add panel member'),
                      ),
                    ),
                    if (atCap)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Panel limited to $_maxPanelists member(s): this '
                          'thesis reserves ${_exOfficio.length} ex-officio '
                          'seat(s), and nominations per thesis are capped at '
                          '$kMaxNominationDocs total.',
                          key: const Key('panelCapReason'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                                'Also on your panel — added automatically'),
                            const SizedBox(height: 6),
                            for (final e in _exOfficio)
                              Text('${e.fullName} — ${e.role}'),
                            const SizedBox(height: 6),
                            Text(
                              'They sit on every panel by role, so there is '
                              'nothing to choose and nothing for them to '
                              'accept.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_submitted)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Nomination submitted.',
                          key: Key('successMessage'),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_error!,
                            key: const Key('error'),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ),
                    FilledButton(
                      key: const Key('submitNomination'),
                      onPressed: (_busy || _submitted)
                          ? null
                          : () => _submit(faculty),
                      child: Text(_busy
                          ? 'Submitting…'
                          : (_submitted
                              ? 'Submitted'
                              : 'Submit nomination')),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
