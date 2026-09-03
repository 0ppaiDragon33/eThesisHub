# Coordinator Admin Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the coordinator a Users screen — every account, activate/deactivate, and per-account designation of who may be nominated as an adviser or a panelist — and make that designation drive the faculty mode switch.

**Architecture:** Rules first, UI last. The three rules changes are the risky part and are the only real authorization boundary, so each lands with its own emulator tests before any Dart consumes it. The models come first because both the rules tests and the screen need to agree on what absence means. The D5 revision comes last, once designation actually exists to read.

**Tech Stack:** Flutter 3.44 / Dart 3.12 · Riverpod **2.6.1** · go_router **17.5** · `fake_cloud_firestore` + `firebase_auth_mocks` for widget tests · `@firebase/rules-unit-testing` against the Firestore emulator.

**Spec:** `docs/superpowers/specs/2026-08-28-coordinator-admin-design.md`

## Global Constraints

- **Riverpod is pinned at 2.6.1.** `Notifier`/`NotifierProvider` **are** part of 2.6.1 and are the right tool for persisted state — `sidebarExpandedProvider` and `facultyModeProvider` both use them. Forbidden: codegen (`@riverpod`) and any 3.x-only API. `StreamProvider.stream` is deprecated in this version.
- **Android and Web only.** `dart:io` must never be imported from `lib/`.
- **Firebase Spark plan — no Cloud Functions. `firestore.rules` is the only authorization boundary.** Picker filtering is a UX guard and must never be described as the boundary.
- **Designation lives on `users/{uid}`. The directory is a mirror.** `facultyDirectory` is self-written; trusting it for authority would make designation self-declarable — the finding the ex-officio check already records (spec D27).
- **Absence of a designation field reads as `true`.** Every existing account predates these fields; a missing value meaning "not nominable" would make every current faculty member unpickable on deploy (spec §3).
- **Capability is the union of designation and positions held. Neither subtracts** (spec D30). A position you already hold always grants access.
- **Ex-officio seats bypass designation** (spec D32).
- **No role-specific designation rules** (spec D31). No "the coordinator is always an adviser".
- `fake_cloud_firestore` **enforces no rules** — every permission claim belongs in `rules-test/rules.test.js` and nowhere else. It **returns documents in insertion order**, so ordering fixtures seed against the expected order. `pumpAndSettle` **resolves streams before assertions**.
- **Every deny test carries a control** proving it is not passing for an unrelated reason.
- Run `flutter test` in the **FOREGROUND**, one run at a time. Concurrent runs leave orphaned `flutter_tester` processes that make the suite appear to hang.
- Analyzer clean apart from exactly 2 known pre-existing infos (`use_super_parameters` in `test/features/auth/verify_email_screen_test.dart`).

---

### Task 1: The two designation fields on both models

**Files:**
- Modify: `lib/data/models/app_user.dart`, `lib/data/models/faculty_directory_entry.dart`
- Test: `test/data/models/designation_test.dart`

**Interfaces:**
- Produces: `AppUser.nominableAsAdviser` / `.nominableAsPanelist` (both `bool`), and the same two on `FacultyDirectoryEntry`. Both default a missing key to `true` on read. Every later task depends on that default.

- [ ] **Step 1: Write the failing test**

