# Defence Stages and Re-defence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One Defences page split by stage (Title defence | Pre-oral | Final defence | Re-defence), the adviser able to reach their advisee's title defence, and a re-defence after a failed pre-oral or final defence.

**Architecture:**
- A re-defence is an ordinary `defenses` document with the same `type` as the failed one, plus `redefenceOf: <failed id>`, stored at the id `<failed id>_redefence`. Firestore rules allow creating one only after a `fail` verdict, at most once.
- The Defences page reads its stage from `?stage=` and shows each stage through the existing list and calendar, filtered.
- The title stage lists, per role, the theses at title defence the reader can open.

**Tech Stack:**
- Flutter 3.44, Riverpod 2.6.1 (pinned), go_router 17.5.0 (pinned).
- Cloud Firestore with `firestore.rules`, tested on the emulator (`cd rules-test && npm test`).
- fake_cloud_firestore 4.2.0, which enforces no rules, for Dart tests.

**Spec:** `docs/superpowers/specs/2026-09-25-defence-stages-and-redefence-design.md`

## Global Constraints

- **Commit only the files your task names.** The working tree has unrelated uncommitted changes. Never stage these, and never edit the lib files among them:
  - `android/app/src/main/kotlin/com/example/ethesishub/MainActivity.kt`
  - `lib/app.dart`
  - `lib/core/theme/app_theme.dart`
  - `lib/core/widgets/app_shell.dart`
  - `lib/features/dashboard/progress_rail.dart`
  - `lib/features/defence/consolidated_defence_screen.dart`
  - `lib/features/forms/form_chrome.dart`
  - `lib/core/platform/native_back.dart`
  - `test/core/platform/`
  - the deleted `double_back_to_exit` files
  - `macos/…`
  - `android/build/`

  Never run `git add -A`, `git add .` or `git commit -a`. Stage by explicit path, and check `git status --short` before every commit.
- Stored strings are exact and never change once shipped: `redefenceOf`, the id suffix `_redefence`, and the query values `title`, `preOral`, `final`, `redefence`.
- One re-defence per failed defence. Re-defence applies to pre-oral and final only; a rejected title set keeps its existing resubmit flow.
- A missing or unknown `?stage=` shows **Title defence**.
- User-facing wording in this plan is final copy. Use it verbatim.
- Every commit message ends with: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Dart test command: `flutter test <path>`. Rules tests: `cd rules-test && npm test`. This needs the Firebase CLI and Java. If the emulator cannot start, say so in your report; do not skip silently.
- Run `dart format` only on files your task creates. On files it modifies, keep your edits in the file's existing style and do not reformat the rest.

## Rulings made while planning

- **Scheduling a re-defence gets its own screen,** `ScheduleRedefenceScreen`, reached at `/defence/schedule?redefenceOf=<id>`, rather than a mode inside `ScheduleDefenceScreen`. The two share a date picker (`pickDefenceDateTime`).
- **A stage's count is what still needs attention:**
  - Title: every title defence listed.
  - Pre-oral and final: defences that are scheduled or in progress.
  - Re-defence: open re-defences plus failed defences awaiting one.

  A plain total would count every past defence and grow forever.
- **A cancelled re-defence still uses up the one slot.** The rules would refuse a second document at the same id, so the app must not offer to schedule one.
- **Whether a re-defence exists is read from `myDefencesProvider`,** the reader's own defence list, never by fetching `defenses/<id>_redefence`. For a missing document the rules' `get` arm would deny, and the read would surface as an error.
- **`DefenceQueue` and `TitleDefencesScreen` are deleted.** The title stage renders `ThesisQueue` over `myTitleDefencesProvider` for every non-student role.
- **The page title becomes "Defences"** (was "Scheduled defences"), because title defences are not scheduled.
- **The manuscript and archive gates get no test of their own.** Spec §7 asks that a passed final re-defence pass them. Both gates (`manuscript_upload.dart`, `archive_providers.dart`) test only `type == final_ && panelVerdict == pass`, and a re-defence keeps its type. That is pinned by Task 2 (the re-defence copies `type`) and Task 1 (the progress rail, which keys on type the same way). A widget-level test of either gate would mostly exercise their unrelated setup.
- **Coordinator and Dean see the same list as before, rendered differently.** Spec §6.2 said "the existing `DefenceQueue`, unchanged". The rows are the same theses, now rendered by `ThesisQueue` (the widget `DefenceQueue` wrapped), with the button reading "Open title defence".

## Review Focus

1. **A cancelled re-defence.** The failed defence must not be offered for another re-defence, because the rules would refuse it. Pinned in Task 1.
2. **The thesis panel changed after the Fail.** The re-defence's copied panel no longer matches, so the rules must refuse it, and the screen must show the permission message rather than succeed silently. The refusal is pinned in Task 3. Task 8 words the message for this case; fake_cloud_firestore cannot produce the refusal, so that message has no Dart test.
3. **A garbage or differently-cased `?stage=`.** `?stage=FINAL` or `?stage=x` must show Title without crashing. Pinned in Task 7.
4. **A faculty member who both advises and sits on a thesis's panel.** It must be listed once, not twice. Pinned in Task 4.
5. **The stage switch with counts on a 360-px-wide phone.** It must not overflow. Pinned in Task 6.

---

### Task 1: Re-defence on the Defence model

**Files:**
- Modify: `lib/data/models/defence.dart`
- Test: `test/data/models/defence_test.dart`
- Test: `test/features/dashboard/progress_rail_test.dart` (add one test; `lib/features/dashboard/progress_rail.dart` is NOT touched)

**Interfaces:**
- Produces:
  - `Defence.redefenceOf` (`String?`)
  - `Defence.isRedefence` (`bool`)
  - `Defence.label` (`String`)
  - `static String Defence.redefenceIdFor(String failedId)`
  - top-level `bool hasRedefence(Defence failed, List<Defence> all)`
  - top-level `List<Defence> awaitingRedefence(List<Defence> all)`

- [ ] **Step 1: Write the failing tests.** Append inside `main()` of `test/data/models/defence_test.dart`:

```dart
  Defence defence(
    String id, {
    DefenceType type = DefenceType.preOral,
    PassFail? verdict,
    String? redefenceOf,
    DefenceStatus status = DefenceStatus.completed,
  }) =>
      Defence(
        id: id,
        thesisId: 't1',
        type: type,
        venue: 'AVR',
        panelUids: const ['p1'],
        adviserUid: 'a1',
        leaderUid: 'l1',
        status: status,
        createdBy: 'c1',
        panelVerdict: verdict,
        redefenceOf: redefenceOf,
      );

  group('re-defence', () {
    test('reads redefenceOf, and a defence without it is not a re-defence',
        () {
      final plain = Defence.fromMap('d1', {'type': 'final'});
      expect(plain.redefenceOf, isNull);
      expect(plain.isRedefence, isFalse);

      final again = Defence.fromMap('d1_redefence', {
        'type': 'final',
        'redefenceOf': 'd1',
      });
      expect(again.redefenceOf, 'd1');
      expect(again.isRedefence, isTrue);
    });

    test('names all four kinds', () {
      expect(defence('a').label, 'Pre-oral defence');
      expect(defence('a', type: DefenceType.final_).label, 'Final defence');
      expect(defence('a', redefenceOf: 'x').label, 'Pre-oral re-defence');
      expect(defence('a', type: DefenceType.final_, redefenceOf: 'x').label,
          'Final re-defence');
    });

    test('a re-defence has the id derived from the failed defence', () {
      expect(Defence.redefenceIdFor('abc'), 'abc_redefence');
    });

    test('a failed defence with no re-defence awaits one', () {
      final failed = defence('d1', verdict: PassFail.fail);
      expect(awaitingRedefence([failed]), [failed]);
    });

    test('a failed defence that has its re-defence awaits nothing', () {
      final failed = defence('d1', verdict: PassFail.fail);
      final again = defence('d1_redefence', redefenceOf: 'd1',
          status: DefenceStatus.scheduled);
      expect(awaitingRedefence([failed, again]), isEmpty);
      expect(hasRedefence(failed, [failed, again]), isTrue);
    });

    test('a cancelled re-defence still uses up the one re-defence', () {
      // The rules refuse a second document at the same derived id, so the
      // app must not offer a re-defence it cannot create.
      final failed = defence('d1', verdict: PassFail.fail);
      final cancelled = defence('d1_redefence', redefenceOf: 'd1',
          status: DefenceStatus.cancelled);
      expect(awaitingRedefence([failed, cancelled]), isEmpty);
    });

    test('a failed re-defence, a pass and no verdict await nothing', () {
      expect(
        awaitingRedefence([
          defence('r', verdict: PassFail.fail, redefenceOf: 'x'),
          defence('p', verdict: PassFail.pass),
          defence('n'),
        ]),
        isEmpty,
      );
    });
  });
```

In `test/features/dashboard/progress_rail_test.dart`, add inside `main()` a test. Its `defence(...)` helper builds a `Defence` without `redefenceOf`, so this test builds its own:

```dart
  test('a passed final re-defence reaches the Final stage', () {
    Defence d(String id, DefenceType type, {String? redefenceOf}) => Defence(
          id: id,
          thesisId: 't1',
          type: type,
          venue: 'AVR',
          panelUids: const ['p1'],
          adviserUid: 'a1',
          leaderUid: 'l1',
          status: DefenceStatus.completed,
          createdBy: 'c1',
          redefenceOf: redefenceOf,
        );
    expect(
      ProgressRail.stageFor(
        status: ThesisStatus.titleApproved,
        defences: [
          d('f1', DefenceType.final_),
          d('f1_redefence', DefenceType.final_, redefenceOf: 'f1'),
        ],
        chapters: [chapter()],
      ),
      RailStage.finalDefence,
    );
  });
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/data/models/defence_test.dart test/features/dashboard/progress_rail_test.dart`
Expected: compile errors, because `redefenceOf`, `isRedefence`, `label`, `redefenceIdFor`, `awaitingRedefence` and `hasRedefence` are undefined.

- [ ] **Step 3: Implement.** In `lib/data/models/defence.dart`:

  - Add `this.redefenceOf,` to the `Defence` constructor after `this.verdictRecordedAt,`.
  - After the `verdictRecordedAt` field, add:

```dart
  /// The failed defence this one re-does (spec 2026-09-25 §4.1). Absent on
  /// every ordinary defence. A re-defence has the same [type] as the defence
  /// it re-does, so every gate that asks "did the final defence pass"
  /// counts a passed final re-defence without knowing re-defences exist.
  final String? redefenceOf;

  bool get isRedefence => redefenceOf != null;

  /// "Pre-oral defence", "Final defence", "Pre-oral re-defence" or "Final
  /// re-defence": the name of this defence, where [DefenceType.label] names
  /// only its kind.
  String get label => switch ((type, isRedefence)) {
        (DefenceType.preOral, false) => 'Pre-oral defence',
        (DefenceType.final_, false) => 'Final defence',
        (DefenceType.preOral, true) => 'Pre-oral re-defence',
        (DefenceType.final_, true) => 'Final re-defence',
      };

  /// Where the one re-defence of [failedId] is stored. Derived rather than
  /// generated, so the rules can refuse a second one: a second write to the
  /// same id is an update, and no update arm allows it.
  static String redefenceIdFor(String failedId) => '${failedId}_redefence';
```

  - In `Defence.fromMap`, add `redefenceOf: map['redefenceOf'] as String?,` after `verdictRecordedAt`.
  - At the end of the file, add:

```dart
/// Whether [failed] already has its re-defence among [all]. A cancelled one
/// counts: the rules refuse a second document at the same derived id, so a
/// cancelled re-defence still uses up the one the group is allowed.
bool hasRedefence(Defence failed, List<Defence> all) =>
    all.any((d) => d.redefenceOf == failed.id);

/// The defences in [all] whose panel verdict was Fail and that have no
/// re-defence yet (spec 2026-09-25 §4.3). A failed re-defence is not
/// listed: a group gets one re-defence per stage.
List<Defence> awaitingRedefence(List<Defence> all) => [
      for (final d in all)
        if (d.panelVerdict == PassFail.fail &&
            !d.isRedefence &&
            !hasRedefence(d, all))
          d,
    ];
```

