# Post-Skeleton Follow-ups

Triaged output of the final whole-branch review of `feat/walking-skeleton`
(2026-08-14). The walking skeleton is complete; these are the items that were
deliberately deferred, grouped by when they need attention.

Nothing here blocks the branch. Everything blocking was fixed in commits
`1849007`â€“`d762020`.

---

## Before the defense

| # | Item | Why it matters | Fix |
|---|---|---|---|
| ~~1~~ | ~~`AppConfig.enforceInstitutionalDomain` is `false`~~ | â€” | **DONE** â€” reverted in `10bc289`. Flag is `true`; 63 tests pass, 0 skipped |
| 2 | Dean role never exercised on live infrastructure | Exit criteria Â§9.1 asks for all four roles. Covered by automated routing and guard tests, but not signed into live. | Console: set a test account's `role` to `dean`, sign in, confirm "College Overview" |
| 3 | Orphaned `users` documents have no cleanup path | `firestore.rules` sets `allow delete: if false` on `users`, so a document orphaned by a deleted auth account is permanent. One exists from a mistyped registration. | Document in Scope and Limitations â€” a real cleanup path needs Cloud Functions (Blaze) |
| 4 | Account `active` flag is inert | `AppUser.active` is parsed and a coordinator can write it, but nothing reads it. Deactivating an account currently has no effect. | Either treat `!profile.active` as force-sign-out in the router, or scope the claim in the manuscript. Full enforcement belongs in M1 |
| 5 | No test for domain-adjacent spoofs (`notisufst.edu.ph`, `isufst.edu.ph.attacker.com`) | The logic is correct and was verified by reading, but this backs a manuscript security claim and is one test | Add to `email_validator_test.dart` |

---

## Manuscript-truth items

Claims the code does not currently support. Fix the code or restate the claim.

1. **"All privileged actions written to `auditLogs`"** â€” now partially true. `role.promoted` is logged at both promotion sites (commit `1c300c8`). No other privileged action exists yet in the skeleton, so the claim holds for this branch, but M1â€“M6 must each wire their own audit calls or the claim degrades.
2. **OWASP A09 (Logging and Monitoring)** â€” supported for role promotion only. Be precise in Chapter IV about scope.
3. **"Every elevation leaves a permanent record"** â€” do not use this phrasing. Coordinators can delete and overwrite invites. The accurate claim, now reflected in `firestore.rules`, is: *the beneficiary of an elevation cannot remove its record.*
4. **Tamper-proof auditing is not achievable on Spark** â€” server-side triggers need Cloud Functions, so all audit writes are client-initiated. State this in Scope and Limitations.
5. **Supabase file access** â€” the bucket is public; files are protected by unguessable UUID paths only, not by per-user policy. Already noted in the spec; keep it in the manuscript.

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

- `AppUser.fromMap` defaulting a missing `role` key â€” `tryParse` already handles null identically, degrading to `student`
- Email regex accepting unusual local parts (`..a@`, `a.@`) â€” Firebase Auth validates independently
- `completes` matchers on thin delegating wrappers â€” appropriate for the contract being tested
- Two `use_super_parameters` style infos in a test file
- `facultyModeKey` exported as a public constant

---

## Accepted by human ruling

- **Two coordinators can promote each other to dean**, and a coordinator holding a second verifiable address can self-elevate on that second account. Rules cannot close this while coordinators may mint deans. Belongs in Scope and Limitations.

---

## Running the Firestore rules tests

`firebase-tools` 15.x requires **Java 21 or newer**. Eclipse Temurin 21 is
installed at `C:\Program Files\Eclipse Adoptium\jdk-21.0.12.8-hotspot`, but a
shell whose PATH still points at JDK 17 will fail with *"firebase-tools no
longer supports Java version before 21"*.

From Git Bash:

```bash
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-21.0.12.8-hotspot"
export PATH="$JAVA_HOME/bin:$PATH"
cd rules-test && npm test
```