Create `test/data/models/designation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';

void main() {
  group('AppUser designation', () {
    test('a document with no designation keys reads as nominable for both',
        () {
      // Every account that exists today predates these fields. If absence
      // meant "not nominable", deploying this would make every current
      // faculty member unpickable at once, with no error anywhere.
      final u = AppUser.fromMap('u1', {
        'fullName': 'Dr. A',
        'email': 'a@isufst.edu.ph',
        'role': 'faculty',
        'active': true,
      });
      expect(u.nominableAsAdviser, isTrue);
      expect(u.nominableAsPanelist, isTrue);
    });

    test('an explicit false is honoured', () {
      final u = AppUser.fromMap('u1', {
        'fullName': 'Dr. A',
        'email': 'a@isufst.edu.ph',
        'role': 'faculty',
        'active': true,
        'nominableAsAdviser': false,
        'nominableAsPanelist': true,
      });
      expect(u.nominableAsAdviser, isFalse);
      expect(u.nominableAsPanelist, isTrue);
    });

    test('the two are independent', () {
      // Two booleans rather than one enum, because the four states are a
      // product of two independent facts.
      final u = AppUser.fromMap('u1', {
        'fullName': 'Dr. A',
        'email': 'a@isufst.edu.ph',
        'role': 'faculty',
        'active': true,
        'nominableAsAdviser': true,
        'nominableAsPanelist': false,
      });
      expect(u.nominableAsAdviser, isTrue);
      expect(u.nominableAsPanelist, isFalse);
    });
  });

  group('FacultyDirectoryEntry designation', () {
    test('a mirror with no designation keys reads as nominable for both', () {
      final e = FacultyDirectoryEntry.fromMap('u1', {
        'fullName': 'Dr. A',
        'role': 'faculty',
      });
      expect(e.nominableAsAdviser, isTrue);
      expect(e.nominableAsPanelist, isTrue);
    });

    test('an explicit false is honoured', () {
      final e = FacultyDirectoryEntry.fromMap('u1', {
        'fullName': 'Dr. A',
        'role': 'faculty',
        'nominableAsAdviser': false,
      });
      expect(e.nominableAsAdviser, isFalse);
      expect(e.nominableAsPanelist, isTrue);
    });

    test('toMap does NOT write designation', () {
      // upsertOwnEntry round-trips through toMap, and the subject may not
      // write their own designation -- that is spec D27's whole point.
      // Including it here would send the field on every sign-in.
      final e = FacultyDirectoryEntry.fromMap('u1', {
        'fullName': 'Dr. A',
        'role': 'faculty',
        'nominableAsAdviser': false,
      });
      expect(e.toMap().containsKey('nominableAsAdviser'), isFalse);
      expect(e.toMap().containsKey('nominableAsPanelist'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/designation_test.dart`
Expected: FAIL — `nominableAsAdviser` is not defined.

- [ ] **Step 3: Add the fields to `AppUser`**

Add two `final bool` fields, required in the constructor with defaults, and in `fromMap`:

```dart
  /// Whether a group may nominate this account as their adviser.
  ///
  /// Set by a coordinator on the Users screen. A missing key reads as
  /// `true`: every account predates this field, and "absent means not
  /// nominable" would make the whole faculty unpickable the moment this
  /// deployed.
  final bool nominableAsAdviser;

  /// Whether a group may nominate this account onto their panel.
  ///
  /// An ex-officio seat ignores this entirely — that seat comes from the
  /// office, not from a coordinator's list (spec D32).
  final bool nominableAsPanelist;
```

In `fromMap`: `nominableAsAdviser: map['nominableAsAdviser'] as bool? ?? true,` and the same for panelist. Add both to `toMap` if `AppUser` has one — check; the coordinator's write needs them.

- [ ] **Step 4: Add the fields to `FacultyDirectoryEntry`**

Same two fields, same `?? true` default in `fromMap`. **Do NOT add them to `toMap`** — `upsertOwnEntry` round-trips through it, and the subject may not write their own designation.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/models/designation_test.dart`
Expected: PASS, all six tests.

- [ ] **Step 6: Falsify the default**

Change `?? true` to `?? false` in `AppUser.fromMap`. Re-run: the "no designation keys" test must FAIL. Restore.

- [ ] **Step 7: Run the full suite and commit**

```bash
flutter test
git add lib/data/models test/data/models/designation_test.dart
git commit -m "feat: add nomination designation to the user and directory models"
```

---

### Task 2: `users` — let a coordinator write designation

**Files:**
- Modify: `firestore.rules` (the coordinator arm at the `match /users/{uid}` block)
- Test: `rules-test/rules.test.js`

**Interfaces:**
- Produces: a coordinator may set `nominableAsAdviser` / `nominableAsPanelist` on any account but their own; `role` stays unwritable.

The existing arm reads:

```
allow update: if isCoordinator()
              && request.auth.uid != uid
              && onlyChanged(['fullName', 'college', 'program',
                              'specialization', 'active']);