- [ ] **Step 4: Run and watch them pass**

Run: `flutter test test/data/models/defence_test.dart test/features/dashboard/progress_rail_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/defence.dart test/data/models/defence_test.dart test/features/dashboard/progress_rail_test.dart
git status --short
git commit -m "feat(defence): a defence can be the re-defence of a failed one

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Scheduling a re-defence in the repository

**Files:**
- Modify: `lib/data/repositories/defence_repository.dart`
- Test: `test/data/repositories/defence_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 (`Defence.redefenceIdFor`, `isRedefence`, `redefenceOf`).
- Produces: `Future<String> DefenceRepository.scheduleRedefence({required Defence failed, required DateTime scheduledAt, required String venue, required String createdBy})`. It returns the new id. It throws `ArgumentError` for a blank venue, a non-fail verdict or a re-defence, and `StateError` if one already exists.

- [ ] **Step 1: Write the failing tests.** Append inside `main()` of `test/data/repositories/defence_repository_test.dart`:

```dart
  group('scheduleRedefence', () {
    Future<Defence> failed(DefenceRepository repo, FakeFirebaseFirestore db,
        {String verdict = 'fail', String? redefenceOf}) async {
      final id = await scheduleOne(repo, type: DefenceType.final_);
      await db.collection('defenses').doc(id).update({
        'status': 'completed',
        'panelVerdict': verdict,
        if (redefenceOf != null) 'redefenceOf': redefenceOf,
      });
      return (await repo.watchDefence(id).first)!;
    }

    test('writes the re-defence at the derived id, copying the failed one',
        () async {
      final db = await seed();
      final repo = DefenceRepository(db);
      final f = await failed(repo, db);

      final id = await repo.scheduleRedefence(
        failed: f,
        scheduledAt: DateTime(2026, 10, 5, 9),
        venue: ' CICT AVR ',
        createdBy: 'c1',
      );

      expect(id, Defence.redefenceIdFor(f.id));
      final again = (await repo.watchDefence(id).first)!;
      expect(again.redefenceOf, f.id);
      expect(again.isRedefence, isTrue);
      expect(again.type, DefenceType.final_);
      expect(again.thesisId, 't1');
      expect(again.panelUids, ['p1', 'p2', 'p3']);
      expect(again.adviserUid, 'a1');
      expect(again.leaderUid, 'l1');
      expect(again.status, DefenceStatus.scheduled);
      expect(again.venue, 'CICT AVR');
      expect(again.panelVerdict, isNull);
    });

    test('refuses a defence that did not fail', () async {
      final db = await seed();
      final repo = DefenceRepository(db);
      final passed = await failed(repo, db, verdict: 'pass');
      await expectLater(
        repo.scheduleRedefence(failed: passed, scheduledAt: DateTime(2026, 10, 5),
            venue: 'AVR', createdBy: 'c1'),
        throwsArgumentError,
      );
    });

    test('refuses to re-defend a re-defence', () async {
      final db = await seed();
      final repo = DefenceRepository(db);
      final second = await failed(repo, db, redefenceOf: 'earlier');
      await expectLater(
        repo.scheduleRedefence(failed: second, scheduledAt: DateTime(2026, 10, 5),
            venue: 'AVR', createdBy: 'c1'),
        throwsArgumentError,
      );
    });

    test('refuses a second re-defence of the same Fail', () async {
      final db = await seed();
      final repo = DefenceRepository(db);
      final f = await failed(repo, db);
      await repo.scheduleRedefence(failed: f, scheduledAt: DateTime(2026, 10, 5),
          venue: 'AVR', createdBy: 'c1');
      await expectLater(
        repo.scheduleRedefence(failed: f, scheduledAt: DateTime(2026, 10, 6),
            venue: 'AVR', createdBy: 'c1'),
        throwsStateError,
      );
    });

    test('refuses a blank venue', () async {
      final db = await seed();
      final repo = DefenceRepository(db);
      final f = await failed(repo, db);
      await expectLater(
        repo.scheduleRedefence(failed: f, scheduledAt: DateTime(2026, 10, 5),
            venue: '  ', createdBy: 'c1'),
        throwsArgumentError,
      );
    });
  });
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/data/repositories/defence_repository_test.dart`
Expected: compile error, because `scheduleRedefence` is undefined.

- [ ] **Step 3: Implement.** In `lib/data/repositories/defence_repository.dart`, add after `schedule(...)`:

```dart
  /// Schedules the one re-defence of [failed] (spec 2026-09-25 §4.2).
  ///
  /// Written at [Defence.redefenceIdFor] with `set`, so the rules can refuse
  /// a second one. The thesis, kind, panel, adviser and leader are copied
  /// from [failed]. The create rule still checks the panel, adviser and
  /// leader against the thesis as it is now, so a panel changed since the
  /// Fail is refused rather than silently mixed.
  Future<String> scheduleRedefence({
    required Defence failed,
    required DateTime scheduledAt,
    required String venue,
    required String createdBy,
  }) async {
    if (venue.trim().isEmpty) {
      throw ArgumentError('Give the re-defence a venue.');
    }
    if (failed.panelVerdict != PassFail.fail) {
      throw ArgumentError('Only a defence the panel failed can be re-defended.');
    }
    if (failed.isRedefence) {
      throw ArgumentError('A re-defence cannot itself be re-defended.');
    }
    final ref = _defence(Defence.redefenceIdFor(failed.id));
    // The rules refuse this too; checked here as well because
    // fake_cloud_firestore enforces no rules, and `set` on an existing
    // document would otherwise quietly overwrite it in every Dart test.
    if ((await ref.get()).exists) {
      throw StateError('This defence already has a re-defence.');
    }
    await ref.set({
      'thesisId': failed.thesisId,
      'type': failed.type.value,
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'venue': venue.trim(),
      'panelUids': failed.panelUids,
      'adviserUid': failed.adviserUid,
      'leaderUid': failed.leaderUid,
      'status': DefenceStatus.scheduled.value,
      'createdBy': createdBy,
      // Pinned to request.time by the rule; see schedule() above.
      'createdAt': FieldValue.serverTimestamp(),
      'redefenceOf': failed.id,
    });
    return ref.id;
  }
```

- [ ] **Step 4: Run and watch them pass**

Run: `flutter test test/data/repositories/defence_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/defence_repository.dart test/data/repositories/defence_repository_test.dart
git status --short
git commit -m "feat(defence): schedule the one re-defence of a failed defence

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Security rules for re-defence

**Files:**
- Modify: `firestore.rules` (`match /defenses/{defenseId}`, around line 1297)
- Test: `rules-test/rules.test.js`

**Interfaces:**
- Consumes: the stored shape from Task 2 (`redefenceOf`, the id `<failed>_redefence`).

- [ ] **Step 1: Write the failing rules tests.** In `rules-test/rules.test.js`, after the test `"M3: the panel snapshot must match the thesis at scheduling"`, add:

```js
// ---------- Re-defence (spec 2026-09-25 §5) ----------

async function seedFailed({ verdict = "fail", type = "preOral",
                            redefenceOf = null } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "theses/dt1"), defThesis());
    await setDoc(doc(db, "theses/dt2"), defThesis());
    await setDoc(doc(db, "users/coord-uid"),
      { role: "coordinator", active: true });
    await setDoc(doc(db, "defenses/rf1"), {
      ...defDoc({ type, status: "completed" }),
      ...(verdict ? { panelVerdict: verdict } : {}),
      ...(redefenceOf ? { redefenceOf } : {}),
    });
  });
}

function redefenceDoc(extra = {}) {
  return defDoc({ redefenceOf: "rf1", ...extra });
}

test("Re-defence: the coordinator re-defends a failed pre-oral", async () => {
  await seedFailed();
  const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");
  await assertSucceeds(setDoc(doc(coord, "defenses/rf1_redefence"),
    redefenceDoc()));
});

test("Re-defence: the coordinator re-defends a failed final", async () => {
  await seedFailed({ type: "final" });
  const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");
  await assertSucceeds(setDoc(doc(coord, "defenses/rf1_redefence"),
    redefenceDoc({ type: "final" })));
});

test("Re-defence: only after a Fail", async () => {
  const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");
  await seedFailed({ verdict: "pass" });
  await assertFails(setDoc(doc(coord, "defenses/rf1_redefence"),
    redefenceDoc()));
  await seedFailed({ verdict: null });
  await assertFails(setDoc(doc(coord, "defenses/rf1_redefence"),
    redefenceDoc()));
});

test("Re-defence: a re-defence is not re-defended", async () => {
  await seedFailed({ redefenceOf: "rf0" });
  const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");
  await assertFails(setDoc(doc(coord, "defenses/rf1_redefence"),
    redefenceDoc()));
});

test("Re-defence: only one per Fail", async () => {
  await seedFailed();
  const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");
  await assertSucceeds(setDoc(doc(coord, "defenses/rf1_redefence"),
    redefenceDoc()));
  // The second write is an update, and no update arm allows it.
  await assertFails(setDoc(doc(coord, "defenses/rf1_redefence"),
    redefenceDoc({ venue: "Another room" })));
});

test("Re-defence: same stage, same thesis, derived id", async () => {
  await seedFailed();
  const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");
  await assertFails(setDoc(doc(coord, "defenses/rf1_redefence"),
    redefenceDoc({ type: "final" })));
  await assertFails(setDoc(doc(coord, "defenses/rf1_redefence"),
    redefenceDoc({ thesisId: "dt2" })));
  await assertFails(setDoc(doc(coord, "defenses/some-other-id"),
    redefenceDoc()));
  // Control.
  await assertSucceeds(setDoc(doc(coord, "defenses/rf1_redefence"),
    redefenceDoc()));
});

test("Re-defence: only the coordinator, and only of a real defence",
  async () => {
    await seedFailed();
    const adv = asDefUser("adviser-uid", "adviser@isufst.edu.ph");
    const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");
    await assertFails(setDoc(doc(adv, "defenses/rf1_redefence"),
      redefenceDoc({ createdBy: "adviser-uid" })));
    await assertFails(setDoc(doc(coord, "defenses/nope_redefence"),
      redefenceDoc({ redefenceOf: "nope" })));
  });

test("Re-defence: a panel changed since the Fail is refused", async () => {
  await seedFailed();
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), "theses/dt1"),
      defThesis({ panelistUids: ["pan-uid", "new-uid"] })));
  const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");
  // Copied from the failed defence, as the app does: the old panel.
  await assertFails(setDoc(doc(coord, "defenses/rf1_redefence"),
    redefenceDoc()));
});
```

- [ ] **Step 2: Run and watch the allowed cases fail**

Run: `cd rules-test && npm test`
Expected: the two "re-defends a failed …" tests and the controls FAIL. The current create rule's `keys().hasOnly(...)` does not admit `redefenceOf`. The deny cases already pass, for that same reason. Every pre-existing test still passes.

- [ ] **Step 3: Implement.** In `firestore.rules`, inside `match /defenses/{defenseId}`:

  - After `function thesisOf(...) { ... }`, add:

```
      // A re-defence (spec 2026-09-25 §5): the same stage of the same thesis
      // again, after the panel's verdict on it was Fail. Stored at an id
      // derived from the failed defence, so a second one is an update, which
      // no update arm allows. `!('redefenceOf' in failed)` is the
      // one-re-defence limit; allowing more changes only that line.
      function validRedefence() {
        let failed = get(/databases/$(database)/documents/defenses/$(incoming().redefenceOf)).data;
        return incoming().redefenceOf is string
            && defenseId == incoming().redefenceOf + '_redefence'
            && failed.thesisId == incoming().thesisId
            && failed.type == incoming().type
            && failed.get('panelVerdict', null) == 'fail'
            && !('redefenceOf' in failed);
      }
