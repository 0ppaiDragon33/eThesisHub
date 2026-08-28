import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
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
/// members from the faculty directory.
///
/// The dean and every research coordinator are recorded automatically as
/// ex-officio panel members — never chosen here, never asked to accept. They
/// are therefore absent from the panel-member pickers: choosing one there
/// adds nobody, because `submitNominations` resolves the pick into the seat
/// they already hold, and a panel of three would commit as two.
///
/// They do remain in the ADVISER picker. A coordinator or the dean can
/// genuinely advise a thesis, and that is an ordinary position — it carries
/// `exOfficio: false`, it needs their Conforme, and it prints on Form 1 as
/// Thesis Adviser.
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

  /// The exception `_error` was translated from, kept for the code
  /// underneath the sentence — see the field on `ErrorState`, whose
  /// reasoning this mirrors: there are no server-side logs on the Spark
  /// plan, so if the friendly copy is ever wrong the code is the only way
  /// to tell.
  Object? _errorCause;
  bool _busy = false;

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
    if (_busy) return;

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
      _errorCause = null;
    });

    try {
      await ref.read(thesisRepositoryProvider).submitNominations(
            thesisId: widget.thesisId,
            adviser: adviser,
            panelists: panelists,
            exOfficio: _exOfficio,
          );
      // Straight to the status screen, which is where the leader watches
      // each nominee's Conforme arrive.
      //
      // Staying put was actively misleading: submitting moves the thesis out
      // of `draft`, this screen watches that status, and so the form was
      // replaced by "Nominations can only be submitted while this thesis is
      // still a draft" — which reads as a refusal of the thing that had just
      // succeeded. Navigating also makes a second submission unreachable,
      // which no flag on this screen can do as reliably.
      if (mounted) context.go('/thesis');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCause = e;
        _error = e.code == 'permission-denied'
            ? _permissionDeniedMessage(adviser, panelists)
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

  /// Turns a bare `permission-denied` on submit into a sentence naming who
  /// and what, per spec §4.2.1.
  ///
  /// A faculty member invited and designated but who has never signed in
  /// has no `facultyDirectory` entry yet. Their first sign-in creates one
  /// through `upsertOwnEntry`, which the rules forbid from writing the
  /// designation fields at all — so that entry reads as nominable for both
  /// positions (a missing key defaults to `true`, same as
  /// [FacultyDirectoryEntry]'s constructor) while `users/{uid}`, which the
  /// student cannot read, may say otherwise. The picker offers that person
  /// for a position `firestore.rules` then refuses. Nothing is corrupted
  /// and nothing is exposed, but the student picked a name off a list this
  /// screen showed them, so the refusal must say so in plain language —
  /// never leave them staring at a bare Firestore code and guessing at a
  /// network problem that was never the cause (the same lesson a
  /// storage-upload investigation taught this project once already).
  ///
  /// A batched write does not report which document a security rule
  /// refused, so every non-ex-officio nominee in this submission is a
  /// candidate. This screen's own floor of at least three real panel
  /// members means a first submission almost always names several —
  /// the adviser (unless they are an ex-officio office holder) plus
  /// every panelist, since a panel slot never offers one of those in
  /// the first place. All of them are named together, never guessed at,
  /// rather than picking one arbitrarily and risking exactly the kind of
  /// confidently-wrong copy this method exists to avoid. The
  /// single-sentence form is kept as the general case — not hardcoded to
  /// "always plural" — so a submission that genuinely has only one
  /// candidate still reads naturally, matching spec §4.2.1's example.
  String _permissionDeniedMessage(
    FacultyDirectoryEntry adviser,
    List<FacultyDirectoryEntry> panelists,
  ) {
    final exOfficioUids = _exOfficio.map((e) => e.uid).toSet();
    final candidates = <(String name, String position)>[
      if (!exOfficioUids.contains(adviser.uid))
        (adviser.fullName, 'adviser'),
      for (final p in panelists)
        if (!exOfficioUids.contains(p.uid)) (p.fullName, 'panelist'),
    ];

    if (candidates.length == 1) {
      final (name, position) = candidates.first;
      final article = position == 'adviser' ? 'an adviser' : 'a panelist';
      return '$name is not available as $article this semester.';
    }

    final named =
        candidates.map((c) => '${c.$1} (${c.$2})').join(', ');
    return 'One of your nominees is not available for the position you '
        'chose this semester: $named. Please choose someone else, or '
        'contact your coordinator.';
  }

  /// One line in a picker: the name, then whatever actually distinguishes
  /// this person from a namesake.
  ///
  /// The separator is only drawn when there is something after it. Nothing in
  /// the app fills `college` or `specialization` — they are set by hand in
  /// the Firebase Console or not at all — so for most entries [subtitle] is
  /// empty, and a hardcoded ' — ' rendered every option as "Karu Sama — "
  /// with a dangling dash.
  ///
  /// Coordinators and the dean are named as such. They stay in the pickers
  /// deliberately (the owner ruled they may be nominated by name "for the
  /// sake of records"), but they also hold an automatic ex-officio seat, so
  /// choosing one as a PANEL MEMBER adds nobody new and is refused at submit.
  /// Seeing "— coordinator" next to the name is what makes that legible
  /// before the refusal rather than after it.
  String _optionLabel(FacultyDirectoryEntry f) {
    final detail = [
      if (f.role == 'coordinator' || f.role == 'dean') f.role,
      if (f.subtitle.isNotEmpty) f.subtitle,
    ].join(' · ');
    return detail.isEmpty ? f.fullName : '${f.fullName} — $detail';
  }

  /// Everyone already chosen in another slot, so no picker offers them twice.
  ///
  /// One person can only hold one position on a thesis — the nomination
  /// documents are keyed by uid, so a second pick of the same person is not a
  /// second seat, it silently overwrites the first. Left unfiltered, the
  /// screen invited exactly that: the same name could fill the adviser slot
  /// and every panel slot at once, and the failure only surfaced at submit,
  /// as "Choose at least three panel members" while three dropdowns visibly
  /// held names (`chosenUids` is a Set, so the duplicates collapsed).
  ///
  /// [own] is the slot's own current value, which must stay in its own list —
  /// `DropdownButtonFormField` asserts its value matches exactly one item.
  Set<String> _takenExcept(String? own) {
    final taken = <String>{
      ?_adviserUid,
      for (final u in _panelUids) ?u,
    };
    if (own != null) taken.remove(own);
    return taken;
  }

  /// The adviser picker offers everyone designated for that position; a
  /// panel picker hides the ex-officio office holders and offers everyone
  /// else designated as a panelist.
  ///
  /// A Research Coordinator or the Dean genuinely can advise a thesis, and
  /// that is a real position: it carries `exOfficio: false`, it needs their
  /// Conforme, and it prints on Form 1 as Thesis Adviser. So the adviser slot
  /// must keep offering them.
  ///
  /// A panel slot must not offer an ex-officio office holder. They already
  /// sit on every panel by office — the "Also on your panel" card below
  /// lists them — so choosing one as a panel member adds nobody:
  /// `submitNominations` resolves that pick into their single automatic
  /// seat. Offering the choice at all only led to a submit-time refusal for
  /// something the screen could have ruled out. Every OTHER ex-officio
  /// entry stays exempt from the designation filter below too (spec D32):
  /// that seat is conferred by office, not by a coordinator's checkbox, and
  /// must never be blocked by a missed designation.
  ///
  /// Everyone else is filtered on [FacultyDirectoryEntry.nominableAsAdviser]
  /// / `.nominableAsPanelist`, set by a coordinator on the Users screen. A
  /// missing key on either field reads as `true` — every account predates
  /// these fields, and "absent means not nominable" would empty the picker
  /// of the entire existing faculty the moment this deployed.
  ///
  /// This is a UX guard, not the authorization boundary: `firestore.rules`
  /// is what actually refuses a nomination for a position its subject is
  /// not designated for, on the Spark plan where rules are the only
  /// enforcement point available. This filter only keeps the ordinary path
  /// from ever reaching that refusal; [_permissionDeniedMessage] is what
  /// handles the case where the two can still disagree (spec §4.2.1).
  ///
  /// The effective-panel-size check in [_submit] and the matching invariant
  /// in `submitNominations` both stay. This filter makes that state
  /// unreachable through the UI; it does not make it unreachable, and the
  /// repository is the layer that has to hold the line.
  List<FacultyDirectoryEntry> _offerableFor(
    bool isAdviserSlot,
    List<FacultyDirectoryEntry> faculty,
  ) {
    final exOfficioUids = _exOfficio.map((e) => e.uid).toSet();
    if (isAdviserSlot) {
      return faculty
          .where((f) => exOfficioUids.contains(f.uid) || f.nominableAsAdviser)
          .toList();
    }
    return faculty
        .where((f) => !exOfficioUids.contains(f.uid))
        .where((f) => f.nominableAsPanelist)
        .toList();
  }

  DropdownButtonFormField<String> _picker(
    String key,
    String label,
    String? value,
    List<FacultyDirectoryEntry> faculty,
    ValueChanged<String?> onChanged, {
    bool isAdviserSlot = false,
  }) {
    // `DropdownButtonFormField` asserts, on every rebuild, that its
    // `initialValue` matches exactly one item in `items` — not just at
    // construction. A previous pick can vanish from the live directory
    // stream between selection and submit (someone edited the faculty
    // directory), which would otherwise crash the whole screen before the
    // submit-time "no longer resolves" validation ever runs. Falling back
    // to displaying no selection here keeps the widget alive; `_adviserUid`
    // / `_panelUids` still remember the stale uid so submit can reject it
    // with a proper message instead of a build-time assertion failure.
    final offerable = _offerableFor(isAdviserSlot, faculty);
    final displayValue = offerable.any((f) => f.uid == value) ? value : null;
    final taken = _takenExcept(value);
    return DropdownButtonFormField<String>(
      key: Key(key),
      initialValue: displayValue,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final f in offerable)
          if (!taken.contains(f.uid))
            DropdownMenuItem(
              value: f.uid,
              child: Text(_optionLabel(f), overflow: TextOverflow.ellipsis),
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
    // The thesis this screen was actually given, not "the signed-in
    // leader's thesis". `myThesisProvider` resolves to `data(null)` while
    // auth is still settling — it reads `authStateProvider.value?.uid` and
    // returns `Stream.value(null)` when that is null — so watching it here
    // made `stillDraft` false on arrival and showed the "only while this
    // thesis is still a draft" refusal instead of the form. A refresh
    // appeared to fix it only because auth was warm the second time.
    final thesisAsync = ref.watch(thesisByIdProvider(widget.thesisId));

    // No Scaffold and no AppBar: the app shell owns both for every
    // signed-in route now.
    return directoryAsync.when(
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

        // Three distinct outcomes, kept apart. Collapsing them is what
        // produced the bug above: "still loading" was reported to the
        // user as "this thesis has moved past draft".
        if (thesisAsync.isLoading) {
          return const LoadingState(label: 'Loading your thesis…');
        }
        if (thesisAsync.hasError) {
          return PageShell(children: [
            ErrorState(
              error: thesisAsync.error,
              message: 'Could not load this thesis.',
            ),
          ]);
        }

        final thesis = thesisAsync.valueOrNull;
        if (thesis == null) {
          return const PageShell(children: [
            EmptyState(
              icon: Icons.search_off,
              title: 'Thesis not found',
              message: 'This thesis no longer exists, or it belongs to '
                  'another group.',
            ),
          ]);
        }

        final stillDraft = thesis.status == ThesisStatus.draft;
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
                      (v) => setState(() => _adviserUid = v),
                      isAdviserSlot: true),
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
                            'accept. That is why they are not listed as '
                            'panel members above — though one of them may '
                            'still be chosen as your thesis adviser, which '
                            'they would be asked to accept.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_error!,
                              key: const Key('error'),
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                          // The code underneath the sentence, same pattern
                          // as `ErrorState`: there are no server-side logs
                          // on the Spark plan, so if the friendly copy is
                          // ever wrong about the cause, the code is the
                          // only way left to tell.
                          if (_errorCause is FirebaseException)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '[${(_errorCause as FirebaseException).code}]',
                                key: const Key('errorCode'),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                        color:
                                            Theme.of(context).colorScheme.error),
                              ),
                            ),
                        ],
                      ),
                    ),
                  FilledButton(
                    key: const Key('submitNomination'),
                    onPressed: _busy ? null : () => _submit(faculty),
                    child: Text(
                        _busy ? 'Submitting…' : 'Submit nomination'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