```

- [ ] **Step 1: Write the failing rules tests**

Append to `rules-test/rules.test.js`, following the file's existing helpers (`seedRole` writes a `users` doc with `withSecurityRulesDisabled`; `assertSucceeds`/`assertFails`):

```js
// --- Coordinator admin: designation on users ---

test("a coordinator may set nomination designation on another account", async () => {
  await seedRole("desig-coord-uid", "coordinator");
  await seedRole("desig-faculty-uid", "faculty");

  const coordinator = env
    .authenticatedContext("desig-coord-uid", {
      email: "desig-coord-uid@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertSucceeds(updateDoc(doc(coordinator, "users/desig-faculty-uid"), {
    nominableAsAdviser: true,
    nominableAsPanelist: false,
  }));
});

// The control. Without it the test above would pass for a rule that let
// anyone write anything.
test("a faculty member may NOT set their own designation", async () => {
  await seedRole("self-desig-uid", "faculty");

  const self = env
    .authenticatedContext("self-desig-uid", {
      email: "self-desig-uid@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertFails(updateDoc(doc(self, "users/self-desig-uid"), {
    nominableAsAdviser: false,
  }));
});

test("a coordinator may NOT set designation on their OWN account", async () => {
  // request.auth.uid != uid is already in the rule; this keeps it there.
  await seedRole("selfcoord-uid", "coordinator");

  const coordinator = env
    .authenticatedContext("selfcoord-uid", {
      email: "selfcoord-uid@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertFails(updateDoc(doc(coordinator, "users/selfcoord-uid"), {
    nominableAsAdviser: false,
  }));
});

test("a coordinator may NOT smuggle a role change alongside designation",
  async () => {
    // onlyChanged() is a hasOnly over affected keys, so a write touching
    // role as well must fail entirely. This is the test that proves
    // widening the list did not widen it too far.
    await seedRole("smuggle-coord-uid", "coordinator");
    await seedRole("smuggle-target-uid", "faculty");

    const coordinator = env
      .authenticatedContext("smuggle-coord-uid", {
        email: "smuggle-coord-uid@isufst.edu.ph", email_verified: true,
      })
      .firestore();

    await assertFails(updateDoc(doc(coordinator, "users/smuggle-target-uid"), {
      nominableAsAdviser: false,
      role: "dean",
    }));
  });