```

  - In `allow create`, add `'redefenceOf'` to the `incoming().keys().hasOnly([...])` list, after `'createdAt'`.
  - After the line `&& incoming().createdAt == request.time`, add:

```
                     && (!('redefenceOf' in incoming()) || validRedefence())
```

- [ ] **Step 4: Run and watch them pass**

Run: `cd rules-test && npm test`
Expected: every test PASSES, old and new.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git status --short
git commit -m "feat(rules): one re-defence after a Fail, same stage, same thesis

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The title defences each reader can open

**Files:**
- Modify: `lib/providers/title_providers.dart`
- Test: `test/providers/my_title_defences_test.dart` (new)

**Interfaces:**
- Consumes: `currentUserProvider` (`StreamProvider<AppUser?>`), `thesesByStatusProvider(ThesisStatus)`, `myAdviseesProvider`, `myThesisProvider`, `thesisByIdProvider(String)` (all in `thesis_providers.dart`), and `myThesisIdsProvider` (`title_providers.dart`).
- Produces: `final myTitleDefencesProvider = Provider<AsyncValue<List<Thesis>>>`. It gives, per role, the theses at `titlePendingDefence` the reader can open:
  - Coordinator and Dean: all.
  - Faculty: advised plus panel, each thesis once.
  - Student: their own thesis, when it is at title defence.

- [ ] **Step 1: Write the failing tests.** Create `test/providers/my_title_defences_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

Map<String, dynamic> thesis({
  String leaderUid = 'l1',
  String adviserUid = 'a1',
  String status = 'titlePendingDefence',
}) =>
    {
      'leaderUid': leaderUid,
      'adviserUid': adviserUid,
      'panelistUids': <String>[],
      'memberNames': <String>[],
      'workingTitle': 'A Working Title',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': status,
    };

Future<ProviderContainer> containerFor(
    FakeFirebaseFirestore db, String uid, String role) async {
  await db.collection('users').doc(uid).set({
    'fullName': 'Test $uid',
    'email': '$uid@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  final c = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
          uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
    )),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// The provider is synchronous over streams, so let them emit until it
/// settles on a value.
Future<List<Thesis>> settle(ProviderContainer c) async {
  final sub = c.listen(myTitleDefencesProvider, (_, _) {});
  addTearDown(sub.close);
  for (var i = 0; i < 100; i++) {
    final v = c.read(myTitleDefencesProvider);
    if (v.hasValue) return v.value!;
    if (v.hasError) throw v.error!;
    await Future<void>.delayed(Duration.zero);
  }
  fail('myTitleDefencesProvider never settled');
}

void main() {
  test('the coordinator sees every thesis at title defence', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis());
    await db.collection('theses').doc('t2').set(thesis());
    await db.collection('theses').doc('t3').set(thesis(status: 'titleApproved'));
    final c = await containerFor(db, 'c1', 'coordinator');
    expect((await settle(c)).map((t) => t.id).toSet(), {'t1', 't2'});
  });

  test('an adviser sees their advisee at title defence, with no nomination',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f1'));
    await db.collection('theses').doc('t2')
        .set(thesis(adviserUid: 'f1', status: 'titleApproved'));
    final c = await containerFor(db, 'f1', 'faculty');
    expect((await settle(c)).map((t) => t.id), ['t1']);
  });

  test('a panelist sees a thesis they sit on', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t2').set(thesis(adviserUid: 'a9'));
    await db.doc('theses/t2/nominations/f1')
        .set({'nomineeUid': 'f1', 'conformeStatus': 'accepted'});
    final c = await containerFor(db, 'f1', 'faculty');
    expect((await settle(c)).map((t) => t.id), ['t2']);
  });

  test('advising and sitting on the same thesis lists it once', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f1'));
    await db.doc('theses/t1/nominations/f1')
        .set({'nomineeUid': 'f1', 'conformeStatus': 'accepted'});
    final c = await containerFor(db, 'f1', 'faculty');
    expect((await settle(c)).map((t) => t.id), ['t1']);
  });

  test('a nomination whose thesis is gone is skipped, not an error',
      () async {
    final db = FakeFirebaseFirestore();
    await db.doc('theses/gone/nominations/f1')
        .set({'nomineeUid': 'f1', 'conformeStatus': 'accepted'});
    final c = await containerFor(db, 'f1', 'faculty');
    expect(await settle(c), isEmpty);
  });

  test('a student sees their own thesis only while it is at title defence',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 's1'));
    final c = await containerFor(db, 's1', 'student');
    expect((await settle(c)).map((t) => t.id), ['t1']);

    await db.collection('theses').doc('t1')
        .update({'status': 'titleApproved'});
    await Future<void>.delayed(Duration.zero);
    expect(await settle(c), isEmpty);
  });
}
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/providers/my_title_defences_test.dart`
Expected: compile error, because `myTitleDefencesProvider` is undefined.

- [ ] **Step 3: Implement.** Append to `lib/providers/title_providers.dart`. Add these imports at the top alongside the existing ones:
  - `import 'package:ethesishub/data/models/thesis.dart';`
  - `import 'package:ethesishub/data/models/thesis_status.dart';`
  - `import 'package:ethesishub/data/models/user_role.dart';`
  - `import 'package:ethesishub/providers/thesis_providers.dart';`

Then add:

```dart
/// The theses at title defence that the signed-in reader can open
/// (spec 2026-09-25 §6.2), per role:
/// - Coordinator and Dean: every one.
/// - Faculty: the ones they advise **or** sit on, each once. An adviser in
///   adviser mode never sees the Panels page, so advised theses must come
///   from [myAdviseesProvider], not only from nominations.
/// - Student: their own thesis, while it is at title defence.
final myTitleDefencesProvider = Provider<AsyncValue<List<Thesis>>>((ref) {
  final me = ref.watch(currentUserProvider);
  if (!me.hasValue) {
    return me.hasError
        ? AsyncError(me.error!, me.stackTrace ?? StackTrace.empty)
        : const AsyncLoading();
  }

  bool atTitleDefence(Thesis t) =>
      t.status == ThesisStatus.titlePendingDefence;

  switch (me.value?.role) {
    case UserRole.coordinator || UserRole.dean:
      return ref.watch(
          thesesByStatusProvider(ThesisStatus.titlePendingDefence));
    case UserRole.student:
      return ref.watch(myThesisProvider).whenData(
          (t) => t != null && atTitleDefence(t) ? [t] : const <Thesis>[]);
    case UserRole.faculty:
      final advised = ref.watch(myAdviseesProvider);
      final ids = ref.watch(myThesisIdsProvider);
      for (final a in [advised, ids]) {
        if (a.hasError && !a.hasValue) {
          return AsyncError(a.error!, a.stackTrace ?? StackTrace.empty);
        }
      }
      if (!advised.hasValue || !ids.hasValue) return const AsyncLoading();

      final byId = {for (final t in advised.value!) t.id: t};
      for (final id in ids.value!) {
        if (byId.containsKey(id)) continue;
        final t = ref.watch(thesisByIdProvider(id));
        if (!t.hasValue && !t.hasError) return const AsyncLoading();
        // A thesis the reader can no longer read (a declined nomination) or
        // that no longer exists is simply not theirs to open.
        final thesis = t.valueOrNull;
        if (thesis != null) byId[id] = thesis;
      }
      return AsyncData(byId.values.where(atTitleDefence).toList());
    case null:
      return const AsyncData(<Thesis>[]);
  }
});
```

If the analyzer reports that the `switch` does not cover every `UserRole` value, add the missing roles to the `case UserRole.coordinator || UserRole.dean:` line, or to a `default:` that returns `const AsyncData(<Thesis>[])`. Report which you chose.

- [ ] **Step 4: Run and watch them pass**

Run: `flutter test test/providers/my_title_defences_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/title_providers.dart test/providers/my_title_defences_test.dart
git status --short
git commit -m "feat(titles): the title defences each reader can open, adviser included

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Stages, filtered lists, and counts

**Files:**
- Create: `lib/features/defence/defence_stage.dart`
- Modify: `lib/features/defence/defences_list.dart` (the `where` filter, empty copy, and `d.label` in `DefenceRow`)
- Modify: `lib/features/defence/defence_calendar.dart` (the `where` filter)
- Test: `test/features/defence/defence_stage_test.dart` (new)
- Test: `test/features/defence/defences_list_test.dart` (add one test)

**Interfaces:**
- Consumes: Task 1 (`isRedefence`, `label`, `awaitingRedefence`); Task 4 (`myTitleDefencesProvider`); `myDefencesProvider`.
- Produces:
  - `enum DefenceStage { title, preOral, finalDefence, redefence }`, with:
    - `param` (`'title'`, `'preOral'`, `'final'`, `'redefence'`), `label`, `shortLabel`, `icon`
    - `static DefenceStage fromParam(String?)`
    - `String get route`
    - `bool includes(Defence)`
    - `String labelFor(int count, {required bool compact})`
  - `final defenceStageCountsProvider = Provider<Map<DefenceStage, int>>`.
  - `DefencesList({Key? key, bool Function(Defence)? where, String emptyTitle, String emptyMessage})`.
  - `DefenceCalendar({Key? key, bool Function(Defence)? where})`.

- [ ] **Step 1: Write the failing tests.** Create `test/features/defence/defence_stage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/defence/defence_stage.dart';

Defence d(String id, DefenceType type, {String? redefenceOf}) => Defence(
      id: id,
      thesisId: 't1',
      type: type,
      venue: 'AVR',
      panelUids: const [],
      adviserUid: 'a1',
      leaderUid: 'l1',
      status: DefenceStatus.scheduled,
      createdBy: 'c1',
      redefenceOf: redefenceOf,
    );

void main() {
  test('reads its stage from the URL, falling back to Title', () {
    expect(DefenceStage.fromParam('title'), DefenceStage.title);
    expect(DefenceStage.fromParam('preOral'), DefenceStage.preOral);
    expect(DefenceStage.fromParam('final'), DefenceStage.finalDefence);
    expect(DefenceStage.fromParam('redefence'), DefenceStage.redefence);
    expect(DefenceStage.fromParam(null), DefenceStage.title);
    expect(DefenceStage.fromParam('FINAL'), DefenceStage.title);
    expect(DefenceStage.fromParam('nonsense'), DefenceStage.title);
  });

  test('each stage has its own URL', () {
    for (final s in DefenceStage.values) {
      expect(DefenceStage.fromParam(Uri.parse(s.route).queryParameters['stage']),
          s);
    }
  });

  test('each scheduled stage holds only its own defences', () {
    final pre = d('p', DefenceType.preOral);
    final fin = d('f', DefenceType.final_);
    final again = d('p_redefence', DefenceType.preOral, redefenceOf: 'p');
    expect([pre, fin, again].where(DefenceStage.preOral.includes), [pre]);
    expect([pre, fin, again].where(DefenceStage.finalDefence.includes), [fin]);
    expect([pre, fin, again].where(DefenceStage.redefence.includes), [again]);
    expect([pre, fin, again].where(DefenceStage.title.includes), isEmpty);
  });

  test('a label carries its count only when there is something', () {
    expect(DefenceStage.preOral.labelFor(0, compact: false), 'Pre-oral');
    expect(DefenceStage.preOral.labelFor(2, compact: false), 'Pre-oral (2)');
    expect(DefenceStage.finalDefence.labelFor(1, compact: false),
        'Final defence (1)');
    expect(DefenceStage.finalDefence.labelFor(1, compact: true), 'Final (1)');
    expect(DefenceStage.title.labelFor(0, compact: true), 'Title');
  });
}
```

