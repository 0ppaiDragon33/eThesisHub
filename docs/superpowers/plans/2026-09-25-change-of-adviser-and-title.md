# Change of Adviser and Change of Title Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A paperless in-app workflow for Form 4a (change of adviser) and Form 4b (change of title): the group leader submits, the named advisers then the Coordinator then the Dean sign off, and the Dean's approval changes the thesis.

**Architecture:** Each request is one document at `theses/{thesisId}/changeRequests/{type}` (`type` is `adviser` or `title`), modelled on nominations. A `stage` field runs the chain; a `signoffs` map holds each approver's accept/decline. A transaction advances the stage as sign-offs land; the Dean's approval is a batch that writes the final sign-off and the thesis change together. Security rules under `match /theses/{thesisId}` reuse its helpers.

**Tech Stack:** Flutter 3.44, Riverpod 2.6.1 (pinned), go_router 17.5.0 (pinned), Cloud Firestore with `firestore.rules` (emulator-tested: `cd rules-test && npm test`), fake_cloud_firestore 4.2.0 for Dart tests, the `pdf`/`printing` packages.

**Spec:** `docs/superpowers/specs/2026-09-25-change-of-adviser-and-title-design.md`

## Global Constraints

- **Commit only the files your task names.** The working tree has unrelated uncommitted changes. Never stage or edit these:
  `android/app/src/main/kotlin/com/example/ethesishub/MainActivity.kt`, `lib/app.dart`, `lib/core/theme/app_theme.dart`, `lib/core/widgets/app_shell.dart`, `lib/features/dashboard/progress_rail.dart`, `lib/features/defence/consolidated_defence_screen.dart`, `lib/features/forms/form_chrome.dart`, `lib/core/platform/native_back.dart`, `test/core/platform/`, the deleted `double_back_to_exit` files, `macos/…`, `android/build/`.
  Never `git add -A`, `git add .`, or `git commit -a`. Stage by explicit path; run `git status --short` before every commit.
- **Stored strings are exact and never change once shipped:** the collection `changeRequests`; the ids `adviser` and `title`; the type values `adviser`/`title`; the stage values `pendingAdvisers`, `pendingAdviser`, `pendingCoordinator`, `pendingDean`, `approved`, `returned`; the sign-off status values `pending`/`accepted`/`declined`; the sign-off role keys `newAdviser`, `formerAdviser`, `adviser`, `coordinator`, `dean`.
- **Never throw inside a `runTransaction` closure** — it crashes on Android (`MissingPluginException` on cancel). Return the failure and throw it outside the closure (see `respondToNomination`).
- The rules gate coarsely (`status == 'titleApproved'`, leader identity); the screen gates the finer defence-state eligibility.
- A request document is reused per type: a fresh first-pending request may be written only when it is absent, `returned`, or `approved` — never while any pending stage is open.
- The Dean's approval writes the final sign-off **and** the thesis change in one batch; each half is denied on its own.
- No new dependencies. User-facing wording in this plan is final copy; use it verbatim.
- Every commit message ends with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Dart tests: `flutter test <path>`. Rules tests: `cd rules-test && npm test` (needs the Firebase CLI and Java; if the emulator cannot start, say so — do not skip silently).
- Run `dart format` only on files your task creates; keep edits to existing files in their local style.

## Review Focus

1. **A stale approver tab.** Two approvers act at once, or one acts after the stage moved: the second write must be refused by the rules and surfaced as a plain message, not advance the request twice. Pinned in Task 2 (rules) and Task 3 (repository).
2. **A resubmit that smuggles in a change of type or thesis.** A `returned` adviser request resubmitted as a title request, or with a different `leaderUid`, must be refused. Pinned in Task 2.
3. **The Dean's approval batch with only one half.** Writing the request `approved` without the thesis change, or the thesis change without the request write, must each be denied. Pinned in Task 2.
6. **A sign-off write that also tampers with another role's sign-off.** An adviser accepting must not, in the same write, set the coordinator's or dean's sign-off. Each write changes only its own role's entry. Pinned in Task 2 (the `onlyOwnSignoff` guard and its test).
4. **The former adviser equals the new adviser, or the new adviser is the current one.** A change of adviser to the same person, or naming the current adviser as "new", is a no-op the screen must refuse. Pinned in Task 5.
5. **A thesis that leaves `titleApproved` mid-request** (archived, or a title-decision replay). An open request whose thesis is no longer `titleApproved` must not apply on approval. Pinned in Task 3 (the approve transaction re-reads the thesis status).

---

### Task 1: The ChangeRequest model

**Files:**
- Create: `lib/data/models/change_request.dart`
- Test: `test/data/models/change_request_test.dart`

**Interfaces:**
- Produces:
  - `enum ChangeRequestType { adviser, title }` with `value`/`fromString`, and `id` (equals `value`).
  - `enum SignoffStatus { pending, accepted, declined }` with `value`/`fromString`.
  - `enum ChangeRequestStage { pendingAdvisers, pendingAdviser, pendingCoordinator, pendingDean, approved, returned }` with `value`/`fromString`.
  - `class Signoff { final SignoffStatus status; final DateTime? respondedAt; final String? reason; }` with `fromMap`/`toMap`.
  - `class ChangeRequest` (fields per spec §4.1) with `fromMap(String id, Map)`, `toMap()`.
  - `List<String> signoffRolesFor(ChangeRequestType)` → `['newAdviser','formerAdviser','coordinator','dean']` or `['adviser','coordinator','dean']`.
  - `ChangeRequestStage firstStageFor(ChangeRequestType)` → `pendingAdvisers` or `pendingAdviser`.
  - `ChangeRequestStage? nextStage(ChangeRequestStage)` → the next stage in order, or null past `pendingDean`.
  - `bool isOpen` on `ChangeRequest` → the stage is a pending one.