test("a coordinator may still deactivate an account", async () => {
  // The pre-existing capability this milestone finally surfaces in the UI.
  await seedRole("deact-coord-uid", "coordinator");
  await seedRole("deact-target-uid", "faculty");

  const coordinator = env
    .authenticatedContext("deact-coord-uid", {
      email: "deact-coord-uid@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertSucceeds(updateDoc(doc(coordinator, "users/deact-target-uid"), {
    active: false,
  }));
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd rules-test && npm test`
Expected: the two `assertSucceeds` designation tests FAIL — `onlyChanged` does not yet list the fields. The three `assertFails` tests already pass; that is fine and expected.

- [ ] **Step 3: Widen the coordinator arm**

Add `'nominableAsAdviser', 'nominableAsPanelist'` to the `onlyChanged` list. Change nothing else. Extend the comment above the arm to say the two fields are designation, set from the Users screen, and that `role` remains unwritable.

- [ ] **Step 4: Run to verify they pass**

Run: `cd rules-test && npm test`
Expected: all pass, including the pre-existing suite.

- [ ] **Step 5: Falsify**

Remove `'nominableAsAdviser'` from the list. Re-run; the first test must FAIL. Restore.

- [ ] **Step 6: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git commit -m "feat: let a coordinator write nomination designation on users"
```

---

### Task 3: `facultyDirectory` — the three changes

**Files:**
- Modify: `firestore.rules` (`mayWriteOwnDirectoryEntry` and the `facultyDirectory` arms)
- Test: `rules-test/rules.test.js`

**Interfaces:**
- Produces: the directory carries the two designation fields; the subject may write their own entry **without** changing them; a coordinator may change **only** them, and only on an entry that exists.

**Read spec §4.2 before touching this.** It is the most delicate change in the milestone. The current function pins:

```
request.resource.data.keys().hasOnly(
  ['fullName', 'role', 'college', 'specialization'])
```

and `upsertOwnEntry` writes with `SetOptions(merge: true)`, where `request.resource.data` is the **merged result**, not the written subset. So an entry carrying designation makes that faculty member's ordinary sign-in write a six-key document and `hasOnly` refuses it. The repository comment at `faculty_directory_repository.dart:43-46` records this; **keep it and extend it.**

- [ ] **Step 1: Write the failing rules tests**

```js
// --- Coordinator admin: designation on the directory mirror ---

async function seedDirectory(uid, extra = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `facultyDirectory/${uid}`), {
      fullName: "Dr. X", role: "faculty", ...extra,
    });
  });
}

test("an ordinary sign-in upsert still succeeds on an entry that carries designation",
  async () => {
    // THE regression this task exists to avoid. Under merge:true the
    // hasOnly pin applies to the merged RESULT, so without widening it,
    // designating someone breaks their sign-in housekeeping.
    await seedRole("dir-signin-uid", "faculty");
    await seedDirectory("dir-signin-uid", { nominableAsPanelist: false });

    const self = env
      .authenticatedContext("dir-signin-uid", {
        email: "dir-signin-uid@isufst.edu.ph", email_verified: true,
      })
      .firestore();

    await assertSucceeds(setDoc(
      doc(self, "facultyDirectory/dir-signin-uid"),
      { fullName: "Dr. X", role: "faculty", college: "CICT" },
      { merge: true },
    ));
  });

test("a faculty member may NOT change their own designation in the directory",
  async () => {
    // Widening hasOnly is exactly what would open this. D27's whole point.
    await seedRole("dir-self-uid", "faculty");
    await seedDirectory("dir-self-uid", { nominableAsAdviser: false });

    const self = env
      .authenticatedContext("dir-self-uid", {
        email: "dir-self-uid@isufst.edu.ph", email_verified: true,
      })
      .firestore();

    await assertFails(setDoc(
      doc(self, "facultyDirectory/dir-self-uid"),
      { nominableAsAdviser: true },
      { merge: true },
    ));
  });

test("a faculty member may NOT introduce designation on create", async () => {
  await seedRole("dir-create-uid", "faculty");

  const self = env
    .authenticatedContext("dir-create-uid", {
      email: "dir-create-uid@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertFails(setDoc(doc(self, "facultyDirectory/dir-create-uid"), {
    fullName: "Dr. X", role: "faculty", nominableAsAdviser: true,
  }));
});

test("a coordinator may change designation on an existing entry", async () => {
  await seedRole("dir-coord-uid", "coordinator");
  await seedRole("dir-target-uid", "faculty");
  await seedDirectory("dir-target-uid");

  const coordinator = env
    .authenticatedContext("dir-coord-uid", {
      email: "dir-coord-uid@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertSucceeds(updateDoc(
    doc(coordinator, "facultyDirectory/dir-target-uid"),
    { nominableAsPanelist: false },
  ));
});

test("a coordinator may NOT change a name in the directory", async () => {
  // The coordinator writes designation and nothing else; the subject
  // owns their own name. Neither may write the other's fields.
  await seedRole("dir-coord2-uid", "coordinator");
  await seedDirectory("dir-target2-uid");

  const coordinator = env
    .authenticatedContext("dir-coord2-uid", {
      email: "dir-coord2-uid@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertFails(updateDoc(
    doc(coordinator, "facultyDirectory/dir-target2-uid"),
    { fullName: "Someone Else" },
  ));
});

test("a coordinator may NOT create a directory entry", async () => {
  // A coordinator-created entry would have no name and would appear as a
  // blank row in the nomination picker.
  await seedRole("dir-coord3-uid", "coordinator");

  const coordinator = env
    .authenticatedContext("dir-coord3-uid", {
      email: "dir-coord3-uid@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertFails(setDoc(doc(coordinator, "facultyDirectory/nobody-uid"), {
    nominableAsAdviser: false,
  }));
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd rules-test && npm test`
Expected: the first and fourth tests FAIL.

- [ ] **Step 3: Make the three changes**

1. Widen `mayWriteOwnDirectoryEntry`'s `hasOnly` to six keys.
2. Add a pin so the subject cannot change designation. On update, both fields must equal their current values; on create, neither may be present. `resource` does not exist on create, so the pin is conditional on `resource != null`. Use `.get(key, true)` on both sides so absence compares equal to absence.
3. Add a coordinator arm: `isCoordinator()` and `onlyChanged(['nominableAsAdviser','nominableAsPanelist'])` and `resource != null` (update only, never create).

Change `allow create, update:` to admit either function.

**Extend the doc comment** to record why the `hasOnly` is six keys and why the pin exists — the existing comment already explains the merge behaviour, and the next reader needs to know the widening was deliberate and is fenced.

- [ ] **Step 4: Run to verify they pass**

Run: `cd rules-test && npm test`
Expected: all pass.

- [ ] **Step 5: Falsify twice**

Narrow `hasOnly` back to four keys — the sign-in test must FAIL. Restore. Then remove the subject pin — the "may NOT change their own designation" test must FAIL. Restore. Report both outputs verbatim.

- [ ] **Step 6: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git commit -m "feat: mirror designation into the directory without letting the subject write it"
```

---

### Task 4: `nominations` — refuse an undesignated position

**Files:**
- Modify: `firestore.rules` (`mayCreateNomination`, around line 506)
- Test: `rules-test/rules.test.js`

**Interfaces:**
- Produces: a nomination whose `position` the nominee is not designated for is refused. Ex-officio is exempt.

`mayCreateNomination` already reads `roleOf(nomineeUid)` from `users`, so the designation read follows the same pattern — and **must** read `users`, never the directory (spec D27/D28).

- [ ] **Step 1: Write the failing rules tests**

```js
test("a nomination naming an adviser-only nominee as PANELIST is refused",
  async () => {
    await seedRole("nom-leader-uid", "student");
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users/nom-adviser-only-uid"), {
        fullName: "Dr. A", email: "ao@isufst.edu.ph", role: "faculty",
        college: null, program: null, specialization: null, active: true,
        createdAt: serverTimestamp(), createdBy: null,
        nominableAsAdviser: true, nominableAsPanelist: false,
      });
    });
    await seedThesis("t-nom-desig", "nom-leader-uid", "draft");

    const leader = env
      .authenticatedContext("nom-leader-uid", {
        email: "nom-leader-uid@isufst.edu.ph", email_verified: true,
      })
      .firestore();

    await assertFails(setDoc(
      doc(leader, "theses/t-nom-desig/nominations/nom-adviser-only-uid"), {
        nomineeUid: "nom-adviser-only-uid", nomineeName: "Dr. A",
        position: "panelist", exOfficio: false,
        conformeStatus: "pending", respondedAt: null, declineReason: null,
      }));
  });