Add to `test/features/defence/defences_list_test.dart` a test that uses that file's existing setup helpers. Pump `DefencesList(where: (d) => d.type == DefenceType.final_, emptyTitle: 'No final defences', emptyMessage: 'None yet.')` with one pre-oral defence seeded. Expect `find.text('No final defences')` to find one widget and `find.byKey(const Key('defenceRow-<that id>'))` to find nothing.

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/features/defence/defence_stage_test.dart test/features/defence/defences_list_test.dart`
Expected: compile errors, because `defence_stage.dart` and the `where` parameter do not exist.

- [ ] **Step 3: Create `lib/features/defence/defence_stage.dart`:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// The four stages the Defences page switches between (spec 2026-09-25
/// §6.1), in the order a thesis meets them.
enum DefenceStage {
  title('title', 'Title defence', 'Title', Icons.forum_outlined),
  preOral('preOral', 'Pre-oral', 'Pre-oral', Icons.record_voice_over_outlined),
  finalDefence('final', 'Final defence', 'Final', Icons.school_outlined),
  redefence('redefence', 'Re-defence', 'Re-defence', Icons.replay_outlined);

  const DefenceStage(this.param, this.label, this.shortLabel, this.icon);

  /// The `?stage=` value. Stored in links, so it never changes.
  final String param;
  final String label;

  /// The label on a phone, where four full labels do not fit.
  final String shortLabel;
  final IconData icon;

  /// A missing or unknown value is the first stage, never an error: a stale
  /// or hand-typed link still lands somewhere useful.
  static DefenceStage fromParam(String? raw) {
    for (final s in values) {
      if (s.param == raw) return s;
    }
    return title;
  }

  String get route => '/defences?stage=$param';

  /// Whether [d] belongs on this stage. The title defence is not a
  /// `defenses` document, so it holds none.
  bool includes(Defence d) => switch (this) {
        title => false,
        preOral => d.type == DefenceType.preOral && !d.isRedefence,
        finalDefence => d.type == DefenceType.final_ && !d.isRedefence,
        redefence => d.isRedefence,
      };

  String labelFor(int count, {required bool compact}) {
    final base = compact ? shortLabel : label;
    return count > 0 ? '$base ($count)' : base;
  }
}

/// What still needs attention on each stage, for the switch's labels:
/// - Title: every title defence the reader can open.
/// - Pre-oral and Final: defences scheduled or in progress.
/// - Re-defence: open re-defences plus failed defences awaiting one.
///
/// A total of every defence ever held would only grow.
final defenceStageCountsProvider = Provider<Map<DefenceStage, int>>((ref) {
  final defences =
      ref.watch(myDefencesProvider).valueOrNull ?? const <Defence>[];
  final titles =
      ref.watch(myTitleDefencesProvider).valueOrNull ?? const <Thesis>[];

  bool open(Defence d) =>
      d.status == DefenceStatus.scheduled ||
      d.status == DefenceStatus.inProgress;
  int openOn(DefenceStage s) =>
      defences.where((d) => s.includes(d) && open(d)).length;

  return {
    DefenceStage.title: titles.length,
    DefenceStage.preOral: openOn(DefenceStage.preOral),
    DefenceStage.finalDefence: openOn(DefenceStage.finalDefence),
    DefenceStage.redefence:
        openOn(DefenceStage.redefence) + awaitingRedefence(defences).length,
  };
});
```

- [ ] **Step 4: Filter `DefencesList`.** In `lib/features/defence/defences_list.dart`:

  - Replace `const DefencesList({super.key});` with:

```dart
  const DefencesList({
    super.key,
    this.where,
    this.emptyTitle = 'No defences scheduled',
    this.emptyMessage = 'A defence appears here once the Coordinator '
        'schedules one you are part of.',
  });

  /// Which of the reader's defences to show; all of them when null. The
  /// Defences page passes one stage's [DefenceStage.includes].
  final bool Function(Defence)? where;
  final String emptyTitle;
  final String emptyMessage;
```

  - In `build`'s `data:` branch, start with `final shown = where == null ? defences : defences.where(where!).toList();`. Use `shown` in place of `defences` for the empty check and for the `preOral` and `final_` groupings.
  - The empty state becomes `EmptyState(key: const Key('noDefences'), icon: Icons.forum_outlined, title: emptyTitle, message: emptyMessage)`. It is no longer `const`.
  - In `DefenceRow`, replace `d.type.label,` with `d.label,`.

- [ ] **Step 5: Filter `DefenceCalendar`.** In `lib/features/defence/defence_calendar.dart`:

  - Replace `const DefenceCalendar({super.key});` with:

```dart
  const DefenceCalendar({super.key, this.where});

  /// Which of the reader's defences to show; all of them when null.
  final bool Function(Defence)? where;
```

  - In `build`'s `data:` branch, start with `final shown = widget.where == null ? defences : defences.where(widget.where!).toList();`. Use `shown` for the empty check and pass it to `_buildCalendar(context, shown)`.

- [ ] **Step 6: Run and watch them pass, plus the existing defence suites**

Run: `flutter test test/features/defence/`
Expected: PASS. The existing list and calendar tests are unchanged, because `where` is null there.

- [ ] **Step 7: Commit**

```bash
git add lib/features/defence/defence_stage.dart lib/features/defence/defences_list.dart lib/features/defence/defence_calendar.dart test/features/defence/defence_stage_test.dart test/features/defence/defences_list_test.dart
git status --short
git commit -m "feat(defence): defence stages, and a list and calendar filtered to one

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The Defences page stage switch, the Title stage and the Re-defence stage

**Files:**
- Create: `lib/features/defence/title_defence_stage.dart`
- Create: `lib/features/defence/redefence_stage.dart`
- Modify: `lib/features/defence/defences_screen.dart`
- Test: `test/features/defence/defences_screen_test.dart` (adjust the helpers; add tests)
- Test: `test/features/defence/title_defence_stage_test.dart` (new)
- Test: `test/features/dashboard/destination_screens_test.dart` (the title text changes)

**Interfaces:**
- Consumes: Task 5 (`DefenceStage`, `defenceStageCountsProvider`, `DefencesList(where:…)`, `DefenceCalendar(where:…)`); Task 4 (`myTitleDefencesProvider`); Task 1 (`awaitingRedefence`, `Defence.label`); `ThesisQueue` (`lib/features/dashboard/thesis_queue.dart`); `candidateTitlesProvider` (`title_providers.dart`); `myThesisProvider`; `Breakpoint.of(context)` (`lib/core/design/layout.dart`).
- Produces:
  - `DefencesScreen({Key? key, DefenceStage initialStage = DefenceStage.title, String title = 'Defences', String subtitle = 'Title defences, pre-oral and final defences, and re-defences.'})`
  - `TitleDefenceStage()`
  - `RedefenceStage({required bool calendar})`
  - `AwaitingRedefenceRow({required Defence failed, required bool canSchedule})`
  - Keys:
    - `defenceStageSwitch`
    - `goToDefence-<thesisId>`
    - `studentTitleCard`, `studentTitleMessage`, `resubmitTitles`
    - `awaitingRedefence`, `scheduleRedefence-<id>`, `awaitingRedefenceNote-<id>`
    - `noRedefences`

- [ ] **Step 1: Write the failing tests.**

  In `test/features/defence/defences_screen_test.dart`:

  - Give `_seedDefence` these new named parameters, and write each into the map, only when non-null for the two nullable ones: `String type = 'preOral'`, `String? redefenceOf`, `String? panelVerdict`.
  - Give `_seedUser` a named parameter `String role = 'faculty'`, used for `'role'`.
  - Give `_wrap` a named parameter `DefenceStage stage = DefenceStage.preOral`, used as `DefencesScreen(initialStage: stage)`. The existing tests keep their meaning, because they seed pre-oral defences.
  - Add `import 'package:ethesishub/features/defence/defence_stage.dart';`.

  Then append:

```dart
  testWidgets('the stage switch offers the four stages', (tester) async {
    final db = await _seedUser('a1');
    await tester.pumpWidget(_wrap(db, uid: 'a1', stage: DefenceStage.title));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceStageSwitch')), findsOneWidget);
    for (final label in ['Title defence', 'Pre-oral', 'Final defence',
        'Re-defence']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('List and Calendar are hidden on the title stage',
      (tester) async {
    final db = await _seedUser('a1');
    await tester.pumpWidget(_wrap(db, uid: 'a1', stage: DefenceStage.title));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('defencesViewToggle')), findsNothing);

    await tester.tap(find.text('Pre-oral'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('defencesViewToggle')), findsOneWidget);
  });

  testWidgets('each stage lists only its own defences', (tester) async {
    final db = await _seedUser('a1');
    await _seedDefence(db, id: 'p', adviserUid: 'a1',
        status: 'completed', panelVerdict: 'fail',
        scheduledAt: DateTime(2026, 9, 1, 9));
    await _seedDefence(db, id: 'f', adviserUid: 'a1', type: 'final',
        scheduledAt: DateTime(2026, 9, 2, 9));
    await _seedDefence(db, id: 'p_redefence', adviserUid: 'a1',
        redefenceOf: 'p', scheduledAt: DateTime(2026, 9, 3, 9));

    Future<void> expectRows(DefenceStage stage, Set<String> ids) async {
      await tester.pumpWidget(_wrap(db, uid: 'a1', stage: stage));
      await tester.pumpAndSettle();
      for (final id in ['p', 'f', 'p_redefence']) {
        expect(find.byKey(Key('defenceRow-$id')),
            ids.contains(id) ? findsOneWidget : findsNothing,
            reason: '$stage / $id');
      }
    }

    await expectRows(DefenceStage.preOral, {'p'});
    await expectRows(DefenceStage.finalDefence, {'f'});
    await expectRows(DefenceStage.redefence, {'p_redefence'});
  });

  testWidgets('a stage counts what still needs attention', (tester) async {
    final db = await _seedUser('a1');
    await _seedDefence(db, id: 'open', adviserUid: 'a1',
        scheduledAt: DateTime(2026, 9, 1, 9));
    await _seedDefence(db, id: 'done', adviserUid: 'a1', status: 'completed',
        scheduledAt: DateTime(2026, 9, 2, 9));
    await tester.pumpWidget(_wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();
    expect(find.text('Pre-oral (1)'), findsOneWidget);
  });

  testWidgets('the coordinator is offered the re-defence of a failed '
      'defence; others are told it is coming', (tester) async {
    final coordDb = await _seedUser('c1', role: 'coordinator');
    await _seedDefence(coordDb, id: 'p', adviserUid: 'a1',
        status: 'completed', panelVerdict: 'fail',
        scheduledAt: DateTime(2026, 9, 1, 9));
    await tester.pumpWidget(
        _wrap(coordDb, uid: 'c1', stage: DefenceStage.redefence));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheduleRedefence-p')), findsOneWidget);

    final advDb = await _seedUser('a1');
    await _seedDefence(advDb, id: 'p', adviserUid: 'a1',
        status: 'completed', panelVerdict: 'fail',
        scheduledAt: DateTime(2026, 9, 1, 9));
    await tester.pumpWidget(
        _wrap(advDb, uid: 'a1', stage: DefenceStage.redefence));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheduleRedefence-p')), findsNothing);
    expect(find.byKey(const Key('awaitingRedefenceNote-p')), findsOneWidget);
  });

  testWidgets('an empty re-defence stage says what a re-defence is',
      (tester) async {
    final db = await _seedUser('a1');
    await tester.pumpWidget(
        _wrap(db, uid: 'a1', stage: DefenceStage.redefence));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('noRedefences')), findsOneWidget);
  });

  testWidgets('on a phone the switch fits, with short labels',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = await _seedUser('a1');
    await _seedDefence(db, id: 'open', adviserUid: 'a1',
        scheduledAt: DateTime(2026, 9, 1, 9));
    await tester.pumpWidget(_wrap(db, uid: 'a1', stage: DefenceStage.title));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Pre-oral (1)'), findsOneWidget);
  });
```

  Create `test/features/defence/title_defence_stage_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/defence/title_defence_stage.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Map<String, dynamic> thesis({
  String leaderUid = 'l1',
  String adviserUid = 'a1',
  String status = 'titlePendingDefence',
  String? approvedTitleId,
}) =>
    {
      'leaderUid': leaderUid,
      'adviserUid': adviserUid,
      'panelistUids': <String>[],
      'memberNames': <String>[],
      'workingTitle': 'A Working Title',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': status,
      if (approvedTitleId != null) 'approvedTitleId': approvedTitleId,
    };