- [ ] **Step 1: Write the failing tests.** Create `test/data/models/change_request_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/change_request.dart';

void main() {
  test('the enums round-trip and default safely', () {
    expect(ChangeRequestType.adviser.value, 'adviser');
    expect(ChangeRequestType.title.id, 'title');
    expect(ChangeRequestType.fromString('title'), ChangeRequestType.title);
    expect(ChangeRequestType.fromString('nope'), isNull);
    expect(SignoffStatus.fromString('accepted'), SignoffStatus.accepted);
    expect(SignoffStatus.fromString(null), SignoffStatus.pending);
    expect(ChangeRequestStage.fromString('pendingDean'),
        ChangeRequestStage.pendingDean);
    expect(ChangeRequestStage.fromString('junk'), isNull);
  });

  test('the roles and first stage differ by type', () {
    expect(signoffRolesFor(ChangeRequestType.adviser),
        ['newAdviser', 'formerAdviser', 'coordinator', 'dean']);
    expect(signoffRolesFor(ChangeRequestType.title),
        ['adviser', 'coordinator', 'dean']);
    expect(firstStageFor(ChangeRequestType.adviser),
        ChangeRequestStage.pendingAdvisers);
    expect(firstStageFor(ChangeRequestType.title),
        ChangeRequestStage.pendingAdviser);
  });

  test('nextStage walks the chain and stops at the Dean', () {
    expect(nextStage(ChangeRequestStage.pendingAdvisers),
        ChangeRequestStage.pendingCoordinator);
    expect(nextStage(ChangeRequestStage.pendingAdviser),
        ChangeRequestStage.pendingCoordinator);
    expect(nextStage(ChangeRequestStage.pendingCoordinator),
        ChangeRequestStage.pendingDean);
    expect(nextStage(ChangeRequestStage.pendingDean), isNull);
  });

  test('an adviser request parses its stored shape', () {
    final r = ChangeRequest.fromMap('adviser', {
      'type': 'adviser',
      'stage': 'pendingAdvisers',
      'reasons': 'The adviser moved campus.',
      'leaderUid': 'l1',
      'newAdviserUid': 'a2',
      'newAdviserName': 'Dr. New',
      'formerAdviserUid': 'a1',
      'formerAdviserName': 'Dr. Old',
      'signoffs': {
        'newAdviser': {'status': 'pending'},
        'formerAdviser': {'status': 'accepted'},
        'coordinator': {'status': 'pending'},
        'dean': {'status': 'pending'},
      },
    });
    expect(r.type, ChangeRequestType.adviser);
    expect(r.stage, ChangeRequestStage.pendingAdvisers);
    expect(r.newAdviserUid, 'a2');
    expect(r.formerAdviserName, 'Dr. Old');
    expect(r.signoffs['formerAdviser']!.status, SignoffStatus.accepted);
    expect(r.isOpen, isTrue);
  });

  test('an approved request is not open', () {
    final r = ChangeRequest.fromMap('title', {
      'type': 'title',
      'stage': 'approved',
      'reasons': 'x',
      'leaderUid': 'l1',
      'newTitle': 'A Better Title',
      'signoffs': const {},
    });
    expect(r.isOpen, isFalse);
    expect(r.newTitle, 'A Better Title');
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/data/models/change_request_test.dart`
Expected: compile error — `change_request.dart` does not exist.

- [ ] **Step 3: Create `lib/data/models/change_request.dart`:**

```dart
/// Which change a request asks for. The value is also the document id, so a
/// thesis holds at most one request of each kind (spec 2026-09-25 §4.1).
enum ChangeRequestType {
  adviser,
  title;

  String get value => name;
  String get id => name;

  static ChangeRequestType? fromString(String? raw) {
    for (final t in values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}

/// One approver's answer. Defaults to `pending` — the safe state that grants
/// nothing and blocks the stage.
enum SignoffStatus {
  pending,
  accepted,
  declined;

  String get value => name;

  static SignoffStatus fromString(String? raw) {
    for (final s in values) {
      if (s.name == raw) return s;
    }
    return SignoffStatus.pending;
  }
}

/// Where a request sits in its chain (spec §4.2). `pendingAdvisers` is the
/// adviser request's first stage (both advisers accept in parallel);
/// `pendingAdviser` is the title request's (the current adviser notes it).
enum ChangeRequestStage {
  pendingAdvisers,
  pendingAdviser,
  pendingCoordinator,
  pendingDean,
  approved,
  returned;

  String get value => name;

  /// Null rather than a default: an unknown stage must not read as an open
  /// one that some approver could act on.
  static ChangeRequestStage? fromString(String? raw) {
    for (final s in values) {
      if (s.name == raw) return s;
    }
    return null;
  }

  bool get isPending =>
      this == pendingAdvisers ||
      this == pendingAdviser ||
      this == pendingCoordinator ||
      this == pendingDean;
}

/// The roles that sign a request of [type], in order. The adviser request has
/// two adviser signers (new and former); the title request has one.
List<String> signoffRolesFor(ChangeRequestType type) => switch (type) {
      ChangeRequestType.adviser => const [
          'newAdviser',
          'formerAdviser',
          'coordinator',
          'dean',
        ],
      ChangeRequestType.title => const ['adviser', 'coordinator', 'dean'],
    };

/// The stage a fresh request of [type] starts at.
ChangeRequestStage firstStageFor(ChangeRequestType type) =>
    type == ChangeRequestType.adviser
        ? ChangeRequestStage.pendingAdvisers
        : ChangeRequestStage.pendingAdviser;

/// The stage after [stage], or null past the Dean. Both adviser first stages
/// lead to the Coordinator.
ChangeRequestStage? nextStage(ChangeRequestStage stage) => switch (stage) {
      ChangeRequestStage.pendingAdvisers => ChangeRequestStage.pendingCoordinator,
      ChangeRequestStage.pendingAdviser => ChangeRequestStage.pendingCoordinator,
      ChangeRequestStage.pendingCoordinator => ChangeRequestStage.pendingDean,
      _ => null,
    };

/// One approver's sign-off on a request.
class Signoff {
  const Signoff({
    this.status = SignoffStatus.pending,
    this.respondedAt,
    this.reason,
  });

  final SignoffStatus status;
  final DateTime? respondedAt;

  /// The reason given on a decline; null otherwise.
  final String? reason;

  factory Signoff.fromMap(Map<String, dynamic> map) => Signoff(
        status: SignoffStatus.fromString(map['status'] as String?),
        respondedAt: map['respondedAt'] as DateTime?,
        reason: map['reason'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'status': status.value,
        'respondedAt': respondedAt,
        'reason': reason,
      };
}

/// A student's request to change their thesis's adviser or approved title,
/// routed through the sign-off chain (spec 2026-09-25).
class ChangeRequest {
  const ChangeRequest({
    required this.type,
    required this.stage,
    required this.reasons,
    required this.leaderUid,
    required this.signoffs,
    this.newAdviserUid,
    this.newAdviserName,
    this.formerAdviserUid,
    this.formerAdviserName,
    this.newTitle,
    this.createdAt,
    this.updatedAt,
  });

  final ChangeRequestType type;
  final ChangeRequestStage stage;
  final String reasons;
  final String leaderUid;

  /// One entry per role in [signoffRolesFor].
  final Map<String, Signoff> signoffs;

  final String? newAdviserUid;
  final String? newAdviserName;
  final String? formerAdviserUid;
  final String? formerAdviserName;
  final String? newTitle;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// True while the request is still moving through the chain — not returned
  /// to the student and not approved.
  bool get isOpen => stage.isPending;

  factory ChangeRequest.fromMap(String id, Map<String, dynamic> map) {
    final rawSignoffs = (map['signoffs'] as Map?) ?? const {};
    return ChangeRequest(
      type: ChangeRequestType.fromString(map['type'] as String?) ??
          ChangeRequestType.adviser,
      stage: ChangeRequestStage.fromString(map['stage'] as String?) ??
          ChangeRequestStage.returned,
      reasons: map['reasons'] as String? ?? '',
      leaderUid: map['leaderUid'] as String? ?? '',
      signoffs: {
        for (final e in rawSignoffs.entries)
          e.key as String:
              Signoff.fromMap((e.value as Map).cast<String, dynamic>()),
      },
      newAdviserUid: map['newAdviserUid'] as String?,
      newAdviserName: map['newAdviserName'] as String?,
      formerAdviserUid: map['formerAdviserUid'] as String?,
      formerAdviserName: map['formerAdviserName'] as String?,
      newTitle: map['newTitle'] as String?,
      createdAt: map['createdAt'] as DateTime?,
      updatedAt: map['updatedAt'] as DateTime?,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.value,
        'stage': stage.value,
        'reasons': reasons,
        'leaderUid': leaderUid,
        'signoffs': {for (final e in signoffs.entries) e.key: e.value.toMap()},
        if (newAdviserUid != null) 'newAdviserUid': newAdviserUid,
        if (newAdviserName != null) 'newAdviserName': newAdviserName,
        if (formerAdviserUid != null) 'formerAdviserUid': formerAdviserUid,
        if (formerAdviserName != null) 'formerAdviserName': formerAdviserName,
        if (newTitle != null) 'newTitle': newTitle,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}
```

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/data/models/change_request_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/change_request.dart test/data/models/change_request_test.dart
git status --short
git commit -m "feat(change-request): the change-of-adviser/title request model

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Security rules for change requests