// The control: the same nominee, the position they ARE designated for.
test("the same nominee succeeds as ADVISER", async () => {
  await seedRole("nom-leader2-uid", "student");
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/nom-adviser-only2-uid"), {
      fullName: "Dr. A", email: "ao2@isufst.edu.ph", role: "faculty",
      college: null, program: null, specialization: null, active: true,
      createdAt: serverTimestamp(), createdBy: null,
      nominableAsAdviser: true, nominableAsPanelist: false,
    });
  });
  await seedThesis("t-nom-desig2", "nom-leader2-uid", "draft");

  const leader = env
    .authenticatedContext("nom-leader2-uid", {
      email: "nom-leader2-uid@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertSucceeds(setDoc(
    doc(leader, "theses/t-nom-desig2/nominations/nom-adviser-only2-uid"), {
      nomineeUid: "nom-adviser-only2-uid", nomineeName: "Dr. A",
      position: "adviser", exOfficio: false,
      conformeStatus: "pending", respondedAt: null, declineReason: null,
    }));
});

test("an account with NO designation fields is still nominable", async () => {
  // Every account predates these fields. If this fails, deploying the
  // milestone makes the entire existing faculty unpickable.
  await seedRole("nom-leader3-uid", "student");
  await seedRole("nom-legacy-uid", "faculty");   // no designation written
  await seedThesis("t-nom-legacy", "nom-leader3-uid", "draft");

  const leader = env
    .authenticatedContext("nom-leader3-uid", {
      email: "nom-leader3-uid@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertSucceeds(setDoc(
    doc(leader, "theses/t-nom-legacy/nominations/nom-legacy-uid"), {
      nomineeUid: "nom-legacy-uid", nomineeName: "Dr. L",
      position: "panelist", exOfficio: false,
      conformeStatus: "pending", respondedAt: null, declineReason: null,
    }));
});