Future<Widget> wrap(FakeFirebaseFirestore db, String uid, String role) async {
  await db.collection('users').doc(uid).set({
    'fullName': 'Test $uid',
    'email': '$uid@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: TitleDefenceStage())),
    ),
  );
}

void main() {
  testWidgets('an adviser opens their advisee\'s title defence',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f1'));
    await tester.pumpWidget(await wrap(db, 'f1', 'faculty'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goToDefence-t1')), findsOneWidget);
    expect(find.text('Open title defence'), findsOneWidget);
  });

  testWidgets('a panelist opens a title defence they sit on',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t2').set(thesis(adviserUid: 'a9'));
    await db.doc('theses/t2/nominations/f1')
        .set({'nomineeUid': 'f1', 'conformeStatus': 'accepted'});
    await tester.pumpWidget(await wrap(db, 'f1', 'faculty'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goToDefence-t2')), findsOneWidget);
  });

  testWidgets('the Dean sees every title defence', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis());
    await db.collection('theses').doc('t2').set(thesis());
    await tester.pumpWidget(await wrap(db, 'd1', 'dean'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goToDefence-t1')), findsOneWidget);
    expect(find.byKey(const Key('goToDefence-t2')), findsOneWidget);
  });

  testWidgets('a student reads where their titles stand, and cannot open '
      'the room', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 's1'));
    await tester.pumpWidget(await wrap(db, 's1', 'student'));
    await tester.pumpAndSettle();
    expect(find.text('Your candidate titles are with the panel.'),
        findsOneWidget);
    expect(find.byKey(const Key('goToDefence-t1')), findsNothing);

    await db.collection('theses').doc('t1')
        .update({'status': 'titleRejected'});
    await tester.pumpAndSettle();
    expect(find.text('The panel returned your titles. Submit a new set.'),
        findsOneWidget);
    expect(find.byKey(const Key('resubmitTitles')), findsOneWidget);
  });

  testWidgets('a student sees the title the panel approved', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(
        leaderUid: 's1', status: 'titleApproved', approvedTitleId: 'c1'));
    await db.doc('theses/t1/candidateTitles/c1').set({
      'titleText': 'Mangrove Carbon Stocks',
      'position': 0,
      'round': 1,
      'submittedAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    });
    await tester.pumpWidget(await wrap(db, 's1', 'student'));
    await tester.pumpAndSettle();
    expect(find.text('Title approved: Mangrove Carbon Stocks'),
        findsOneWidget);
  });
}
```

  In `test/features/dashboard/destination_screens_test.dart`, in `'defences screen renders the defences list standalone'`, replace `expect(find.text('Scheduled defences'), findsOneWidget);` with `expect(find.text('Defences'), findsOneWidget);`.

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/features/defence/ test/features/dashboard/destination_screens_test.dart`
Expected: compile errors, because `initialStage`, `title_defence_stage.dart` and `RedefenceStage` do not exist.

- [ ] **Step 3: Create `lib/features/defence/title_defence_stage.dart`:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/dashboard/thesis_queue.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// The Title defence stage of the Defences page (spec 2026-09-25 §6.2).
///
/// Everyone but a student gets the title defences they can open, each with
/// a way in. A student gets where their own titles stand, never the room:
/// the remarks are not theirs to watch while the panel deliberates.
class TitleDefenceStage extends ConsumerWidget {
  const TitleDefenceStage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    if (!me.hasValue) {
      return me.hasError
          ? ErrorState(error: me.error, message: 'Could not load your account.')
          : const LoadingState(label: 'Loading title defences…');
    }
    final role = me.value?.role;
    if (role == UserRole.student) return const _StudentTitleCard();

    return ThesisQueue(
      theses: ref.watch(myTitleDefencesProvider),
      waitingSince: (t) => t.titlesSubmittedAt,
      errorMessage: 'Could not load the title defences.',
      emptyTitle: 'No title defences',
      emptyMessage: role == UserRole.faculty
          ? 'None of your theses are at title defence right now.'
          : 'A thesis appears here once its group has submitted their '
              'candidate titles.',
      rowAction: (context, t) => FilledButton.tonal(
        key: Key('goToDefence-${t.id}'),
        onPressed: () => context.push('/defence/${t.id}'),
        child: const Text('Open title defence'),
      ),
    );
  }
}

class _StudentTitleCard extends ConsumerWidget {
  const _StudentTitleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(myThesisProvider).when(
          loading: () => const LoadingState(label: 'Loading your thesis…'),
          error: (e, _) =>
              ErrorState(error: e, message: 'Could not load your thesis.'),
          data: (thesis) {
            if (thesis == null) {
              return const EmptyState(
                icon: Icons.groups_outlined,
                title: 'No thesis yet',
                message: 'Your title defence appears here once your group '
                    'has a thesis.',
              );
            }
            return Panel(
              key: const Key('studentTitleCard'),
              title: 'Title defence',
              icon: Icons.forum_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _message(thesis),
                  if (thesis.status == ThesisStatus.titleRejected) ...[
                    const Gap.md(),
                    FilledButton.tonal(
                      key: const Key('resubmitTitles'),
                      onPressed: () =>
                          context.push('/thesis/titles?id=${thesis.id}'),
                      child: const Text('Submit new titles'),
                    ),
                  ],
                ],
              ),
            );
          },
        );
  }

  Widget _message(Thesis thesis) => switch (thesis.status) {
        ThesisStatus.titlePendingDefence => const Text(
            'Your candidate titles are with the panel.',
            key: Key('studentTitleMessage'),
          ),
        ThesisStatus.titleRejected => const Text(
            'The panel returned your titles. Submit a new set.',
            key: Key('studentTitleMessage'),
          ),
        ThesisStatus.titleApproved ||
        ThesisStatus.archived =>
          _ApprovedTitle(thesis: thesis),
        _ => const Text(
            'Your group has not submitted candidate titles yet.',
            key: Key('studentTitleMessage'),
          ),
      };
}

/// "Title approved: <the approved candidate>", or a plain sentence while the
/// candidate is still loading or cannot be read.
class _ApprovedTitle extends ConsumerWidget {
  const _ApprovedTitle({required this.thesis});

  final Thesis thesis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approvedId = thesis.approvedTitleId;
    final candidates =
        ref.watch(candidateTitlesProvider(thesis.id)).valueOrNull;
    String? text;
    for (final c in candidates ?? const []) {
      if (c.id == approvedId) text = c.titleText;
    }
    return Text(
      text == null ? 'Your title has been approved.' : 'Title approved: $text',
      key: const Key('studentTitleMessage'),
    );
  }
}
```

- [ ] **Step 4: Create `lib/features/defence/redefence_stage.dart`:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/defence/defence_calendar.dart';
import 'package:ethesishub/features/defence/defence_stage.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The Re-defence stage of the Defences page (spec 2026-09-25 §6.3): failed
/// defences still awaiting their re-defence, then the re-defences
/// themselves.
class RedefenceStage extends ConsumerWidget {
  const RedefenceStage({super.key, required this.calendar});

  /// Show the scheduled re-defences as the calendar rather than the list.
  final bool calendar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(myDefencesProvider).when(
          loading: () => const LoadingState(label: 'Loading your defences…'),
          error: (e, _) =>
              ErrorState(error: e, message: 'Could not load your defences.'),
          data: (all) {
            final awaiting = awaitingRedefence(all);
            final scheduled = all.any(DefenceStage.redefence.includes);
            if (awaiting.isEmpty && !scheduled) {
              return const EmptyState(
                key: Key('noRedefences'),
                icon: Icons.replay_outlined,
                title: 'No re-defences',
                message: 'A group re-defends a stage when the panel\'s '
                    'verdict on it is Fail.',
              );
            }
            final canSchedule =
                ref.watch(currentUserProvider).valueOrNull?.role ==
                    UserRole.coordinator;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (awaiting.isNotEmpty)
                  Panel(
                    key: const Key('awaitingRedefence'),
                    title: 'Awaiting a re-defence',
                    subtitle: 'The panel\'s verdict on these was Fail',
                    icon: Icons.replay_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final d in awaiting)
                          AwaitingRedefenceRow(
                              failed: d, canSchedule: canSchedule),
                      ],
                    ),
                  ),
                if (awaiting.isNotEmpty && scheduled) const Gap.lg(),
                if (scheduled)
                  calendar
                      ? const DefenceCalendar(
                          where: _isRedefence,
                        )
                      : const DefencesList(where: _isRedefence),
              ],
            );
          },
        );
  }
}

bool _isRedefence(Defence d) => d.isRedefence;

/// One failed defence waiting for its re-defence. The Coordinator schedules
/// it from here; everyone else is told it is coming.
class AwaitingRedefenceRow extends ConsumerWidget {
  const AwaitingRedefenceRow({
    super.key,
    required this.failed,
    required this.canSchedule,
  });

  final Defence failed;
  final bool canSchedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final title =
        ref.watch(thesisByIdProvider(failed.thesisId)).valueOrNull?.workingTitle;
    final at = failed.scheduledAt;
    return Padding(
      key: Key('awaitingRedefence-${failed.id}'),
      padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title == null || title.isEmpty ? 'Untitled thesis' : title,
              style: text.titleMedium),
          const SizedBox(height: 2),
          Text(
            [
              failed.label,
              if (at != null) DefencesList.formatDateTime(at),
              'Verdict: Fail',
            ].join(', '),
            style: text.bodySmall,
          ),
          const Gap.sm(),
          if (canSchedule)
            FilledButton.icon(
              key: Key('scheduleRedefence-${failed.id}'),
              onPressed: () => context
                  .push('/defence/schedule?redefenceOf=${failed.id}'),
              icon: const Icon(Icons.replay_outlined, size: 18),
              label: const Text('Schedule re-defence'),
            )
          else
            Text(
              'Waiting for the Coordinator to schedule the re-defence.',
              key: Key('awaitingRedefenceNote-${failed.id}'),
              style: text.bodySmall,
            ),
        ],
      ),
    );
  }
}
```

  `const DefencesList(where: _isRedefence)` works because a top-level function is a compile-time constant. If `Panel`'s constructor names differ from `title`/`subtitle`/`icon`/`child` (check `lib/core/design/panel.dart`), match its real parameter names.

- [ ] **Step 5: Rewrite `lib/features/defence/defences_screen.dart`:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/features/defence/defence_calendar.dart';
import 'package:ethesishub/features/defence/defence_stage.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/features/defence/redefence_stage.dart';
import 'package:ethesishub/features/defence/title_defence_stage.dart';

enum _DefencesView { list, calendar }

/// The Defences destination, at '/defences?stage=…' (spec 2026-09-25 §6.1).
///
/// A stage switch, styled like the List / Calendar toggle, reads **Title
/// defence | Pre-oral | Final defence | Re-defence**. In the app the stage is
/// part of the URL, so a dashboard or a notification can link straight to
/// one. The router hands it in as [initialStage], and switching stages goes
/// to the new URL. Standing alone (in a test), switching is local state.
///
/// List / Calendar applies to the three stages that have dates. It is not
/// persisted: a stored preference is not warranted for something changed by
/// a single tap.
class DefencesScreen extends ConsumerStatefulWidget {
  const DefencesScreen({
    super.key,
    this.initialStage = DefenceStage.title,
    this.title = 'Defences',
    this.subtitle =
        'Title defences, pre-oral and final defences, and re-defences.',
  });

  final DefenceStage initialStage;
  final String title;
  final String subtitle;

  @override
  ConsumerState<DefencesScreen> createState() => _DefencesScreenState();
}

class _DefencesScreenState extends ConsumerState<DefencesScreen> {
  late DefenceStage _stage = widget.initialStage;
  _DefencesView _view = _DefencesView.list;

