# Post-Skeleton Follow-ups

Triaged output of the final whole-branch review of `feat/walking-skeleton`
(2026-08-14). The walking skeleton is complete; these are the items that were
deliberately deferred, grouped by when they need attention.

Nothing here blocks the branch. Everything blocking was fixed in commits
`1849007`–`d762020`.

---

## Before the defense

| # | Item | Why it matters | Fix |
|---|---|---|---|
| 1 | `AppConfig.enforceInstitutionalDomain` is `false` (commit `481192d`) | The manuscript's Scope and Limitations states registration is restricted to institutional addresses. That claim is untrue while this is false. | `git revert 481192d`, then confirm 64 passing / 0 skipped |
| 2 | Dean role never exercised on live infrastructure | Exit criteria §9.1 asks for all four roles. Covered by automated routing and guard tests, but not signed into live. | Console: set a test account's `role` to `dean`, sign in, confirm "College Overview" |
| 3 | Orphaned `users` documents have no cleanup path | `firestore.rules` sets `allow delete: if false` on `users`, so a document orphaned by a deleted auth account is permanent. One exists from a mistyped registration. | Document in Scope and Limitations — a real cleanup path needs Cloud Functions (Blaze) |
| 4 | Account `active` flag is inert | `AppUser.active` is parsed and a coordinator can write it, but nothing reads it. Deactivating an account currently has no effect. | Either treat `!profile.active` as force-sign-out in the router, or scope the claim in the manuscript. Full enforcement belongs in M1 |
| 5 | No test for domain-adjacent spoofs (`notisufst.edu.ph`, `isufst.edu.ph.attacker.com`) | The logic is correct and was verified by reading, but this backs a manuscript security claim and is one test | Add to `email_validator_test.dart` |

---

## Manuscript-truth items

Claims the code does not currently support. Fix the code or restate the claim.

1. **"All privileged actions written to `auditLogs`"** — now partially true. `role.promoted` is logged at both promotion sites (commit `1c300c8`). No other privileged action exists yet in the skeleton, so the claim holds for this branch, but M1–M6 must each wire their own audit calls or the claim degrades.
2. **OWASP A09 (Logging and Monitoring)** — supported for role promotion only. Be precise in Chapter IV about scope.
3. **"Every elevation leaves a permanent record"** — do not use this phrasing. Coordinators can delete and overwrite invites. The accurate claim, now reflected in `firestore.rules`, is: *the beneficiary of an elevation cannot remove its record.*
4. **Tamper-proof auditing is not achievable on Spark** — server-side triggers need Cloud Functions, so all audit writes are client-initiated. State this in Scope and Limitations.
5. **Supabase file access** — the bucket is public; files are protected by unguessable UUID paths only, not by per-user policy. Already noted in the spec; keep it in the manuscript.

---

## Later modules

| Item | Module | Note |
|---|---|---|
| `AppUser.toMap()` emits `createdAt` as `DateTime`, which `firestore.rules` (`createdAt == request.time`) would reject | M1 | Currently used only by its own round-trip test. Delete it or document as read-side only before anything writes profiles with it |
| Dashboard nav destinations are decorative (`selectedIndex: 0`, `onDestinationSelected` is a no-op) | M1 | When real tabs arrive, use `ShellRoute` + `StatefulNavigationShell`. The cross-role guard compares `state.matchedLocation` against a flat dashboard list and will need prefix matching once dashboards have children |
| `promoteFromInvite` throws if the user document is absent | M1 | Only reachable via an orphan; should return null instead |
| `createInvite` accepts `UserRole.student`, which the rules reject | Coordinator UI | Becomes a silent `permission-denied` the moment an invite UI ships. Add a client-side guard then |
| Faculty toggle and badge branches are untested | M1 | Genuinely unreachable until `adviserPositionCountProvider` returns real data |
| Stale `email_verified` token claim | M1 | `reload()` refreshes the user record but not necessarily the ID token claim the rules read, so promotion on the verify screen can `permission-denied` and silently retry at next sign-in. Self-healing, but the first audit entry may be attributed to the later login |
| Registration's "could not send verification email" message is unreachable | Low priority | The router redirects to `/verify-email` before `submit()` returns, so the widget unmounts and drops the message. The rollback fix itself is correct; only the signal is lost. Consider surfacing it on the verify screen instead |
| `SignOutButton` hardcodes `Key('signOut')` while also accepting `super.key` | Low priority | Two instances in one `actions` list would collide. Not currently reachable |

---

## Deliberately not doing

These were raised during review and judged not worth acting on:

- `AppUser.fromMap` defaulting a missing `role` key — `tryParse` already handles null identically, degrading to `student`
- Email regex accepting unusual local parts (`..a@`, `a.@`) — Firebase Auth validates independently
- `completes` matchers on thin delegating wrappers — appropriate for the contract being tested
- Two `use_super_parameters` style infos in a test file
- `facultyModeKey` exported as a public constant

---

## Accepted by human ruling

- **Two coordinators can promote each other to dean**, and a coordinator holding a second verifiable address can self-elevate on that second account. Rules cannot close this while coordinators may mint deans. Belongs in Scope and Limitations.