**Files:**
- Modify: `firestore.rules` (inside `match /theses/{thesisId}`, and a new arm on the thesis `update`)
- Test: `rules-test/rules.test.js`

**Interfaces:**
- Consumes: the model's stored shape (Task 1).
- Produces: the `match /theses/{thesisId}/changeRequests/{crId}` block, a `changeRequestAt(thesisId, crId)` helper, and a thesis-`update` arm for the Dean's approval batch.

The rules cannot iterate the `signoffs` map generically, so each condition is written per role and per type. The stage advance is validated by the client's write being one of a small set of legal (stage, signoffs) transitions.

- [ ] **Step 1: Write the failing rules tests.** In `rules-test/rules.test.js`, after the re-defence tests (or at the end of the defence section), add:

```js
// ---------- Change of adviser / title (spec 2026-09-25) ----------

function crThesis(extra = {}) {
  return {
    leaderUid: "cr-leader", adviserUid: "cr-old-adv",
    panelistUids: ["cr-pan"], memberNames: [],
    workingTitle: "Old Title", college: "CICT", program: "BSIT",
    semester: "First", academicYear: "2026-2027",
    status: "titleApproved", ...extra,
  };
}

function adviserReq(extra = {}) {
  return {
    type: "adviser", stage: "pendingAdvisers",
    reasons: "The adviser moved campus.", leaderUid: "cr-leader",
    newAdviserUid: "cr-new-adv", newAdviserName: "Dr. New",
    formerAdviserUid: "cr-old-adv", formerAdviserName: "Dr. Old",
    signoffs: {
      newAdviser: { status: "pending" },
      formerAdviser: { status: "pending" },
      coordinator: { status: "pending" },
      dean: { status: "pending" },
    },
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra,
  };
}

const m5Dbs = new Map();
function asCrUser(uid, email) {
  if (!m5Dbs.has(uid)) {
    m5Dbs.set(uid, env.authenticatedContext(
      uid, { email, email_verified: true }).firestore());
  }
  return m5Dbs.get(uid);
}

async function seedCr(reqExtra = null, thesisExtra = {}) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "theses/cr1"), crThesis(thesisExtra));
    await setDoc(doc(db, "users/cr-leader"), { role: "student", active: true });
    await setDoc(doc(db, "users/cr-new-adv"), { role: "faculty", active: true });
    await setDoc(doc(db, "users/cr-old-adv"), { role: "faculty", active: true });
    await setDoc(doc(db, "users/cr-coord"), { role: "coordinator", active: true });
    await setDoc(doc(db, "users/cr-dean"), { role: "dean", active: true });
    if (reqExtra !== null) {
      await setDoc(doc(db, "theses/cr1/changeRequests/adviser"),
        adviserReq(reqExtra));
    }
  });
}

const crPath = "theses/cr1/changeRequests/adviser";

test("CR: only the leader creates, only at titleApproved", async () => {
  await seedCr();
  const leader = asCrUser("cr-leader", "cr-leader@isufst.edu.ph");
  const other = asCrUser("cr-new-adv", "cr-new-adv@isufst.edu.ph");
  await assertFails(setDoc(doc(other, crPath), adviserReq()));
  await assertSucceeds(setDoc(doc(leader, crPath), adviserReq()));
});

test("CR: create denied when the thesis is not titleApproved", async () => {
  await seedCr(null, { status: "titlePendingDefence" });
  const leader = asCrUser("cr-leader", "cr-leader@isufst.edu.ph");
  await assertFails(setDoc(doc(leader, crPath), adviserReq()));
});

test("CR: create must start every sign-off pending at the first stage",
  async () => {
    await seedCr();
    const leader = asCrUser("cr-leader", "cr-leader@isufst.edu.ph");
    await assertFails(setDoc(doc(leader, crPath),
      adviserReq({ stage: "pendingDean" })));
    await assertFails(setDoc(doc(leader, crPath), adviserReq({
      signoffs: { newAdviser: { status: "accepted" },
        formerAdviser: { status: "pending" },
        coordinator: { status: "pending" }, dean: { status: "pending" } } })));
  });

test("CR: no second open request of the same type", async () => {
  await seedCr(); // creates an open request at pendingAdvisers
  const leader = asCrUser("cr-leader", "cr-leader@isufst.edu.ph");
  await assertFails(setDoc(doc(leader, crPath),
    adviserReq({ reasons: "again" })));
});

test("CR: the new adviser accepts only their own sign-off, only at stage",
  async () => {
    await seedCr({});
    const newAdv = asCrUser("cr-new-adv", "cr-new-adv@isufst.edu.ph");
    const other = asCrUser("cr-pan", "cr-pan@isufst.edu.ph");
    // Someone else may not write the newAdviser sign-off.
    await assertFails(updateDoc(doc(other, crPath), {
      "signoffs.newAdviser.status": "accepted" }));
    // The new adviser accepts; the stage stays (former still pending).
    await assertSucceeds(updateDoc(doc(newAdv, crPath), {
      "signoffs.newAdviser.status": "accepted",
      "signoffs.newAdviser.respondedAt": serverTimestamp() }));
  });

test("CR: both advisers accepted advances to the coordinator", async () => {
  await seedCr({ signoffs: {
    newAdviser: { status: "accepted" },
    formerAdviser: { status: "pending" },
    coordinator: { status: "pending" }, dean: { status: "pending" } } });
  const oldAdv = asCrUser("cr-old-adv", "cr-old-adv@isufst.edu.ph");
  await assertSucceeds(updateDoc(doc(oldAdv, crPath), {
    "signoffs.formerAdviser.status": "accepted",
    "signoffs.formerAdviser.respondedAt": serverTimestamp(),
    stage: "pendingCoordinator" }));
});

test("CR: an adviser advancing before both accepted is denied", async () => {
  await seedCr({});
  const newAdv = asCrUser("cr-new-adv", "cr-new-adv@isufst.edu.ph");
  await assertFails(updateDoc(doc(newAdv, crPath), {
    "signoffs.newAdviser.status": "accepted", stage: "pendingCoordinator" }));
});

test("CR: a decline returns the request", async () => {
  await seedCr({});
  const newAdv = asCrUser("cr-new-adv", "cr-new-adv@isufst.edu.ph");
  await assertSucceeds(updateDoc(doc(newAdv, crPath), {
    "signoffs.newAdviser.status": "declined",
    "signoffs.newAdviser.reason": "Not my field.", stage: "returned" }));
});

test("CR: the coordinator recommends only at the coordinator stage",
  async () => {
    await seedCr({ stage: "pendingCoordinator", signoffs: {
      newAdviser: { status: "accepted" }, formerAdviser: { status: "accepted" },
      coordinator: { status: "pending" }, dean: { status: "pending" } } });
    const coord = asCrUser("cr-coord", "cr-coord@isufst.edu.ph");
    const dean = asCrUser("cr-dean", "cr-dean@isufst.edu.ph");
    await assertFails(updateDoc(doc(dean, crPath), {
      "signoffs.coordinator.status": "accepted", stage: "pendingDean" }));
    await assertSucceeds(updateDoc(doc(coord, crPath), {
      "signoffs.coordinator.status": "accepted",
      "signoffs.coordinator.respondedAt": serverTimestamp(),
      stage: "pendingDean" }));
  });

test("CR: the Dean approves the request and the thesis in one batch",
  async () => {
    await seedCr({ stage: "pendingDean", signoffs: {
      newAdviser: { status: "accepted" }, formerAdviser: { status: "accepted" },
      coordinator: { status: "accepted" }, dean: { status: "pending" } } });
    const dean = asCrUser("cr-dean", "cr-dean@isufst.edu.ph");

    // The thesis change alone is denied.
    await assertFails(updateDoc(doc(dean, "theses/cr1"),
      { adviserUid: "cr-new-adv" }));

    // Both together succeed.
    const batch = writeBatch(dean);
    batch.update(doc(dean, crPath), {
      "signoffs.dean.status": "accepted",
      "signoffs.dean.respondedAt": serverTimestamp(), stage: "approved" });
    batch.update(doc(dean, "theses/cr1"), { adviserUid: "cr-new-adv" });
    await assertSucceeds(batch.commit());
  });

test("CR: the leader resubmits only a returned request, same type & leader",
  async () => {
    await seedCr({ stage: "returned", signoffs: {
      newAdviser: { status: "declined", reason: "no" },
      formerAdviser: { status: "pending" },
      coordinator: { status: "pending" }, dean: { status: "pending" } } });
    const leader = asCrUser("cr-leader", "cr-leader@isufst.edu.ph");
    // Resubmit resets to first stage, all pending.
    await assertSucceeds(setDoc(doc(leader, crPath),
      adviserReq({ newAdviserUid: "cr-new-adv", newAdviserName: "Dr. New" })));
    // A resubmit that changes the type is refused.
    await seedCr({ stage: "returned", signoffs: adviserReq().signoffs });
    await assertFails(setDoc(doc(leader, crPath),
      adviserReq({ type: "title" })));
  });
```