  @override
  void didUpdateWidget(covariant DefencesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStage != widget.initialStage) {
      _stage = widget.initialStage;
    }
  }

  void _selectStage(DefenceStage stage) {
    setState(() => _stage = stage);
    // `go`, not `push`: changing tabs is not a step back should undo.
    GoRouter.maybeOf(context)?.go(stage.route);
  }

  @override
  Widget build(BuildContext context) {
    final compact = Breakpoint.of(context) == Breakpoint.compact;
    final counts = ref.watch(defenceStageCountsProvider);
    final calendar = _view == _DefencesView.calendar;

    return PageShell(
      key: const Key('defencesScreen'),
      maxWidth: AppTokens.measureWide,
      title: widget.title,
      subtitle: widget.subtitle,
      actions: [
        // Title defences have no date, so they have no calendar.
        if (_stage != DefenceStage.title)
          SegmentedButton<_DefencesView>(
            key: const Key('defencesViewToggle'),
            segments: const [
              ButtonSegment(
                value: _DefencesView.list,
                label: Text('List'),
                icon: Icon(Icons.view_list_outlined),
              ),
              ButtonSegment(
                value: _DefencesView.calendar,
                label: Text('Calendar'),
                icon: Icon(Icons.calendar_month_outlined),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (selection) =>
                setState(() => _view = selection.first),
          ),
      ],
      children: [
        // Scrolls sideways if even the short labels do not fit, so the page
        // itself never overflows.
        Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<DefenceStage>(
              key: const Key('defenceStageSwitch'),
              segments: [
                for (final s in DefenceStage.values)
                  ButtonSegment(
                    value: s,
                    label: Text(s.labelFor(counts[s] ?? 0, compact: compact)),
                    icon: compact ? null : Icon(s.icon),
                  ),
              ],
              selected: {_stage},
              onSelectionChanged: (selection) =>
                  _selectStage(selection.first),
            ),
          ),
        ),
        const Gap.lg(),
        switch (_stage) {
          DefenceStage.title => const TitleDefenceStage(),
          DefenceStage.redefence => RedefenceStage(calendar: calendar),
          DefenceStage.preOral => calendar
              ? const DefenceCalendar(
                  key: ValueKey('preOralCalendar'), where: _preOral)
              : const DefencesList(
                  key: ValueKey('preOralList'),
                  where: _preOral,
                  emptyTitle: 'No pre-oral defences',
                  emptyMessage: 'A pre-oral defence appears here once the '
                      'Coordinator schedules one you are part of.',
                ),
          DefenceStage.finalDefence => calendar
              ? const DefenceCalendar(
                  key: ValueKey('finalCalendar'), where: _final)
              : const DefencesList(
                  key: ValueKey('finalList'),
                  where: _final,
                  emptyTitle: 'No final defences',
                  emptyMessage: 'A final defence appears here once the '
                      'Coordinator schedules one you are part of.',
                ),
        },
      ],
    );
  }
}

bool _preOral(Defence d) => DefenceStage.preOral.includes(d);
bool _final(Defence d) => DefenceStage.finalDefence.includes(d);
```

  Add `import 'package:ethesishub/data/models/defence.dart';` for `Defence`. If `Breakpoint` or `Gap` live in different files than imported above, fix the imports: `Breakpoint` is in `lib/core/design/layout.dart`, `Gap` in `lib/core/components/document.dart`.

- [ ] **Step 6: Run and watch them pass**

Run: `flutter test test/features/defence/ test/features/dashboard/destination_screens_test.dart`
Expected: PASS, including every pre-existing Defences page test.

- [ ] **Step 7: Commit**

```bash
git add lib/features/defence/title_defence_stage.dart lib/features/defence/redefence_stage.dart lib/features/defence/defences_screen.dart test/features/defence/defences_screen_test.dart test/features/defence/title_defence_stage_test.dart test/features/dashboard/destination_screens_test.dart
git status --short
git commit -m "feat(defence): one Defences page, switched by stage

Title defence, Pre-oral, Final defence and Re-defence, in the style of
the List / Calendar toggle. The title stage lists what each reader can
open, the adviser included; the re-defence stage lists failed defences
awaiting one, with Schedule re-defence for the Coordinator.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Routing and navigation

**Files:**
- Modify: `lib/core/routing/app_router.dart` (the `/defences` builder, the `/title-defences` route and its role guard)
- Modify: `lib/core/navigation/shell_destination.dart` (remove Title defences for Dean and Coordinator)
- Modify: `lib/core/widgets/app_shell_host.dart` (remove the `'/title-defences'` title)
- Modify: `lib/features/dashboard/dean_overview.dart` (the metric's link)
- Delete: `lib/features/dashboard/title_defences_screen.dart`, `lib/features/dashboard/defence_queue.dart`
- Modify: `lib/providers/needs_you_providers.dart` (two doc comments naming `DefenceQueue`)
- Test: `test/core/routing/shell_routes_test.dart`, `test/features/dashboard/destination_screens_test.dart`, `test/core/navigation/shell_destination_test.dart`

**Interfaces:**
- Consumes: Task 5 (`DefenceStage.fromParam`, `DefenceStage.route`); Task 6 (`DefencesScreen(initialStage:)`).

- [ ] **Step 1: Update the tests first.**

  In `test/core/routing/shell_routes_test.dart`:

  - Replace the test `'/title-defences reaches the title defences screen'` with:

```dart
  testWidgets('/title-defences forwards to the Title defence stage',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('dean', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/title-defences');
    await tester.pumpAndSettle();

    expect(locationOf(c), '/defences?stage=title');
    expect(find.byKey(const Key('defencesScreen')), findsOneWidget);
  });

  testWidgets('the stage is read from the URL, and a bad one shows Title',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('faculty', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    Set<Object?> selected() => tester
        .widget<SegmentedButton<Object?>>(
            find.byKey(const Key('defenceStageSwitch')))
        .selected;

    c.read(goRouterProvider).go('/defences?stage=final');
    await tester.pumpAndSettle();
    expect(selected().single.toString(), 'DefenceStage.finalDefence');

    for (final bad in ['FINAL', 'nonsense', '']) {
      c.read(goRouterProvider).go('/defences?stage=$bad');
      await tester.pumpAndSettle();
      expect(selected().single.toString(), 'DefenceStage.title',
          reason: bad);
    }
  });

  testWidgets('choosing a stage puts it in the URL', (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('faculty', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/defences');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Re-defence'));
    await tester.pumpAndSettle();
    expect(locationOf(c), '/defences?stage=redefence');
  });
```

    If `tester.widget<SegmentedButton<Object?>>` fails to find the widget because of its generic type, import `package:ethesishub/features/defence/defence_stage.dart`, use `SegmentedButton<DefenceStage>`, and compare against `DefenceStage.finalDefence` and `DefenceStage.title` directly.

  - In `'/title-defences and /thesis/titles are distinct routes'`, replace `find.byKey(const Key('titleDefencesScreen'))` with `find.byKey(const Key('defencesScreen'))`. Keep the assertion `findsNothing`.
  - In `'no two of the eight routes share a path'`, delete the `'/title-defences': 'titleDefencesScreen',` entry.
  - Replace `'coordinator and dean reach /title-defences and /readiness'` with a test that keeps only its `/readiness` half, renamed `'coordinator and dean reach /readiness'`.
  - Replace `'student and faculty are redirected home from /title-defences and /readiness'` with:
    - `'student and faculty are redirected home from /readiness'`, keeping only its `/readiness` half;
    - a new test, `'every role reaching /title-defences lands on the Title stage'`. It loops over `['student', 'faculty', 'coordinator', 'dean']` and asserts `locationOf(c) == '/defences?stage=title'` after `go('/title-defences')`.

  In `test/features/dashboard/destination_screens_test.dart`, delete the test `'title defences screen renders the defence queue standalone'` and the import of `title_defences_screen.dart`.

  In `test/core/navigation/shell_destination_test.dart`, add:

```dart
  test('the Dean and the Coordinator reach title defences through Defences',
      () {
    for (final role in [UserRole.dean, UserRole.coordinator]) {
      final routes = destinationsFor(role: role).map((d) => d.route);
      expect(routes, isNot(contains('/title-defences')), reason: '$role');
      expect(routes, contains('/defences'), reason: '$role');
    }
  });
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/core/routing/shell_routes_test.dart test/core/navigation/shell_destination_test.dart test/features/dashboard/destination_screens_test.dart`
Expected: the new redirect, stage and sidebar tests FAIL.

- [ ] **Step 3: Implement.**

  In `lib/core/routing/app_router.dart`:
  - Import `package:ethesishub/features/defence/defence_stage.dart`, and remove the `title_defences_screen.dart` import.
  - Replace `GoRoute(path: '/defences', builder: (_, _) => const DefencesScreen()),` with:

```dart
      GoRoute(
        path: '/defences',
        builder: (_, state) => DefencesScreen(
          initialStage:
              DefenceStage.fromParam(state.uri.queryParameters['stage']),
        ),
      ),
```

  - Replace the `/title-defences` `GoRoute` (keep its comment about `/thesis/titles`) with:

```dart
      // Kept so old links and bookmarks still work: title defences are now
      // the Title stage of the Defences page (spec 2026-09-25 §6.7).
      GoRoute(
        path: '/title-defences',
        redirect: (_, _) => DefenceStage.title.route,
      ),
```

  - In the role guard, change `if ((location == '/title-defences' || location == '/readiness') && …` to `if (location == '/readiness' && …`. Update its comment so it speaks only of `/readiness`.

  In `lib/core/navigation/shell_destination.dart`, delete both `ShellDestination(label: 'Title defences', …, route: '/title-defences')` entries, the Dean's and the Coordinator's.

  In `lib/core/widgets/app_shell_host.dart`, delete the line `'/title-defences': 'Title defences',`.

  In `lib/features/dashboard/dean_overview.dart`, change `onTap: () => context.go('/title-defences'),` to `onTap: () => context.go('/defences?stage=title'),`.

  Delete `lib/features/dashboard/title_defences_screen.dart` and `lib/features/dashboard/defence_queue.dart`. Then run `grep -rn "DefenceQueue\|TitleDefencesScreen\|defence_queue.dart\|title_defences_screen.dart" lib test`, and fix every remaining reference. In `lib/providers/needs_you_providers.dart` the two doc comments say `(see \`DefenceQueue\`)`; change each to `(see \`TitleDefenceStage\`)`.

- [ ] **Step 4: Run and watch them pass**

Run: `flutter test test/core/ test/features/dashboard/ test/features/defence/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/routing/app_router.dart lib/core/navigation/shell_destination.dart lib/core/widgets/app_shell_host.dart lib/features/dashboard/dean_overview.dart lib/providers/needs_you_providers.dart test/core/routing/shell_routes_test.dart test/core/navigation/shell_destination_test.dart test/features/dashboard/destination_screens_test.dart
git rm lib/features/dashboard/title_defences_screen.dart lib/features/dashboard/defence_queue.dart
git status --short
git commit -m "feat(nav): title defences live on the Defences page

/defences reads its stage from ?stage=; /title-defences forwards to
the Title stage, and the separate sidebar entry is gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Scheduling a re-defence

**Files:**
- Create: `lib/features/defence/defence_date_picker.dart`
- Create: `lib/features/defence/schedule_redefence_screen.dart`
- Modify: `lib/features/defence/schedule_defence_screen.dart` (use the shared picker; add the advisory notice)
- Modify: `lib/core/routing/app_router.dart` (the `/defence/schedule` builder)
- Test: `test/features/defence/schedule_redefence_screen_test.dart` (new)
- Test: `test/features/defence/schedule_defence_screen_test.dart` (add one test)

**Interfaces:**
- Consumes: Task 1 (`hasRedefence`, `Defence.label`, `isRedefence`); Task 2 (`scheduleRedefence`); `defenceProvider(String)` (`StreamProvider.family<Defence?, String>`); `myDefencesProvider`; `thesisByIdProvider`; `currentUserProvider`; `DefencesList.formatDateTime`.
- Produces:
  - `Future<DateTime?> pickDefenceDateTime(BuildContext context, DateTime initial)`.
  - `ScheduleRedefenceScreen({required String failedDefenceId})`.
  - Keys: `scheduleRedefenceScreen`, `redefenceOfSummary`, `redefenceDate`, `redefenceVenue`, `scheduleRedefenceButton`, `cannotRedefend`, `redefenceError`, `scheduleRedefenceInstead`.

- [ ] **Step 1: Write the failing tests.** Create `test/features/defence/schedule_redefence_screen_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/features/defence/schedule_redefence_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seed({
  String role = 'coordinator',
  String verdict = 'fail',
  String? redefenceOf,
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('c1').set({
    'fullName': 'Coordinator',
    'email': 'c1@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1',
    'panelistUids': <String>['p1', 'p2'],
    'memberNames': <String>[], 'workingTitle': 'Mangrove Carbon Stocks',
    'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
    'academicYear': '2026-2027', 'status': 'titleApproved',
  });
  await db.collection('defenses').doc('f1').set({
    'thesisId': 't1', 'type': 'final',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 1, 9)),
    'venue': 'AVR', 'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1', 'leaderUid': 'l1', 'status': 'completed',
    'createdBy': 'c1', 'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    'panelVerdict': verdict,
    if (redefenceOf != null) 'redefenceOf': redefenceOf,
  });
  return db;
}