test("an EX-OFFICIO nomination ignores designation entirely", async () => {
  // Spec D32: that seat comes from the office, not from a list.
  await seedRole("nom-leader4-uid", "student");
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/nom-dean-uid"), {
      fullName: "Dean B", email: "dean-nom@isufst.edu.ph", role: "dean",
      college: null, program: null, specialization: null, active: true,
      createdAt: serverTimestamp(), createdBy: null,
      nominableAsAdviser: false, nominableAsPanelist: false,
    });
  });
  await seedThesis("t-nom-exof", "nom-leader4-uid", "draft");

  const leader = env
    .authenticatedContext("nom-leader4-uid", {
      email: "nom-leader4-uid@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertSucceeds(setDoc(
    doc(leader, "theses/t-nom-exof/nominations/nom-dean-uid"), {
      nomineeUid: "nom-dean-uid", nomineeName: "Dean B",
      position: "panelist", exOfficio: true,
      conformeStatus: "exOfficio", respondedAt: null, declineReason: null,
    }));
});
```

- [ ] **Step 2: Run to verify the first fails**

Run: `cd rules-test && npm test`
Expected: the adviser-only-as-panelist test FAILS (it currently succeeds — nothing checks designation). The other three already pass.

- [ ] **Step 3: Add the check**

Inside `mayCreateNomination`, add a designation clause to the **non-ex-officio** branch only. Read from `users/{nomineeUid}` using the same helper shape as `roleOf`, with `.get(key, true)` so absence reads as nominable. Comment it with why it reads `users` rather than the directory, referencing the existing ex-officio comment a few lines above.

- [ ] **Step 4: Run and falsify**

Run: `cd rules-test && npm test` — all pass. Then change `.get('nominableAsPanelist', true)` to `.get('nominableAsPanelist', false)`: the "no designation fields" test must FAIL. Restore.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git commit -m "feat: refuse a nomination for a position the nominee is not designated for"
```

---

### Task 5: Repository and providers

**Files:**
- Modify: `lib/data/repositories/user_repository.dart`, `lib/data/repositories/faculty_directory_repository.dart`
- Create: `lib/providers/admin_providers.dart`
- Test: `test/providers/admin_providers_test.dart`

**Interfaces:**
- Produces:
  - `UserRepository.watchAllUsers()` → `Stream<List<AppUser>>`
  - `UserRepository.setActive(String uid, bool active)` → `Future<void>`
  - `UserRepository.setDesignation({required String uid, required bool adviser, required bool panelist})` → `Future<void>` — writes `users` **and** mirrors to `facultyDirectory` if an entry exists
  - `FacultyDirectoryRepository.setDesignation({required String uid, required bool adviser, required bool panelist})` → `Future<void>` — update only, never create
  - `allUsersProvider` → `StreamProvider<List<AppUser>>`

- [ ] **Step 1: Write the failing test**

`test/providers/admin_providers_test.dart` — using `FakeFirebaseFirestore`, assert: `allUsersProvider` returns every seeded account; `setActive` flips the flag; `setDesignation` writes both fields to `users`; `setDesignation` mirrors to an **existing** directory entry; and `setDesignation` does **not** create a directory entry when none exists.

Seed the account list **against** alphabetical order (insert "Zara" before "Alma") — `fake_cloud_firestore` returns insertion order, so a fixture seeded in the expected order would pass with the sort deleted.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/providers/admin_providers_test.dart`
Expected: FAIL — `watchAllUsers` is not defined.

- [ ] **Step 3: Implement**

`watchAllUsers` mirrors `watchAll` on `ThesisRepository` — a plain `snapshots()` map, sorted by `fullName`. Doc-comment it as coordinator/dean-only, since the rules deny `list` to anyone else and watching it elsewhere surfaces a `permission-denied` the reader cannot act on.

`setDesignation` on `UserRepository` writes `users` first (the authority), then calls the directory repository's `setDesignation`, which uses `update` — not `set` — so it throws rather than creating when no entry exists. Catch that one case and swallow it: an account that has never signed in has no mirror to update, and that is expected, not an error. Comment it, and reference spec §4.2.1.

`allUsersProvider` watches `signedInUidProvider` first, like its siblings.

- [ ] **Step 4: Run, then falsify the ordering**

Run the test; delete the sort; confirm the ordering test FAILS; restore.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories lib/providers/admin_providers.dart test/providers/admin_providers_test.dart
git commit -m "feat: read every account and write designation to both records"
```