Also add a test that a sign-off cannot tamper with another role:

```js
test("CR: a sign-off changes only its own role", async () => {
  await seedCr({});
  const newAdv = asCrUser("cr-new-adv", "cr-new-adv@isufst.edu.ph");
  // Accepting my own AND pre-setting the coordinator's is denied.
  await assertFails(updateDoc(doc(newAdv, crPath), {
    "signoffs.newAdviser.status": "accepted",
    "signoffs.coordinator.status": "accepted" }));
});
```

Import `writeBatch` at the top of the test file if it is not already imported (it is from `firebase/firestore`).

- [ ] **Step 2: Run and watch the allowed cases fail**

Run: `cd rules-test && npm test`
Expected: every new test's `assertSucceeds` FAILS (no rule admits the writes yet); the `assertFails` calls pass by default. Every pre-existing test still passes.

- [ ] **Step 3: Implement the rules.** In `firestore.rules`, inside `match /theses/{thesisId}` (after the existing helpers, near `candidateTitleExists`), add a helper:

```
    function changeRequestAt(thesisId, crId) {
      return get(/databases/$(database)/documents/theses/$(thesisId)/changeRequests/$(crId)).data;
    }
```

Then, still inside `match /theses/{thesisId}`, add the subcollection block (place it beside `match /nominations/{nomineeUid}`):