Future<GoRouter> pump(WidgetTester tester, FakeFirebaseFirestore db) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/s',
    routes: [
      GoRoute(
        path: '/s',
        builder: (_, _) => const Scaffold(
            body: ScheduleRedefenceScreen(failedDefenceId: 'f1')),
      ),
      GoRoute(
        path: '/defence/room/:id',
        builder: (_, s) =>
            Scaffold(body: Text('room ${s.pathParameters['id']}')),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'c1', email: 'c1@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('says which defence is re-defended, and schedules it',
      (tester) async {
    final db = await seed();
    await pump(tester, db);

    expect(find.byKey(const Key('redefenceOfSummary')), findsOneWidget);
    expect(find.textContaining('Re-defence of the final defence held'),
        findsOneWidget);

    await tester.enterText(find.byKey(const Key('redefenceVenue')), 'AVR 2');
    await tester.tap(find.byKey(const Key('scheduleRedefenceButton')));
    await tester.pumpAndSettle();

    final again = await db.doc('defenses/f1_redefence').get();
    expect(again.exists, isTrue);
    expect(again.data()!['redefenceOf'], 'f1');
    expect(again.data()!['type'], 'final');
    expect(find.text('room f1_redefence'), findsOneWidget);
  });

  testWidgets('a passed defence cannot be re-defended', (tester) async {
    final db = await seed(verdict: 'pass');
    await pump(tester, db);
    expect(find.byKey(const Key('cannotRedefend')), findsOneWidget);
    expect(find.byKey(const Key('scheduleRedefenceButton')), findsNothing);
  });

  testWidgets('a re-defence cannot be re-defended', (tester) async {
    final db = await seed(redefenceOf: 'f0');
    await pump(tester, db);
    expect(find.byKey(const Key('cannotRedefend')), findsOneWidget);
  });

  testWidgets('a defence already re-defended cannot be again',
      (tester) async {
    final db = await seed();
    await db.doc('defenses/f1_redefence').set({
      ...(await db.doc('defenses/f1').get()).data()!,
      'status': 'scheduled',
      'redefenceOf': 'f1',
    });
    await pump(tester, db);
    expect(find.byKey(const Key('cannotRedefend')), findsOneWidget);
  });

  testWidgets('a blank venue is refused with the reason', (tester) async {
    final db = await seed();
    await pump(tester, db);
    await tester.tap(find.byKey(const Key('scheduleRedefenceButton')));
    await tester.pumpAndSettle();
    expect(find.text('Give the re-defence a venue.'), findsOneWidget);
  });

  testWidgets('only the Coordinator gets the button', (tester) async {
    final db = await seed(role: 'faculty');
    await pump(tester, db);
    expect(find.byKey(const Key('scheduleRedefenceButton')), findsNothing);
    expect(find.text('Only the Research Coordinator can schedule defences.'),
        findsOneWidget);
  });
}
```

  In `test/features/defence/schedule_defence_screen_test.dart`, add a test using that file's own setup helpers. Seed, for the thesis it schedules, a `defenses` document of type `preOral` with `status: 'completed'` and `panelVerdict: 'fail'`. With `Pre-oral defence` selected (the default), expect `find.byKey(const Key('scheduleRedefenceInstead'))` to find one widget. Tap the `Final defence` segment, and expect it to find nothing.

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/features/defence/schedule_redefence_screen_test.dart test/features/defence/schedule_defence_screen_test.dart`
Expected: compile error; the screen does not exist.

- [ ] **Step 3: Create `lib/features/defence/defence_date_picker.dart`:**

```dart
import 'package:flutter/material.dart';

/// A date, then a time, for a defence. Null if either picker is dismissed or
/// the screen goes away mid-pick. Shared by the defence and re-defence
/// scheduling screens.
Future<DateTime?> pickDefenceDateTime(
    BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(DateTime.now().year - 1),
    lastDate: DateTime(DateTime.now().year + 2),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null || !context.mounted) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
```

  In `schedule_defence_screen.dart`, replace the body of `_pickDateTime` with:

```dart
  Future<void> _pickDateTime() async {
    final picked = await pickDefenceDateTime(context, _scheduledAt);
    if (picked == null || !mounted) return;
    setState(() => _scheduledAt = picked);
  }
```

  Add the import `package:ethesishub/features/defence/defence_date_picker.dart`.

- [ ] **Step 4: Add the advisory notice to `ScheduleDefenceScreen`.** In `build`, before the `Panel(title: 'Chapter readiness', …)`, add:

```dart
          // A plain defence of a kind this group already failed is almost
          // always meant to be the re-defence (spec 2026-09-25 §6.4). The
          // rules cannot refuse it, so the screen points the way instead.
          ...() {
            final failed = awaitingRedefence(
                    ref.watch(myDefencesProvider).valueOrNull ?? const [])
                .where((d) => d.thesisId == thesis.id && d.type == _type)
                .firstOrNull;
            if (failed == null) return const <Widget>[];
            final at = failed.scheduledAt;
            return [
              Panel(
                key: const Key('scheduleRedefenceInstead'),
                icon: Icons.replay_outlined,
                title: 'This group failed its ${failed.type.label.toLowerCase()}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(at == null
                        ? 'Schedule a re-defence instead.'
                        : 'Held ${DefencesList.formatDateTime(at)}. '
                            'Schedule a re-defence instead.'),
                    const Gap.sm(),
                    FilledButton.tonal(
                      onPressed: () => context.push(
                          '/defence/schedule?redefenceOf=${failed.id}'),
                      child: const Text('Schedule re-defence'),
                    ),
                  ],
                ),
              ),
              const Gap.md(),
            ];
          }(),
```

  Add the imports for `defences_list.dart` (for `formatDateTime`) and, if `firstOrNull` is not in scope, `package:collection/collection.dart`. It is in `dart:core` from Dart 3, so it normally needs no import. `awaitingRedefence` comes from `defence.dart`, which is already imported.

- [ ] **Step 5: Create `lib/features/defence/schedule_redefence_screen.dart`:**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/defence/defence_date_picker.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The Coordinator's screen for the one re-defence of a failed defence
/// (spec 2026-09-25 §6.4), at '/defence/schedule?redefenceOf=<id>'.
///
/// The kind, thesis and panel come from the failed defence; only the date,
/// time and venue are asked.
class ScheduleRedefenceScreen extends ConsumerStatefulWidget {
  const ScheduleRedefenceScreen({super.key, required this.failedDefenceId});

  final String failedDefenceId;

  @override
  ConsumerState<ScheduleRedefenceScreen> createState() =>
      _ScheduleRedefenceScreenState();
}

