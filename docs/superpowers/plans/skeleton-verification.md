# Walking Skeleton — Verification Record

**Date:** 2026-08-14
**Branch:** `feat/walking-skeleton`
**Firebase project:** `ethesishub-43a04` (Spark plan, `asia-southeast1`)
**Verified by:** Karl Joshua P. Vargas

Evidence for the exit criteria in `docs/superpowers/specs/2026-08-12-ethesishub-design.md` §9.1.

---

## Automated verification

| Check | Command | Result |
|---|---|---|
| Dart analyzer | `flutter analyze` | 2 style infos (`use_super_parameters`, test file only) |
| Dart unit + widget tests | `flutter test` | **56 passed, 3 skipped** |
| Firestore rules tests | `cd rules-test && npm test` | **22 passed** (Firebase Emulator Suite) |
| Rules deployment | `firebase deploy --only firestore:rules` | Deploy complete → `ethesishub-43a04` |

The three skipped Dart tests are the institutional-domain checks, skipped because
`AppConfig.enforceInstitutionalDomain` is temporarily `false` for testing
(see Open Items).

---

## Manual verification against live infrastructure

### 1. Registration — PASS

Registered through the app with no role selector present on the form. Firebase Auth
account created, Firestore `users/{uid}` document written with `role: "student"`,
`active: true`, `createdAt` set, and a verification email delivered.

*Incidental finding:* a first attempt used a mistyped address
(`karljoshua_vagas67@…` instead of `karljoshua_vargas67@…`). The account was created
and the verification email sent to the mistyped address, and the subsequent sign-in
with the correct spelling was correctly rejected. System behaved correctly throughout;
the domain check cannot detect a typo in the local part.

### 2. Coordinator bootstrap — PASS

`users/GxGVYFzc47gFF8fuxmVw4OsGIvS2.role` changed from `student` to `coordinator`
by hand in the Firebase Console (the one-time bootstrap; all later coordinators
arrive by invite). On reload the account routed to the **coordinator dashboard**
("All Theses") rather than the student dashboard.

### 3. Invite-based faculty promotion — PASS

`facultyInvites/samakru929@gmail.com` created in the Console with
`role: "faculty"`, `invitedBy: "GxGVYFzc47gFF8fuxmVw4OsGIvS2"`, `consumedAt: null`.

That address registered, verified, and signed in. Result: routed to the **faculty
dashboard** ("My Advisees"), confirming the promotion applied. The invite document
survived with `consumedAt` set — consumed invites are marked, not deleted, so the
elevation leaves a permanent record.

### 4. Role routing — PARTIAL

| Role | Dashboard | Verified |
|---|---|---|
| `student` | My Thesis | Yes |
| `faculty` | My Advisees | Yes |
| `coordinator` | All Theses | Yes |
| `dean` | College Overview | **Not yet exercised on live infrastructure** |

The dean route is covered by the automated routing tests (including the cross-role
guard tests, which were verified to fail when the guard is removed), but has not
been signed into against the live project.

### 5. Privilege escalation refused — PASS

Tested from an **independent Firebase client** initialised in the browser console
under a separate app name, using only the public web config and a student account's
own credentials. The Flutter UI was not involved, so this exercises the deployed
security rules directly — the scenario a UI-level role check cannot defend.

Signed in as `kirayuuki54@gmail.com` (`prDnW591wcXffvhVXgVmu1rxHdz1`, role `student`):

```
signed in as: kirayuuki54@gmail.com prDnW591wcXffvhVXgVmu1rxHdz1
PASS - self-promotion denied: permission-denied
PASS - invite enumeration denied: permission-denied
```

- Writing `role: "dean"` to the account's own `users` document → **permission-denied**
- Enumerating the `facultyInvites` collection → **permission-denied**

This is the evidence behind the OWASP A01 (Broken Access Control) claim: authorization
is enforced at the data layer, not in the client.

### 6. Responsive layout — PASS

Below the 900px breakpoint the navigation rail is replaced by a bottom navigation bar.

---

## Open items

1. **`AppConfig.enforceInstitutionalDomain` is `false`** (commit `481192d`) so the
   invite flow could be tested without a second ISUFST account holder.
   **Must be reverted before the defense** — the manuscript's Scope and Limitations
   states registration is restricted to institutional addresses, which is untrue
   while this flag is false. Revert with `git revert 481192d`.
2. **Dean role not exercised live** (§4 above).
3. **Orphaned `users` documents.** Deleting a Firebase Auth account leaves its
   Firestore `users` document behind, because the rules set `allow delete: if false`
   on that collection. One such orphan exists from the mistyped registration.
   No cleanup path exists for coordinators.

---

## Notes for Chapter IV

- Integration testing via the Firebase Emulator Suite is accurate as written: 22 rules
  tests run against the emulator on every `npm test`.
- The escalation evidence above is stronger than a UI-level demonstration and is
  worth describing precisely: an independent client, public configuration only,
  a legitimate student credential, and the write still refused.
- Tamper-proof auditing is **not** achievable on the Spark plan — server-side triggers
  need Cloud Functions, so audit writes are client-initiated. The defensible claim is
  that invite records cannot be quietly removed by the person who benefits from them,
  not that the audit trail is tamper-proof.