```
      // Change of adviser / title (spec 2026-09-25). One document per kind,
      // id == the type, so a thesis holds at most one of each. The leader
      // creates it; the named advisers, then the coordinator, then the dean
      // sign off; the dean's approval batch also changes the thesis.
      match /changeRequests/{crId} {
        function req() { return resource.data; }
        function incoming() { return request.resource.data; }
        function t() { return thesisData(thesisId); }

        // Every reader who has business seeing the request.
        allow get, list: if isThesisLeader(thesisId)
                         || isCoordinator() || isDean()
                         || (signedIn() && isActive() && (
                              request.auth.uid == req().get('newAdviserUid', '') ||
                              request.auth.uid == req().get('formerAdviserUid', '') ||
                              request.auth.uid == t().adviserUid ||
                              request.auth.uid in t().panelistUids));

        // The leader writes a fresh first-pending request: the first create
        // (no document — the create rule), or a reset of a returned/approved
        // one (an update). Both are the same shape, so both arms share it.
        function isFreshRequest() {
          let d = incoming();
          return crId in ['adviser', 'title']
                 && d.type == crId
                 && d.leaderUid == request.auth.uid
                 && d.reasons is string && d.reasons.size() > 0
                 && d.reasons.size() < 4000
                 && (
                      (crId == 'adviser'
                       && d.stage == 'pendingAdvisers'
                       && d.newAdviserUid is string
                       && d.formerAdviserUid == t().adviserUid
                       && d.signoffs.newAdviser.status == 'pending'
                       && d.signoffs.formerAdviser.status == 'pending'
                       && d.signoffs.coordinator.status == 'pending'
                       && d.signoffs.dean.status == 'pending')
                      ||
                      (crId == 'title'
                       && d.stage == 'pendingAdviser'
                       && d.newTitle is string && d.newTitle.size() > 0
                       && d.signoffs.adviser.status == 'pending'
                       && d.signoffs.coordinator.status == 'pending'
                       && d.signoffs.dean.status == 'pending')
                    );
        }

        allow create: if verified()
                      && isThesisLeader(thesisId)
                      && t().status == 'titleApproved'
                      && isFreshRequest();

        // A leader's reset (returned or approved -> fresh). An open request
        // may never be overwritten, which is the one-open-request guarantee.
        allow update: if verified()
                      && isThesisLeader(thesisId)
                      && t().status == 'titleApproved'
                      && req().stage in ['returned', 'approved']
                      && req().type == crId
                      && isFreshRequest();

        // A sign-off writes exactly one role's entry, at the stage that
        // awaits it, and either accepts (advancing when the step completes)
        // or declines (returning the request). The uid allowed to write a
        // role is checked inline in the `allow update` arms below
        // (`request.auth.uid == req().newAdviserUid`, `== t().adviserUid`,
        // `isCoordinator()`, `isDean()`).

        // Every role OTHER than `role` must be untouched, so a signer cannot
        // pre-set a later approver's sign-off in the same write. Rules cannot
        // iterate the map, so each role is named. A role `r` is "kept" when
        // it is not `role` and its incoming status equals its stored status;
        // `role` itself is exempt because the caller is changing it.
        function keptUnless(r, role) {
          return r == role
                 || incoming().signoffs[r].status == req().signoffs[r].status;
        }
        function onlyOwnSignoff(role) {
          return req().type == 'adviser'
              ? (keptUnless('newAdviser', role)
                 && keptUnless('formerAdviser', role)
                 && keptUnless('coordinator', role)
                 && keptUnless('dean', role))
              : (keptUnless('adviser', role)
                 && keptUnless('coordinator', role)
                 && keptUnless('dean', role));
        }

        // Accept: the role's status becomes accepted; the stage either holds
        // (an adviser accept while the co-adviser is still pending) or moves
        // to `to`. Only that role's signoff and the stage may change.
        function accepts(role, holdStage, to) {
          return onlyChanged(['signoffs', 'stage', 'updatedAt'])
                 && incoming().signoffs[role].status == 'accepted'
                 && req().signoffs[role].status == 'pending'
                 && onlyOwnSignoff(role)
                 && (incoming().stage == holdStage || incoming().stage == to);
        }

        // A decline sets the role declined with a reason and returns the
        // request; nothing else of substance changes.
        function declines(role) {
          return onlyChanged(['signoffs', 'stage', 'updatedAt'])
                 && incoming().signoffs[role].status == 'declined'
                 && req().signoffs[role].status == 'pending'
                 && onlyOwnSignoff(role)
                 && incoming().stage == 'returned'
                 && (incoming().signoffs[role].reason == null
                     || incoming().signoffs[role].reason.size() < 2000);
        }

        // The adviser-request advance to coordinator is legal only when BOTH
        // advisers are accepted in the incoming document.
        function bothAdvisersAccepted() {
          return incoming().signoffs.newAdviser.status == 'accepted'
                 && incoming().signoffs.formerAdviser.status == 'accepted';
        }

        allow update: if verified() && (
          // --- adviser request: the two advisers, in parallel ---
          (req().type == 'adviser' && req().stage == 'pendingAdvisers'
           && request.auth.uid == req().newAdviserUid
           && (declines('newAdviser')
               || (accepts('newAdviser', 'pendingAdvisers', 'pendingCoordinator')
                   && (incoming().stage == 'pendingAdvisers'
                       || bothAdvisersAccepted()))))
          ||
          (req().type == 'adviser' && req().stage == 'pendingAdvisers'
           && request.auth.uid == req().formerAdviserUid
           && (declines('formerAdviser')
               || (accepts('formerAdviser', 'pendingAdvisers', 'pendingCoordinator')
                   && (incoming().stage == 'pendingAdvisers'
                       || bothAdvisersAccepted()))))
          ||
          // --- title request: the current adviser notes it ---
          (req().type == 'title' && req().stage == 'pendingAdviser'
           && request.auth.uid == t().adviserUid
           && (declines('adviser')
               || accepts('adviser', 'pendingAdviser', 'pendingCoordinator')))
          ||
          // --- coordinator ---
          (req().stage == 'pendingCoordinator' && isCoordinator()
           && (declines('coordinator')
               || accepts('coordinator', 'pendingCoordinator', 'pendingDean')))
          ||
          // --- dean: half of the approval batch, or a return ---
          (req().stage == 'pendingDean' && isDean()
           && (declines('dean')
               || accepts('dean', 'pendingDean', 'approved')))
        );

        allow delete: if false;
      }
```

Then add the thesis-change arm to the thesis's own `allow update` rules. After the Dean's title-decision arm (around line 766), add:

```
      // The other half of the Dean's change-request approval batch (spec
      // 2026-09-25 §7). The dean may set the new adviser or the new title on
      // a titleApproved thesis, but ONLY while a matching request sits at
      // `pendingDean` naming this exact value — so the change cannot be made
      // except by approving a request that ran the whole chain.
      allow update: if verified()
                    && isDean()
                    && resource.data.status == 'titleApproved'
                    && (
                      (onlyChanged(['adviserUid'])
                       && changeRequestAt(thesisId, 'adviser').stage
                          == 'pendingDean'
                       && changeRequestAt(thesisId, 'adviser').newAdviserUid
                          == request.resource.data.adviserUid)
                      ||
                      (onlyChanged(['workingTitle'])
                       && changeRequestAt(thesisId, 'title').stage
                          == 'pendingDean'
                       && changeRequestAt(thesisId, 'title').newTitle
                          == request.resource.data.workingTitle)
                    );
```

- [ ] **Step 4: Run and watch them pass**

Run: `cd rules-test && npm test`
Expected: every test PASSES, old and new. If the emulator rejects `onlyOwnSignoff`'s nested `incoming().signoffs[r].status` because a role key is absent from `incoming().signoffs`, guard each access with `.get`: `incoming().signoffs[r].get('status', '')`. Keep the assertion's meaning (an absent role reads as changed-from-stored, which the "only own signoff" test still catches).

- [ ] **Step 5: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git status --short
git commit -m "feat(rules): change-of-adviser/title requests and the Dean's batch

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: The change-request repository