---

### Task 6: The Users screen

**Files:**
- Create: `lib/features/admin/users_screen.dart`
- Modify: `lib/core/navigation/shell_destination.dart`, `lib/core/routing/app_router.dart`
- Test: `test/features/admin/users_screen_test.dart`, `test/core/routing/shell_routes_test.dart`

**Interfaces:**
- Consumes: `allUsersProvider`, `setActive`, `setDesignation` (Task 5).
- Produces: `UsersScreen` keyed `Key('usersScreen')`, at `/users`, and a `Users` destination owning `/invites` as well.

- [ ] **Step 1: Write the failing tests**

Cover: the screen lists seeded accounts; the coordinator's **own row** renders its controls disabled with a reason; `role` renders as text with no control anywhere; there is no delete control; toggling active calls through; setting designation calls through; the filter narrows by role and by active; an account with **no directory entry** is marked "not yet signed in" (spec §4.2.1); and both `/users` and `/invites` highlight the Users destination.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/admin/users_screen_test.dart`
Expected: FAIL — `users_screen.dart` does not exist.

- [ ] **Step 3: Build the screen**

A `ConsumerStatefulWidget` holding the filter state. Columns: name and email, role (text), positions, designation, active. **No `Scaffold`, no `AppBar`** — the shell owns both.

Positions come from `myAdviseesProvider`-shaped data per user; if that proves expensive across a whole college, render the count lazily per row and say so in the report rather than blocking the list on it.

Show the refusals rather than letting them be discovered: role as text, own row disabled with its reason, no delete.

- [ ] **Step 4: Rename the destination and add the route**

In `shell_destination.dart`, the coordinator's `Faculty` destination becomes:

```dart
const ShellDestination(
  label: 'Users',
  icon: Icons.people_outline,
  route: '/users',
  alsoOwns: ['/invites'],
),
```

**This is the first thing to populate `alsoOwns`,** and a finding deferred during the app-shell milestone applies: `destinationForLocation` sorts candidate matches by `d.route.length` rather than by the length of the root that actually matched. No other destination owns `/invites`, so the tiebreak never fires today — but fix it now rather than leaving an armed trap: sort by the length of the **matched** root. Add a unit test with two destinations where the shorter `route` has the deeper `alsoOwns`, proving the fix.

Register `/users` in `app_router.dart` with a coordinator-only guard, alongside the existing `/invites` guard.

- [ ] **Step 5: Run everything**

```bash
flutter test
cd rules-test && npm test
flutter analyze
flutter build web --debug
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add the Users screen, replacing the Faculty destination"
```

---

### Task 7: Filter the nomination picker, and say why when it refuses

**Files:**
- Modify: `lib/features/thesis/nominate_screen.dart`
- Test: `test/features/thesis/nominate_screen_test.dart`

**Interfaces:** consumes `FacultyDirectoryEntry.nominableAsAdviser` / `.nominableAsPanelist` (Task 1).

- [ ] **Step 1: Write the failing tests**