class _ScheduleRedefenceScreenState
    extends ConsumerState<ScheduleRedefenceScreen> {
  final _venue = TextEditingController();
  late DateTime _scheduledAt;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _scheduledAt = DateTime(now.year, now.month, now.day + 7, 9);
  }

  @override
  void dispose() {
    _venue.dispose();
    super.dispose();
  }

  Future<void> _schedule(Defence failed, String uid) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(defenceRepositoryProvider).scheduleRedefence(
            failed: failed,
            scheduledAt: _scheduledAt,
            venue: _venue.text,
            createdBy: uid,
          );
      if (mounted) context.push('/defence/room/$id');
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = e.message.toString());
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FirebaseException catch (e) {
      // Most often: the thesis panel changed since the Fail, so the copied
      // panel no longer matches and the rules refuse the re-defence.
      if (mounted) {
        setState(() => _error = e.code == 'permission-denied'
            ? 'You do not have permission to schedule this re-defence. '
                'If the panel changed since the defence, the re-defence '
                'cannot use the old one [permission-denied].'
            : 'Could not schedule this re-defence. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not schedule this re-defence. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _framed(List<Widget> children) => KeyedSubtree(
        key: const Key('scheduleRedefenceScreen'),
        child: PageShell(
          kicker: 'Research office',
          title: 'Schedule a re-defence',
          children: children,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final failedAsync = ref.watch(defenceProvider(widget.failedDefenceId));
    final allAsync = ref.watch(myDefencesProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;

    if (failedAsync.isLoading || allAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading the defence…')]);
    }
    if (failedAsync.hasError || allAsync.hasError) {
      return _framed([
        ErrorState(
          error: failedAsync.error ?? allAsync.error,
          message: 'Could not load this defence.',
        ),
      ]);
    }
    final failed = failedAsync.valueOrNull;
    if (failed == null) {
      return _framed(const [
        EmptyState(
          icon: Icons.search_off,
          title: 'Defence not found',
          message: 'This defence no longer exists.',
        ),
      ]);
    }

    final String? refusal = failed.panelVerdict != PassFail.fail
        ? 'Only a defence the panel failed can be re-defended.'
        : failed.isRedefence
            ? 'This was already the group\'s re-defence of this stage.'
            : hasRedefence(failed, allAsync.value ?? const [])
                ? 'This defence already has its re-defence.'
                : null;
    if (refusal != null) {
      return _framed([
        EmptyState(
          key: const Key('cannotRedefend'),
          icon: Icons.block_outlined,
          title: 'This defence cannot be re-defended',
          message: refusal,
        ),
      ]);
    }

    final thesisTitle =
        ref.watch(thesisByIdProvider(failed.thesisId)).valueOrNull?.workingTitle;
    final at = failed.scheduledAt;
    final isCoordinator = me?.role == UserRole.coordinator;

    return _framed([
      if (thesisTitle != null && thesisTitle.isNotEmpty) ...[
        Text(thesisTitle, style: Theme.of(context).textTheme.titleMedium),
        const Gap.sm(),
      ],
      Panel(
        title: 'Session',
        icon: Icons.replay_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Re-defence of the ${failed.type.label.toLowerCase()} held '
              '${at == null ? 'on a date not recorded' : DefencesList.formatDateTime(at)}',
              key: const Key('redefenceOfSummary'),
            ),
            const Gap.md(),
            FormRow(
              label: 'Date and time',
              child: InkWell(
                key: const Key('redefenceDate'),
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final picked =
                      await pickDefenceDateTime(context, _scheduledAt);
                  if (picked != null && mounted) {
                    setState(() => _scheduledAt = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.schedule_rounded),
                    suffixIcon: Icon(Icons.edit_calendar_outlined),
                  ),
                  child: Text(DefencesList.formatDateTime(_scheduledAt)),
                ),
              ),
            ),
            FormRow(
              label: 'Venue',
              child: TextField(
                key: const Key('redefenceVenue'),
                controller: _venue,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                  hintText: 'Room or online link',
                ),
              ),
            ),
          ],
        ),
      ),
      const Gap.lg(),
      if (_error != null) ...[
        ErrorState(key: const Key('redefenceError'), message: _error!),
        const Gap.md(),
      ],
      if (isCoordinator)
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('scheduleRedefenceButton'),
            onPressed:
                _busy || uid == null ? null : () => _schedule(failed, uid),
            icon: const Icon(Icons.replay_outlined, size: 18),
            label: Text(_busy ? 'Scheduling…' : 'Schedule re-defence'),
          ),
        )
      else
        Text('Only the Research Coordinator can schedule defences.',
            style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
```

  `FormRow` is in `lib/core/components/document.dart`, as `ScheduleDefenceScreen` uses it. The blank-venue refusal text comes from Task 2's `ArgumentError`. The test expects the message `'Give the re-defence a venue.'`, rendered by `ErrorState(message: _error!)`.

- [ ] **Step 6: Route it.** In `lib/core/routing/app_router.dart`, in the `/defence/schedule` builder, add these lines first:

```dart
          final redefenceOf = state.uri.queryParameters['redefenceOf'];
          if (redefenceOf != null && redefenceOf.isNotEmpty) {
            return ScheduleRedefenceScreen(failedDefenceId: redefenceOf);
          }
```

  Add `import 'package:ethesishub/features/defence/schedule_redefence_screen.dart';`.

- [ ] **Step 7: Run and watch them pass**

Run: `flutter test test/features/defence/ test/core/routing/`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/defence/defence_date_picker.dart lib/features/defence/schedule_redefence_screen.dart lib/features/defence/schedule_defence_screen.dart lib/core/routing/app_router.dart test/features/defence/schedule_redefence_screen_test.dart test/features/defence/schedule_defence_screen_test.dart
git status --short
git commit -m "feat(defence): the Coordinator schedules a re-defence

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Failed-defence prompts, re-defence headings, and the adviser's title defence link

**Files:**
- Create: `lib/features/defence/redefence_notice.dart`
- Modify: `lib/features/defence/defence_room_screen.dart` (the leader verdict; the headings; the link to the original)
- Modify: `lib/features/defence/defence_grades_screen.dart` (the verdict block; the heading)
- Modify: `lib/features/dashboard/advisees_screen.dart` (Open title defence)
- Test: `test/features/defence/redefence_notice_test.dart` (new)
- Test: `test/features/defence/defence_room_screen_test.dart` (add one test)
- Test: `test/features/dashboard/destination_screens_test.dart` (add one test)

**Interfaces:**
- Consumes: Task 1 (`hasRedefence`, `Defence.label`, `isRedefence`, `redefenceOf`); `myDefencesProvider`; `currentUserProvider`.
- Produces: `RedefenceNotice({required Defence defence})`. Keys: `scheduleRedefence`, `redefencePending`, `redefenceOfLink`, `openTitleDefence-<thesisId>`.

- [ ] **Step 1: Write the failing tests.** Create `test/features/defence/redefence_notice_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/features/defence/redefence_notice.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Defence failed({PassFail? verdict = PassFail.fail, String? redefenceOf}) =>
    Defence(
      id: 'f1', thesisId: 't1', type: DefenceType.preOral, venue: 'AVR',
      panelUids: const ['p1'], adviserUid: 'a1', leaderUid: 'l1',
      status: DefenceStatus.completed, createdBy: 'c1',
      panelVerdict: verdict, redefenceOf: redefenceOf,
    );

Future<void> pump(WidgetTester tester, Defence d,
    {String uid = 'c1', String role = 'coordinator',
    bool alreadyRedefended = false}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(uid).set({
    'fullName': 'U', 'email': '$uid@isufst.edu.ph', 'role': role,
    'active': true,
  });
  if (alreadyRedefended) {
    await db.doc('defenses/f1_redefence').set({
      'thesisId': 't1', 'type': 'preOral',
      'scheduledAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      'venue': 'AVR', 'panelUids': ['p1'], 'adviserUid': 'a1',
      'leaderUid': 'l1', 'status': 'scheduled', 'createdBy': 'c1',
      'redefenceOf': 'f1',
    });
  }
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: MaterialApp(home: Scaffold(body: RedefenceNotice(defence: d))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Coordinator is offered the re-defence of a Fail',
      (tester) async {
    await pump(tester, failed());
    expect(find.byKey(const Key('scheduleRedefence')), findsOneWidget);
  });

  testWidgets('the adviser is told a re-defence is to be scheduled',
      (tester) async {
    await pump(tester, failed(), uid: 'a1', role: 'faculty');
    expect(find.byKey(const Key('scheduleRedefence')), findsNothing);
    expect(find.byKey(const Key('redefencePending')), findsOneWidget);
  });

  testWidgets('nothing once the re-defence exists', (tester) async {
    await pump(tester, failed(), alreadyRedefended: true);
    expect(find.byKey(const Key('scheduleRedefence')), findsNothing);
    expect(find.byKey(const Key('redefencePending')), findsNothing);
  });

  testWidgets('nothing for a pass, no verdict, or a failed re-defence',
      (tester) async {
    for (final d in [
      failed(verdict: PassFail.pass),
      failed(verdict: null),
      failed(redefenceOf: 'f0'),
    ]) {
      await pump(tester, d);
      expect(find.byKey(const Key('scheduleRedefence')), findsNothing);
      expect(find.byKey(const Key('redefencePending')), findsNothing);
    }
  });
}
```

  In `test/features/defence/defence_room_screen_test.dart`, add a test with that file's own setup. Seed a defence whose id is `d1_redefence` with `'redefenceOf': 'd1'` and `type: 'preOral'`, and open it as the adviser. Expect `find.text('Pre-oral re-defence')` to find at least one widget (the kicker) and `find.byKey(const Key('redefenceOfLink'))` to find one widget.

  In `test/features/dashboard/destination_screens_test.dart`, add:

```dart
  testWidgets('an adviser opens an advisee\'s title defence from Advisees',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(
          thesis(adviserUid: 'f1', status: 'titlePendingDefence'),
        );

    await tester.pumpWidget(await wrap(
      const AdviseesScreen(),
      db,
      uid: 'f1',
      role: 'faculty',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('openTitleDefence-t1')), findsOneWidget);
    expect(find.text('Open title defence'), findsOneWidget);
  });
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/features/defence/redefence_notice_test.dart test/features/defence/defence_room_screen_test.dart test/features/dashboard/destination_screens_test.dart`
Expected: compile error and failures.

- [ ] **Step 3: Create `lib/features/defence/redefence_notice.dart`:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Under a Fail verdict with no re-defence yet (spec 2026-09-25 §6.5): the
/// Coordinator's way to schedule it, or, for everyone else, word that it is
/// coming.
///
/// Whether the re-defence exists is read from the reader's own defence
/// list, never by fetching the derived id: the rules deny `get` on a
/// missing defence document.
class RedefenceNotice extends ConsumerWidget {
  const RedefenceNotice({super.key, required this.defence});

  final Defence defence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (defence.panelVerdict != PassFail.fail || defence.isRedefence) {
      return const SizedBox.shrink();
    }
    final all = ref.watch(myDefencesProvider).valueOrNull;
    // Until the list arrives, say nothing, rather than offer a re-defence
    // that may already exist.
    if (all == null || hasRedefence(defence, all)) {
      return const SizedBox.shrink();
    }
    final isCoordinator = ref.watch(currentUserProvider).valueOrNull?.role ==
        UserRole.coordinator;
    if (isCoordinator) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const Key('scheduleRedefence'),
          onPressed: () =>
              context.push('/defence/schedule?redefenceOf=${defence.id}'),
          icon: const Icon(Icons.replay_outlined, size: 18),
          label: const Text('Schedule re-defence'),
        ),
      );
    }
    return const Text(
      'A re-defence of this stage is to be scheduled.',
      key: Key('redefencePending'),
    );
  }
}
```

- [ ] **Step 4: Wire it in.**

  In `lib/features/defence/defence_room_screen.dart`:
  - In the leader branch, directly after the `Text('Panel verdict: …', key: const Key('leaderVerdict'), …)` inside `if (defence.hasVerdict)`, turn the `if/else` into:

```dart
                if (defence.hasVerdict) ...[
                  Text(
                    'Panel verdict: ${defence.panelVerdict!.label}',
                    key: const Key('leaderVerdict'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Gap.sm(),
                  RedefenceNotice(defence: defence),
                ] else
```

    Keep the existing `else` text.
  - In the final `PageShell`, change `kicker: defence.type.label,` and `title: thesisTitle ?? defence.type.label,` to use `defence.label`.
  - At the start of its `children`, add:

```dart
          if (defence.isRedefence) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('redefenceOfLink'),
                onPressed: () =>
                    context.push('/defence/room/${defence.redefenceOf}'),
                icon: const Icon(Icons.history, size: 18),
                label: Text('Re-defence of an earlier '
                    '${defence.type.label.toLowerCase()}. Open the original'),
              ),
            ),
            const Gap.sm(),
          ],
```

  - Import `redefence_notice.dart`.

  In `lib/features/defence/defence_grades_screen.dart`:
  - In `_verdictBlock`'s `if (defence.hasVerdict)` branch, append `const Gap.md(), RedefenceNotice(defence: defence),` as the last two entries of the returned list.
  - Change `title: defence.type.label` in `build` to `title: defence.label`.
  - Import `redefence_notice.dart`.

  In `lib/features/dashboard/advisees_screen.dart`, in `AdviseeRow.build`:
  - Add `import 'package:ethesishub/data/models/thesis_status.dart';` if it is not already imported.
  - Replace `void open() => context.push('/thesis/chapters?id=${thesis.id}');` with:

```dart
    // At title defence there are no chapters yet; the defence is the work.
    final atTitleDefence = thesis.status == ThesisStatus.titlePendingDefence;
    void open() => context.push(atTitleDefence
        ? '/defence/${thesis.id}'
        : '/thesis/chapters?id=${thesis.id}');
```

  - Replace the `button` definition with:

```dart
          final button = atTitleDefence
              ? FilledButton(
                  key: Key('openTitleDefence-${thesis.id}'),
                  onPressed: open,
                  child: const Text('Open title defence'),
                )
              : FilledButton.tonal(
                  key: Key('openChapters-${thesis.id}'),
                  // No faculty destination owns '/thesis/chapters', so it is
                  // pushed, leaving this list as the back stop (D23).
                  onPressed: open,
                  child: const Text('Review chapters'),
                );
```

- [ ] **Step 5: Run and watch them pass**

Run: `flutter test test/features/defence/ test/features/dashboard/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/defence/redefence_notice.dart lib/features/defence/defence_room_screen.dart lib/features/defence/defence_grades_screen.dart lib/features/dashboard/advisees_screen.dart test/features/defence/redefence_notice_test.dart test/features/defence/defence_room_screen_test.dart test/features/dashboard/destination_screens_test.dart
git status --short
git commit -m "feat(defence): a failed defence points to its re-defence

The room and grades pages offer the Coordinator the re-defence of a
Fail and tell everyone else it is coming; a re-defence is named as one
and links to the original. Advisees at title defence open it directly.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Whole-suite verification

**Files:** none changed unless a check fails.

- [ ] **Step 1:** Run `flutter test`. Expected: `All tests passed!`. One unrelated test, `evaluation_repository_test.dart` "a second submit edits the same document", has flaked under load. If it alone fails, re-run once and report both runs.
- [ ] **Step 2:** Run `flutter analyze`. Expected: no issues in any file this plan created or changed.
- [ ] **Step 3:** Run `cd rules-test && npm test`. Expected: all pass.
- [ ] **Step 4:** Run `grep -rn "title-defences" lib`. Expected: only the redirect route and its comment in `app_router.dart`.
- [ ] **Step 5: Report; no commit.**
  - The user must deploy `firestore.rules`. There is no data migration: existing defences have no `redefenceOf`.
  - Rebuild the APK.
  - On a device:
    - an adviser in adviser mode sees their advisee's title defence under Defences → Title defence, and on Advisees;
    - a failed defence (Coordinator) shows Schedule re-defence;
    - the stage switch fits on the phone.