**Files:**
- Create: `lib/data/repositories/change_request_repository.dart`
- Create: `lib/providers/change_request_providers.dart` (the repository provider only; the query providers come in Task 4)
- Test: `test/data/repositories/change_request_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 (the model), `firestoreProvider` (`lib/providers/auth_providers.dart`), `FacultyDirectoryEntry` (`lib/data/models/faculty_directory_entry.dart`), `Thesis`.
- Produces:
  - `final changeRequestRepositoryProvider = Provider<ChangeRequestRepository>`.
  - `ChangeRequestRepository(FirebaseFirestore)` with:
    - `Stream<List<ChangeRequest>> watchForThesis(String thesisId)`
    - `Future<void> submitAdviserChange({required Thesis thesis, required FacultyDirectoryEntry newAdviser, required String formerAdviserName, required String reasons})`
    - `Future<void> submitTitleChange({required Thesis thesis, required String newTitle, required String reasons})`
    - `Future<void> respond({required String thesisId, required ChangeRequestType type, required String role, required bool accept, String? reason})`
    - `Future<void> approveAsDean({required String thesisId, required ChangeRequestType type})`

- [ ] **Step 1: Write the failing tests.** Create `test/data/repositories/change_request_repository_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/repositories/change_request_repository.dart';

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1',
    'panelistUids': <String>['p1'], 'memberNames': <String>[],
    'workingTitle': 'Old Title', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027', 'status': 'titleApproved',
  });
  return db;
}

Future<Thesis> theThesis(FakeFirebaseFirestore db) async =>
    Thesis.fromMap('t1', (await db.doc('theses/t1').get()).data()!);

FacultyDirectoryEntry newAdv() => const FacultyDirectoryEntry(
    uid: 'a2', fullName: 'Dr. New', role: 'faculty');

void main() {
  test('submitting an adviser change creates a pendingAdvisers request',
      () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitAdviserChange(
      thesis: await theThesis(db),
      newAdviser: newAdv(),
      formerAdviserName: 'Dr. Old',
      reasons: 'The adviser moved campus.',
    );
    final list = await repo.watchForThesis('t1').first;
    expect(list.single.type, ChangeRequestType.adviser);
    expect(list.single.stage, ChangeRequestStage.pendingAdvisers);
    expect(list.single.newAdviserUid, 'a2');
    expect(list.single.formerAdviserUid, 'a1');
    expect(list.single.signoffs['newAdviser']!.status, SignoffStatus.pending);
  });

  test('a title change creates a pendingAdviser request', () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitTitleChange(
      thesis: await theThesis(db), newTitle: 'A Better Title', reasons: 'x');
    final r = (await repo.watchForThesis('t1').first).single;
    expect(r.type, ChangeRequestType.title);
    expect(r.stage, ChangeRequestStage.pendingAdviser);
    expect(r.newTitle, 'A Better Title');
  });

  test('the new adviser accepting holds the stage until the former does',
      () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitAdviserChange(thesis: await theThesis(db),
        newAdviser: newAdv(), formerAdviserName: 'Dr. Old', reasons: 'x');

    await repo.respond(thesisId: 't1', type: ChangeRequestType.adviser,
        role: 'newAdviser', accept: true);
    var r = (await repo.watchForThesis('t1').first).single;
    expect(r.stage, ChangeRequestStage.pendingAdvisers);

    await repo.respond(thesisId: 't1', type: ChangeRequestType.adviser,
        role: 'formerAdviser', accept: true);
    r = (await repo.watchForThesis('t1').first).single;
    expect(r.stage, ChangeRequestStage.pendingCoordinator);
  });

  test('a decline returns the request with the reason', () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitTitleChange(
        thesis: await theThesis(db), newTitle: 'X', reasons: 'y');
    await repo.respond(thesisId: 't1', type: ChangeRequestType.title,
        role: 'adviser', accept: false, reason: 'Too broad.');
    final r = (await repo.watchForThesis('t1').first).single;
    expect(r.stage, ChangeRequestStage.returned);
    expect(r.signoffs['adviser']!.status, SignoffStatus.declined);
    expect(r.signoffs['adviser']!.reason, 'Too broad.');
  });

  test('the coordinator then Dean approval applies the adviser change',
      () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitAdviserChange(thesis: await theThesis(db),
        newAdviser: newAdv(), formerAdviserName: 'Dr. Old', reasons: 'x');
    await repo.respond(thesisId: 't1', type: ChangeRequestType.adviser,
        role: 'newAdviser', accept: true);
    await repo.respond(thesisId: 't1', type: ChangeRequestType.adviser,
        role: 'formerAdviser', accept: true);
    await repo.respond(thesisId: 't1', type: ChangeRequestType.adviser,
        role: 'coordinator', accept: true);
    await repo.approveAsDean(thesisId: 't1', type: ChangeRequestType.adviser);

    expect((await theThesis(db)).adviserUid, 'a2');
    final r = (await repo.watchForThesis('t1').first).single;
    expect(r.stage, ChangeRequestStage.approved);
  });

  test('the Dean approval applies the title change', () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitTitleChange(
        thesis: await theThesis(db), newTitle: 'A Better Title', reasons: 'x');
    for (final role in ['adviser', 'coordinator']) {
      await repo.respond(thesisId: 't1', type: ChangeRequestType.title,
          role: role, accept: true);
    }
    await repo.approveAsDean(thesisId: 't1', type: ChangeRequestType.title);
    expect((await theThesis(db)).workingTitle, 'A Better Title');
  });

  test('responding at the wrong stage is refused', () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitTitleChange(
        thesis: await theThesis(db), newTitle: 'X', reasons: 'y');
    // The coordinator cannot act while the adviser has not.
    await expectLater(
      repo.respond(thesisId: 't1', type: ChangeRequestType.title,
          role: 'coordinator', accept: true),
      throwsStateError,
    );
  });

  test('approving applies nothing if the thesis left titleApproved',
      () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitTitleChange(
        thesis: await theThesis(db), newTitle: 'X', reasons: 'y');
    for (final role in ['adviser', 'coordinator']) {
      await repo.respond(thesisId: 't1', type: ChangeRequestType.title,
          role: role, accept: true);
    }
    await db.doc('theses/t1').update({'status': 'archived'});
    await expectLater(
      repo.approveAsDean(thesisId: 't1', type: ChangeRequestType.title),
      throwsStateError,
    );
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/data/repositories/change_request_repository_test.dart`
Expected: compile error — the repository does not exist.

- [ ] **Step 3: Create `lib/data/repositories/change_request_repository.dart`:**

```dart
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
          String thesisId, ChangeRequestType type) =>
      _requests(thesisId).doc(type.id);

  ChangeRequest _toRequest(String id, Map<String, dynamic> raw) {
    Map<String, dynamic> withDates(Map<String, dynamic> m) => {
          ...m,
          'createdAt': (m['createdAt'] as Timestamp?)?.toDate(),
          'updatedAt': (m['updatedAt'] as Timestamp?)?.toDate(),
          'signoffs': {
            for (final e in ((m['signoffs'] as Map?) ?? const {}).entries)
              e.key: {
                ...(e.value as Map).cast<String, dynamic>(),
                'respondedAt':
                    ((e.value as Map)['respondedAt'] as Timestamp?)?.toDate(),
              },
          },
        };
    return ChangeRequest.fromMap(id, withDates(raw));
  }

  Stream<List<ChangeRequest>> watchForThesis(String thesisId) =>
      _requests(thesisId).snapshots().map((s) =>
          s.docs.map((d) => _toRequest(d.id, d.data())).toList());

  Map<String, dynamic> _freshSignoffs(List<String> roles) => {
        for (final r in roles)
          r: {'status': SignoffStatus.pending.value, 'respondedAt': null,
              'reason': null},
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
            : {'workingTitle': req.newTitle});
    await batch.commit();
  }
}
```

Create `lib/providers/change_request_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/repositories/change_request_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final changeRequestRepositoryProvider = Provider<ChangeRequestRepository>(
  (ref) => ChangeRequestRepository(ref.watch(firestoreProvider)),
);
```

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/data/repositories/change_request_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/change_request_repository.dart lib/providers/change_request_providers.dart test/data/repositories/change_request_repository_test.dart
git status --short
git commit -m "feat(change-request): the request repository and its stage machine

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Providers — the leader's request, the inboxes, and eligibility

**Files:**
- Modify: `lib/providers/change_request_providers.dart`
- Test: `test/providers/change_request_providers_test.dart`

**Interfaces:**
- Consumes: Task 3 (`changeRequestRepositoryProvider`, `watchForThesis`), `signedInUidProvider`, `currentUserProvider`, `myDefencesProvider` (`lib/providers/defence_providers.dart`), `Defence`, `Thesis`, `UserRole`.
- Produces:
  - `changeRequestsForThesisProvider = StreamProvider.family<List<ChangeRequest>, String>`
  - `mySignoffRequestsProvider = StreamProvider<List<({String thesisId, ChangeRequest request, String role})>>` — for the signed-in faculty member: every open request awaiting a role they hold. Reads via a `collectionGroup('changeRequests')` query filtered by `stage` in the pending stages, then keeps the ones where the signed-in uid is the awaited signer.
  - `coordinatorChangeRequestsProvider` / `deanChangeRequestsProvider = StreamProvider<List<({String thesisId, ChangeRequest request})>>` — open requests at `pendingCoordinator` / `pendingDean`.
  - `bool canRequestAdviserChange(Thesis, List<Defence>)` and `bool canRequestTitleChange(Thesis, List<Defence>)` — the §5 eligibility.

- [ ] **Step 1: Write the failing tests.** Create `test/providers/change_request_providers_test.dart`, covering: `canRequestAdviserChange` true at `titleApproved` with no defence and false once any non-cancelled defence exists; `canRequestTitleChange` true at `titleApproved` with no passed final and false after a passed final or when archived; and `mySignoffRequestsProvider` returning a request awaiting the signed-in new adviser but not one awaiting someone else. Use the `ProviderContainer` + fake Firestore pattern from `test/providers/my_title_defences_test.dart` (its `containerFor`/`settle` helpers), seeding `theses/{id}/changeRequests/{type}` documents directly. Write the two pure eligibility functions' tests first as plain `test(...)` calls with hand-built `Thesis` and `Defence` objects (see `defence_repository_test.dart` for a `Defence` constructor and `my_title_defences_test.dart` for a `thesis(...)` map helper).

For `canRequestAdviserChange`, assert: `titleApproved` + `[]` → true; `titleApproved` + one `scheduled` pre-oral → false; `titleApproved` + one `cancelled` defence → true; any other status → false.
For `canRequestTitleChange`, assert: `titleApproved` + `[]` → true; `titleApproved` + a `final` defence with `pass` verdict → false; `titleApproved` + a `final` defence with no verdict → true; `archived` → false.

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/providers/change_request_providers_test.dart`
Expected: compile error — the providers and functions do not exist.