An adviser-only entry appears in the adviser picker and **not** in the panel picker; a panelist-only entry the reverse; an entry with no designation appears in both; and a refused nomination renders copy naming the person and the position — *"Dr. X is not available as a panelist this semester"* — rather than a Firestore code. Assert on the copy, since the whole point is that a student who picked from a list the app showed them is not shown a permission error (spec §4.2.1).

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/thesis/nominate_screen_test.dart`
Expected: FAIL — the pickers do not filter.

- [ ] **Step 3: Filter, and add the refusal copy**

Filter each picker on the matching flag. Ex-officio entries are exempt (spec D32) — do not filter them out of the ex-officio slot.

Map a `permission-denied` on nomination submit to the plain-language message. Keep the Firestore code visible underneath, as `ErrorState` already does — the code helps you, the sentence helps them.

- [ ] **Step 4: Run and commit**

```bash
flutter test
git add lib/features/thesis test/features/thesis
git commit -m "feat: offer only designated nominees, and explain a refusal in words"
```

---

### Task 8: The D5 revision

**Files:**
- Modify: `lib/providers/faculty_mode_provider.dart`, `lib/core/navigation/shell_destination.dart`
- Test: `test/providers/faculty_mode_test.dart`

**Interfaces:** consumes `AppUser.nominableAsAdviser` / `.nominableAsPanelist`.

`faculty_mode_provider.dart:85-87` currently ends `return FacultyMode.panelist;`, reached when both position counts are zero — so every newly invited faculty member lands in panelist mode with no switch and an empty screen.

- [ ] **Step 1: Write the failing tests**

Every row of the spec §6 table, as its own test:

| Designated | Holds | Effective | Switch |
|---|---|---|---|
| both | nothing | both | yes |
| adviser | nothing | adviser | no |
| panelist | nothing | panelist | no |
| adviser | 3 panels | both | yes |
| neither | nothing | neither | no destination |
| neither | 2 advisees | adviser | no |

**The fourth row is the one that proves D30** — testing only the agreeing rows would pass with the union replaced by designation alone. Write it explicitly.

Plus: a faculty member whose profile read **fails** still gets a mode from positions alone (spec §6 degradation).

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/providers/faculty_mode_test.dart`
Expected: the "both designated, nothing held" row FAILS — it currently yields panelist.

- [ ] **Step 3: Implement the union**

Effective adviser capability is `designatedAdviser || adviserCount > 0`; likewise panelist. Both → `stored`. One → that one. Neither → a new state meaning no mode destination.

In `shell_destination.dart`, `destinationsFor` declares **neither** Advisees nor Panels when capability is neither. A destination that leads to an empty screen reads as a broken app.

On profile error, fall back to today's position-only derivation.

- [ ] **Step 4: Run, falsify, verify**

Run the test. Then replace the union with designation alone: the "adviser designated, 3 panels held" row must FAIL. Restore.

```bash
flutter test
cd rules-test && npm test
flutter analyze
flutter build web --debug
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: drive the faculty mode from designation as well as positions"
```

---

## Verification

1. `flutter test` — foreground, one run at a time.
2. `cd rules-test && npm test` — every claim in spec §4 lives here; `fake_cloud_firestore` enforces nothing.
3. `flutter analyze` — clean but for the 2 known infos.
4. `flutter build web --debug`.
5. `flutter run -d chrome` as a coordinator: the Users destination lists every account; your own row is inert; deactivating someone sticks after a reload; narrowing a faculty member to adviser-only removes them from the panel picker for a student.
6. Sign in as a **newly invited** faculty member with no positions — confirm they get the mode switch rather than an empty Panels screen.
7. Designate someone adviser-only who already sits on a panel, then sign in as them: they must still see both modes (spec D30).

## Self-review notes

- **Spec coverage.** §1 → Tasks 1–8. D27 → Tasks 1, 3, 4. D28 → Task 4. D29 → Task 7. D30 → Task 8. D31 → no task, by design; there is nothing role-specific to build. D32 → Tasks 4, 7. D33 → Task 1. §3 → Task 1. §4.1 → Task 2. §4.2 → Task 3. §4.2.1 → Tasks 5, 6, 7. §4.3 → Task 4. §5 → Task 6. §6 → Task 8. §7 → Tasks 6, 7. §8 → throughout. §9–10 → out of scope / documentation.
- **Naming consistency.** `nominableAsAdviser` / `nominableAsPanelist` are used identically in every task, in both models, both collections and all three rules.
- **Known thin spots.** Tasks 5, 6 and 7 give the interfaces, the required behaviours and the load-bearing tests, but describe some test bodies rather than writing every line — they are screen and repository work following patterns this codebase already has several examples of. Tasks 1–4, the rules, are written out in full because they are the boundary.