Setting `JAVA_HOME` permanently in the system environment variables avoids
repeating this.

---

## Title Justification vs. built architecture â€” manuscript contradictions

The Capstone Title Justification (Title/Concept Hearing, 28 Feb 2026) describes
an architecture the project did not build. Chapter III describes the built one
correctly, so the two documents disagree with each other. Flagged for correction
before the defence; **no code change is intended** â€” the built architecture is
right for the Spark plan and is working and tested.

| Title Justification claims | What exists |
|---|---|
| Backend: Node.js + Express.js | No custom backend; the Flutter client talks to Firebase directly |
| JWT authentication and session management | Firebase Auth; the SDK manages ID tokens |
| Password hashing with bcrypt | Firebase Auth owns credentials; the app never handles a password |
| SQL queries; prevention of SQL injection | Firestore is NoSQL â€” there is no SQL anywhere in the system |
| Three-tier clientâ€“server with an Application Layer | Two-tier: client + Firebase, with security rules as the authorization layer |
| Mobile: Flutter Android **and iOS** | Android and Web only (iOS needs macOS tooling and an Apple developer account) |
| Deployment to a VPS or Firebase Hosting | Firebase Hosting |

Two further points worth correcting in the same pass:

1. **The data-flow example is wrong for this system.** It reads "Student submits
   thesis title â†’ Adviser receives notification â†’ Adviser reviews and updates
   status." In the agreed process the title defence happens *after* nomination,
   and the panel decides â€” so no adviser exists at title-submission time, and the
   adviser is not the approver.
2. **"Prevents SQL injection" cannot be claimed.** The honest OWASP claims for
   this system are A01 Broken Access Control (enforced by security rules, proven
   against the deployed rules by an independent client) and A07 Identification
   and Authentication Failures. Injection is not applicable to a NoSQL document
   store accessed through a typed SDK.

**How to defend the difference if asked:** Firestore security rules replace the
Express authorization layer, and Firebase Auth replaces both JWT session handling
and bcrypt password storage. The security boundary moved from application code to
the data layer, which is stronger â€” it holds even when a caller bypasses the app
entirely, which the verification record demonstrates.

## From M1a Task 9 (deferred by Ruling 10)

- **Nominate screen: no floor on the panel cap.** `maxPanelists = 9 - 1 - exOfficioSeatCount` can fall below the required 3 when a college has 7+ ex officio members (dean + coordinators). The screen then shows a contradictory "minimum 3, at most 1", and submit reports "Choose at least three panel members" without naming the structural cause. Cannot occur at ISUFST CICT (1 dean, 1-2 coordinators -> cap of 6-7). Fix: floor the cap and give the sub-3 case its own message.
- **Nominate screen: duplicate person across roles** is only rejected at submit, not in the dropdowns. Harmless - the repository collision precedence collapses it correctly.
- **Create-thesis screen: `kAcademicYears` is hardcoded** to 2026-2027 and 2027-2028 and will expire.
- **Nomination inbox: add `exOfficio == false` to the query** as defence in depth. The ex-officio exclusion currently rides on `conformeStatus == 'pending'`, which is sound only because the rules pin the two together at create.
- **Form 1 PDF: embed a bundled serif Unicode font.** The `pdf` package built-in Helvetica silently drops em dashes, en dashes and curly quotes (proven by probe; middot and Latin-1 accents are fine). An em dash was hyphen-substituted as a point fix, but the next curly quote or accented-beyond-Latin-1 name is lost silently. An embedded font also matches the serif face of the layout approved with the owner.
- **Stalled-thesis recovery (M1a Ruling 13).** A declined nomination stalls a thesis permanently; recovery is Console-only. Needs a coordinator "reopen" action: a rules branch letting a coordinator return a stalled thesis to `draft`, the UI for it, and a fix for `_nominationIds` being snapshotted outside the approval transaction (re-nomination adds/removes nomination docs, which breaks that assumption — store nomination ids on the thesis doc so `tx.get` can read them).