- [ ] **Step 3: Implement.** Append to `lib/providers/change_request_providers.dart` the eligibility functions and the providers:

```dart
// (add these imports at the top)
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:ethesishub/data/models/change_request.dart';
// import 'package:ethesishub/data/models/defence.dart';
// import 'package:ethesishub/data/models/evaluation.dart';
// import 'package:ethesishub/data/models/thesis.dart';
// import 'package:ethesishub/data/models/thesis_status.dart';
// import 'package:ethesishub/data/models/user_role.dart';
// import 'package:ethesishub/providers/defence_providers.dart';

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
```

The title request's `adviser` signer is resolved against the thesis (the collection-group query cannot join it). Note this for Task 6: the faculty inbox filters `pendingAdviser` requests to the ones whose thesis the signed-in user advises, using `myAdviseesProvider`.

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/providers/change_request_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/change_request_providers.dart test/providers/change_request_providers_test.dart
git status --short
git commit -m "feat(change-request): providers for the leader, inboxes and eligibility

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Student — request forms, thesis-screen buttons, and tracking

**Files:**
- Create: `lib/features/thesis/change_request_screen.dart` (both request forms; one screen, two modes)
- Create: `lib/features/thesis/change_request_tracker.dart` (the progress card shown on the thesis screen)
- Modify: `lib/features/thesis/thesis_status_screen.dart` (the two buttons + the tracker)
- Modify: `lib/core/routing/app_router.dart` (two routes)
- Test: `test/features/thesis/change_request_screen_test.dart`
- Test: `test/features/thesis/change_request_tracker_test.dart`

**Interfaces:**
- Consumes: Task 3 (`submitAdviserChange`, `submitTitleChange`), Task 4 (`changeRequestsForThesisProvider`, `canRequestAdviserChange`, `canRequestTitleChange`), `allDirectoryProvider`, `myDefencesProvider`, `currentUserProvider`.
- Produces: routes `/thesis/change-adviser?id=<thesisId>` and `/thesis/change-title?id=<thesisId>`; keys `requestAdviserChange`, `requestTitleChange`, `changeRequestTracker`, `changeRequestScreen`, `submitChangeRequest`, `newAdviserPicker`, `changeReasons`, `newTitleField`, `resubmitChangeRequest`.

- [ ] **Step 1** through **Step N** (TDD): write the screen and tracker. The screen picks the new adviser from `allDirectoryProvider` (honour `nominableAsAdviser`, exclude the current `thesis.adviserUid`) with a reasons field, or a new-title field with reasons; **Submit** refuses an empty reason, an empty title, a new adviser equal to the current adviser, or (adviser) a new adviser equal to the former, showing an inline message. On success it pops back. The tracker card lists the open/returned request, each sign-off's state, and on `returned` shows the reason and an **Edit and resubmit** button routing back to the screen prefilled. On the thesis screen, the two buttons appear only when `canRequestAdviserChange` / `canRequestTitleChange` (read `myDefencesProvider` for the thesis), and only for the leader. Model the screen on `schedule_defence_screen.dart` (form + busy + error + `_framed`) and the tracker on the nomination-progress card in `thesis_status_screen.dart`. Full widget tests per key above, in the style of `test/features/defence/schedule_defence_screen_test.dart` (fake Firestore, `MockFirebaseAuth`, a GoRouter with the request route and a landing route). Commit with `test/` + `lib/` for this task's files.

  Because the screen and tracker are substantial, split this task's commit into two if a reviewer would gate them separately: (a) the request screen + routes; (b) the tracker + thesis-screen wiring. Each commit ends with the trailer.

- [ ] **Final step: Commit** (see above).

---

### Task 6: Faculty — the sign-off inbox

**Files:**
- Modify: `lib/features/nomination/nomination_inbox_screen.dart` (add a "Change requests" section) OR create `lib/features/nomination/change_request_inbox.dart` and mount it on the same screen
- Test: `test/features/nomination/change_request_inbox_test.dart`

**Interfaces:**
- Consumes: Task 4 (`mySignoffRequestsProvider`, `myAdviseesProvider` for resolving the title request's adviser), Task 3 (`respond`), `currentUserProvider`.
- Produces: a `ChangeRequestInbox` widget listing the requests awaiting this faculty member — each showing the group's thesis title, the from→to change and the reasons, with **Accept** and **Decline** (reason required). For a `pendingAdviser` (title) request, show it only when the signed-in user advises that thesis (`myAdviseesProvider` contains it). Keys: `changeRequestInbox`, `acceptChangeRequest-<thesisId>-<role>`, `declineChangeRequest-<thesisId>-<role>`, `changeRequestDeclineReason`.

- [ ] TDD as in Task 5's style: a new adviser sees and accepts a `pendingAdvisers` request; a decline requires a reason and returns it; a title request appears only for the advising faculty. Widget tests with fake Firestore and a signed-in faculty uid. Commit `lib/` + `test/` for this task, trailer included.

---

### Task 7: Coordinator and Dean — the queues

**Files:**
- Create: `lib/features/dashboard/change_request_queue.dart` (`ChangeRequestQueue({required bool asDean})`)
- Modify: `lib/features/dashboard/coordinator_overview.dart` and `lib/features/dashboard/dean_overview.dart` (mount the queue / add a metric linking to it), and `lib/core/routing/app_router.dart` if a dedicated route is added
- Test: `test/features/dashboard/change_request_queue_test.dart`

**Interfaces:**
- Consumes: Task 4 (`coordinatorChangeRequestsProvider`, `deanChangeRequestsProvider`), Task 3 (`respond` for the coordinator's recommend/return; `approveAsDean` for the Dean's approve; `respond` with `accept:false` for the Dean's return).
- Produces: `ChangeRequestQueue`, showing each request at the queue's stage with the change and reasons, and **Recommend**/**Return** (coordinator) or **Approve**/**Return** (dean). Keys: `changeRequestQueue`, `recommendChangeRequest-<thesisId>-<type>`, `approveChangeRequest-<thesisId>-<type>`, `returnChangeRequest-<thesisId>-<type>`, `changeRequestReturnReason`.

- [ ] TDD: the coordinator recommends a `pendingCoordinator` request (it moves to `pendingDean`); the Dean approves a `pendingDean` adviser request and the thesis's `adviserUid` changes; a return sets it `returned`. Widget tests with fake Firestore, a coordinator and a dean uid. Commit `lib/` + `test/`, trailer.

---

### Task 8: The filled Form 4a / 4b record PDF

**Files:**
- Create: `lib/features/forms/change_request_form.dart` (`Future<Uint8List> buildChangeRequestPdf(ChangeRequest, {required Thesis thesis})`)
- Modify: `lib/features/thesis/change_request_tracker.dart` (a **Download form** button when the request is `approved`)
- Test: `test/features/forms/change_request_form_test.dart`

**Interfaces:**
- Consumes: `form4aTemplate` / `form4bTemplate` and `buildFormPdf` (`lib/features/forms/editable/…`), the templates' block ids (`nominatedAdviser`, `formerAdviser`, `reasons` for 4a; `oldTitle`, `newTitle`, `reasons` for 4b; plus `student`, `nominated`, `former`, `adviser` name blocks), and `pdf_text.dart`'s `extractPdfText` for the test.
- Produces: `buildChangeRequestPdf` mapping a `ChangeRequest` to the template overrides and returning the filled PDF.

- [ ] **Step 1: Write the failing test.** Assert that for an adviser request, `extractPdfText(await buildChangeRequestPdf(req, thesis: t))` contains the new adviser name, the former adviser name and the reasons; for a title request, the old title (`thesis.workingTitle`), the new title and the reasons.

- [ ] **Step 2–4:** implement by building the overrides map (e.g. adviser: `{'nominatedAdviser': req.newAdviserName!, 'formerAdviser': req.formerAdviserName!, 'reasons': req.reasons, 'nominated': req.newAdviserName!, 'former': req.formerAdviserName!}`; title: `{'oldTitle': thesis.workingTitle, 'newTitle': req.newTitle!, 'reasons': req.reasons}`) and calling `buildFormPdf(form4aTemplate, overrides)` / `buildFormPdf(form4bTemplate, overrides)`. Wire the download button through the existing `pdfSharerProvider`. Commit `lib/` + `test/`, trailer.

---

### Task 9: Whole-suite verification

**Files:** none changed unless a check fails.

- [ ] **Step 1:** `flutter test`. Expected: `All tests passed!`. The known flaky `evaluation_repository_test` may need one re-run; report both runs if it alone fails.
- [ ] **Step 2:** `flutter analyze`. Expected: no new issues in this plan's files.
- [ ] **Step 3:** `cd rules-test && npm test`. Expected: all pass.
- [ ] **Step 4: Report; no commit.**
  - Deploy `firestore.rules`. If the console asks for a `collectionGroup('changeRequests')` index (on `stage`), create it. No data migration.
  - Rebuild the APK.
  - On a device: as a leader at `titleApproved` with no defence, request a change of adviser; accept as the new and former adviser; recommend as Coordinator; approve as Dean; confirm the thesis moves to the new adviser's Advisees. Repeat for a title change. Confirm a decline returns it and the leader can resubmit.
