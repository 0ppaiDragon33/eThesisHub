# eThesisHub — System Design

**Date:** 2026-08-12
**Project:** eThesisHub — A Web and Mobile-Based Thesis Management System for Campus
**Institution:** Iloilo State University of Fisheries Science and Technology (ISUFST), College of Information and Communications Technology, Main Campus – Poblacion Site
**Team:** Bagsain, Karlo June · Delos Reyes, Leonel · Eredillas, Butch S. · Solinap, Jepte · Vargas, Karl Joshua P.

**Development capacity: one developer.** Vargas builds, assisted by an AI coding assistant. The other four members do not have machines available and work on documentation. Build sequencing (§9) assumes a single sequential lane — there is no parallel development.

---

## 1. Context

This design implements the capstone described in `Revised- eThesisHub Capstonemain 1-4.docx`, revised against decisions made during design review, and aligned to the *ISUFST Guidelines for Undergraduate Thesis* (BOR Resolution No. 114, s. 2024).

The existing codebase is an unmodified Flutter scaffold — `lib/main.dart` and `cupertino_icons` only. Everything in this document is to be built.

**Stack:** Flutter (Android + Web) · Riverpod · Firebase Auth · Cloud Firestore · Supabase Storage · Firebase Spark (free) plan.

---

## 2. Decisions

Decisions taken during design review, including deviations from the manuscript as written. Each deviation creates documentation debt tracked in §11.

| # | Decision | Rationale |
|---|---|---|
| D1 | **Five actors, not six** — Research Coordinator absorbs Administrator | Coordinator already performs administrative duties; a separate Administrator actor had no distinct responsibilities |
| D2 | **Account role ≠ thesis position** | Faculty advise one group and sit on another's panel; making both account roles would force dual accounts |
| D3 | **Students nominate; coordinators do not assign** | Matches Form 1, which is the student nominating adviser and panel members with Conforme signatures. The manuscript's coordinator-assigns flow was the deviation |
| D4 | **Minimum 3 panel members, expandable** | Guidelines §4a specifies three panel members. Form 1 prints only two blanks — an inconsistency in the manual; §4a governs |
| D5 | **Faculty use an explicit Adviser/Panelist mode switch** | Two clean dashboards, easier to diagram in Chapter IV. Mode-error risks mitigated per §8.4 |
| D6 | **Firebase Auth + Firestore; Supabase for files only** | Firebase Storage now requires the Blaze (billing) plan; Supabase Storage has a free tier with no card |
| D7 | **Supabase bucket is public; no per-user file policies** | Users authenticate to Firebase, so Supabase cannot identify them. Accepted limitation, documented (§7.2) |
| D8 | **No Cloud Functions** (Spark plan) | Notifications are in-app real-time, not background push (§6.5) |
| D9 | **Faculty provisioned by invitation record** | Coordinator never handles anyone's password; avoids the client-SDK session-swap trap |
| D10 | **Defense comments are append-only** | The defense record is evidence; editable remarks make consolidated feedback worthless |
| D11 | **Riverpod for state management** | Stream providers map cleanly onto Firestore listeners; testable without widget context |
| D12 | **Form generation included** as a sixth module | Specific Objective #6 otherwise traces to no code |

---

## 3. Roles and permissions

### 3.1 Account roles

Set at the account level, stored on `users/{uid}.role`, never client-selectable.

| Role | Capabilities |
|---|---|
| `student` | Register self; create/join a thesis group; submit title; nominate adviser + 3 or more panel members; upload documents; view feedback and revision history; view own status; browse approved archive; download generated forms |
| `faculty` | Accept/decline nominations (Conforme); act as adviser and/or panelist per thesis; review documents and leave feedback; add defense comments; submit evaluations when serving as panelist; consolidate defense comments when serving as adviser |
| `coordinator` | All faculty capabilities, plus: provision faculty accounts; recommend approval of nominations; assign advisers under §1e fallback; schedule defenses; monitor all theses; manage the archive; issue Form 8 certification |
| `dean` | Final approval of nominations and titles; college-wide progress visibility; accept theses in partial fulfilment |

### 3.2 Thesis positions

Held per thesis, not per account. Written when a nomination is fully approved.

- `adviser` — exactly one per thesis
- `panelist` — three or more per thesis

A single faculty account may hold `adviser` on one thesis and `panelist` on several others simultaneously.

---

## 4. Data model (Cloud Firestore)

```
users/{uid}
  fullName, email, role, college, program, specialization,
  status, createdBy, createdAt
  # role is never client-writable except via the invite promotion path (§6.2)

facultyInvites/{email}
  role, invitedBy, createdAt
  # client-unreadable; consumed at promotion

theses/{thesisId}
  title, abstract, memberUids[], leaderUid, program, academicYear,
  adviserUid, panelistUids[], status, createdAt, updatedAt

  nominations/{nomineeUid}
    position, conformeStatus, respondedAt, declineReason,
    coordinatorRecommendedAt, deanApprovedAt

  documents/{documentId}
    type, storagePath, fileUrl, version, uploadedBy, uploadedAt,
    mimeType, sizeBytes

    revisions/{revisionId}
      version, fileUrl, feedback, reviewerUid, createdAt

defenses/{defenseId}
  thesisId, type, scheduledAt, venue, panelUids[], status, createdBy

  comments/{commentId}
    authorUid, authorName, authorPosition, text, createdAt, editedAt

  evaluations/{evaluatorUid}
    scores{}, remarks, averageRating, finalGrade, verdict, submittedAt

generatedForms/{formId}
  thesisId, formType, fileUrl, generatedBy, generatedAt

notifications/{notificationId}
  recipientUid, type, thesisId, message, read, createdAt

auditLogs/{logId}
  actorUid, action, targetType, targetId, timestamp, metadata
```

**Naming note.** The `documents/revisions` subcollection preserves the naming in the manuscript's Database Design section, so the written data dictionary remains accurate.

**`auditLogs`** gives the "visitor log" named in the Chapter I conceptual framework a concrete implementation; it is currently referenced in the input box and implemented nowhere.

### 4.1 Thesis status values

```
draft                              tentative title recorded
  → nomination_pending_conforme
  → nomination_pending_coordinator
  → nomination_pending_dean
  → nomination_approved             adviser + panel fixed (Form 1 complete)
  → title_pending_coordinator
  → title_pending_dean
  → title_approved
  → in_progress
  → pre_oral_scheduled → pre_oral_completed
  → final_defense_scheduled → final_defense_completed
  → manuscript_final → archived
```

**Ordering follows the Guidelines, not the manuscript.** §1 (Nomination of Adviser and Panel Members) precedes §3 (Proposal Preparation), and Form 2 appoints an adviser to a thesis *"with the tentative title"* — so the title is still tentative at nomination and is formally approved afterwards, under adviser supervision. The manuscript's Activity Diagram shows title approval first; that narrative needs updating (§11).

---

## 5. Workflows

### 5.1 Nomination (replaces coordinator assignment)

Mirrors Form 1 (Appendix 1).

```
Student nominates adviser + 3 or more panel members
        ↓
Each nominee accepts or declines               [Conforme]
        ↓  all accepted
Research Coordinator recommends approval       [Recommending Approval]
        ↓
Dean approves                                  [Approved]
        ↓
adviserUid + panelistUids[] written; thesis → in_progress
```

**Nominee eligibility.** Any account with role `faculty`, `coordinator`, or `dean` may be nominated to a panel position — Guidelines §4a requires the panel to include the Research Coordinator or Chair, so restricting nominees to `faculty` would make a compliant panel impossible to form. Part-time instructors may serve only as co-advisers (§1c). A coordinator serving as a panelist on a thesis still performs their coordinator duties on it; the two are independent.

- A decline returns **that slot only** to the student for re-nomination; other Conformes stand.
- Guidelines §1e fallback: where a student cannot secure an adviser, the coordinator may assign one from the faculty pool.
- Nomination cannot be submitted with fewer than three panel members.

### 5.2 Documents and revisions

Student uploads → file stored via `StorageService` → `documents` record created with an incremented `version` → adviser and panelists read all versions and write `revisions` entries carrying feedback → student uploads the next version. Full version history is retained; nothing is overwritten.

### 5.3 Defense scheduling and live comments

Coordinator schedules a defense (type, datetime, venue, panel). During the presentation, the adviser, panelists, coordinator, and dean each add comments in real time; every client holds a Firestore listener so comments appear live for all participants.

**Consolidated output** groups comments into a bracketed block per commenter:

```
[Dr. Noel A. Armada — Adviser]
  Revise the statement of the problem to be measurable.
  Add the sampling frame to Chapter III.

[Dr. Louella C. Diamante — Panelist]
  Justify the choice of respondents.
```

This automates Guidelines §4d — the adviser consolidates defense comments and furnishes a copy to the Research Coordinator.

Comments are **append-only** (§6.4).

### 5.4 Evaluation

Per-panelist scoring against Form 5c (Appendix 8):

| Criterion | Weight |
|---|---|
| **A. Content** | **50%** |
| Title | 5% |
| Introduction | 5% |
| Materials and Methods | 10% |
| Result | 10% |
| Discussion | 10% |
| Conclusion | 5% |
| Recommendation | 2% |
| References | 3% |
| **B. Presentation and Defense** | **50%** |
| Preciseness and clarity | 15% |
| Alertness in answering questions | 25% |
| Personality | 10% |

> **Known error in the source manual — confirmed as a typo by the team.** Form 5c prints Title as **50%** inside a Content section itself worth 50%, while the remaining Content items already total 45%. Title must be **5%** for Content to reach 50 and the sheet to total 100. Presentation and Defense is internally consistent (15 + 25 + 10 = 50). The system implements Title at 5%. Still worth raising with the Research Coordinator so the printed manual can be corrected.

Panel verdict is Pass/Fail per §8a, with the numeric grade computed from the rubric.

### 5.5 Form generation

Generates pre-filled, downloadable PDFs from system data using the `pdf` and `printing` packages:

| Form | Trigger |
|---|---|
| Form 1 — Nomination of Adviser and Panel Members | Nomination submitted |
| Form 3 — Request to Convene Panel for Pre-Oral Defense | Pre-oral scheduled |
| Form 4a / 4b — Change of Adviser / Change of Title | Change requested |
| Form 5a — Request for Final Oral Defense | Final defense requested |
| Form 5c — Evaluation Guide | Evaluation submitted |
| Form 7 — Certificate of Review | Panel approves reproduction |
| Form 8 — Certification of Submission of Bound Copies | Bound copies submitted |

Generated Form 1 carries **three or more** panel member rows rather than the printed form's two, per D4.

---

## 6. Security design

### 6.1 Signup

The registration form contains **no role field** — absent, not hidden. The client always writes `role: 'student'`, enforced in rules:

```
allow create: if request.auth.uid == uid
           && request.resource.data.role == 'student';
```

A caller bypassing the Flutter app and hitting the Firestore REST API directly can still only create a student.

### 6.2 Faculty provisioning

The coordinator creates `facultyInvites/{email}` holding the intended role. The faculty member registers normally (defaulting to `student`), and a rule promotes them only if an invite matching their **verified** email exists:

```
allow update: if request.auth.uid == uid
           && exists(/databases/$(db)/documents/facultyInvites/$(request.auth.token.email))
           && request.resource.data.role ==
              get(/databases/$(db)/documents/facultyInvites/$(request.auth.token.email)).data.role;
```

`exists()` and `get()` execute inside the rules engine. The coordinator never learns anyone's password.

**Invite readability.** The invitee must be able to read their *own* invite, otherwise the client cannot know which role to request in the promotion write. Access is therefore: `get` allowed when `request.auth.token.email` equals the document id; `list` denied outright; full access for coordinators. Since the document id *is* the email and the token email is verified, no one can read an invite that is not theirs, and the collection cannot be enumerated.

**Rejected alternative:** creating accounts via `createUserWithEmailAndPassword` from the coordinator's session — the client SDK swaps the active session and signs the coordinator out.

**Bootstrap:** the first coordinator is seeded by hand in the Firebase Console.

### 6.3 Additional controls

- Email verification required before any workflow write
- **Institutional domain restriction enabled** on student self-registration — all students hold `@isufst.edu.ph` accounts (confirmed). Kept as a config flag so it can be relaxed if a valid exception appears. Faculty registration is not domain-gated: promotion is bound to an invite the coordinator created for a specific address (§6.2), which is a stronger control than a domain check
- Password policy and throttling via Firebase Auth defaults
- All privileged actions written to `auditLogs`

### 6.4 Firestore rules

Deny-by-default. Authorization lives in rules, never only in Flutter — hiding a button is not access control.

| Collection | Write authority |
|---|---|
| `users` | Self, profile fields only; `role` immutable except via §6.2 |
| `facultyInvites` | Coordinator only; unreadable by clients |
| `theses` | Members while `draft`; status transitions gated per role |
| `nominations` | Student creates; **only the nominee** sets their Conforme; only coordinator sets `recommendedAt`; only dean sets `approvedAt` |
| `documents` / `revisions` | Members upload; adviser and panelists write feedback |
| `defenses` | Coordinator only |
| `comments` | **Append-only** — create by adviser/panelist/coordinator/dean; no delete; edit only within a 5-minute window, original retained |
| `evaluations` | Evaluator writes own only; coordinator and dean read |
| `auditLogs` | Create only; never update, never delete |

### 6.5 Notifications

No Cloud Functions on Spark, and the FCM API requires a service account credential that cannot ship in a client. Notifications are therefore **in-app and real-time**: the acting user's client writes to `notifications`, recipients' clients hold Firestore listeners, and `flutter_local_notifications` surfaces a tray notification while the app is running.

**Limitation:** a fully closed app is not woken. Documented in Scope and Limitations (§11).

### 6.6 OWASP mapping

| OWASP Top 10 (2021) | Control |
|---|---|
| A01 Broken Access Control | All authorization in rules; per-thesis position checks; append-only logs |
| A02 Cryptographic Failures | TLS in transit; no API secrets in the client |
| A04 Insecure Design | Role escalation treated as primary threat; role removed from the signup surface |
| A05 Security Misconfiguration | Deny-by-default rules; explicit check that test-mode rules never reach production; Supabase bucket policy audit |
| A07 Identification and Auth Failures | Email verification gate; Firebase password policy and throttling |
| A09 Logging and Monitoring Failures | `auditLogs` on every privileged action |

**OWASP MASVS** for the Android build: no secrets in the APK, tokens in platform secure storage, TLS enforced.

---

## 7. Storage

### 7.1 Abstraction

```dart
abstract class StorageService {
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  });
  Future<void> delete(String path);
}
```

**Bytes, not `File`.** `dart:io File` does not exist on Flutter web, and the web build is a stated deliverable. The interface takes bytes so a single implementation serves Android and web; `file_picker` returns bytes on both platforms.

`SupabaseStorageService` is the only implementation initially. Swapping providers — should the department later subscribe to Firebase Storage or Cloudinary — means writing one class.

Bucket `thesis-documents`; paths `theses/{thesisId}/{documentId}/{uuid}.pdf`; listing disabled; PDF and DOCX only; size-capped. URLs are stored only inside rule-protected Firestore documents.

### 7.2 Accepted limitation

Users authenticate to Firebase, so Supabase cannot identify them and its policies cannot enforce per-user file access. Anyone holding a URL can fetch the file. Mitigations are bucket-level (unguessable UUID paths, MIME allowlist, size cap, listing disabled) rather than per-user.

This is the deliberate consequence of D6 + D7 and **must appear in Scope and Limitations** rather than be implied away by §6.6.

---

## 8. Application architecture

### 8.1 Layers

Presentation (Flutter widgets) → Business logic (Riverpod providers, repositories) → Data (Firebase SDKs, Supabase SDK). No custom server; authorization is enforced at the data layer by security rules.

### 8.2 Folder structure

```
lib/
  main.dart
  app.dart                    MaterialApp, router, theme
  core/
    config/                   env, feature flags
    theme/                    light + dark ThemeData
    routing/                  GoRouter + role guards
    widgets/                  shared UI
  data/
    models/                   AppUser, Thesis, Nomination, ThesisDocument,
                              Revision, Defense, DefenseComment, Evaluation,
                              AppNotification, AuditLog
    services/                 AuthService, FirestoreService, StorageService,
                              NotificationService, AuditService
    repositories/             UserRepository, ThesisRepository, DefenseRepository
  features/
    auth/  dashboard/  nomination/  documents/
    defense/  evaluation/  repository/  forms/  notifications/
```

Screens, widgets, and providers are colocated per feature. Models and services are shared — the part five developers must not duplicate.

### 8.3 Navigation

Bottom navigation bar on mobile, navigation rail on web, switched by `LayoutBuilder`. Light and dark themes follow system preference. Routing is role-guarded via GoRouter redirects.

### 8.4 Faculty mode switch

Faculty toggle between **Adviser view** and **Panelist view** in the app bar. Mitigations for the mode-error risk inherent in this pattern:

- Mode persists across sessions (Riverpod provider backed by `SharedPreferences`)
- Notification deep links are mode-aware and switch mode automatically rather than landing on an empty screen
- The inactive mode carries a **badge count**, so pending work is never silently hidden
- Faculty holding no adviser positions are locked to Panelist mode and the toggle is hidden

---

## 9. Build sequencing

### 9.1 Walking skeleton

Built by one or two developers before the team splits. Everything after this drops into a working app.

1. Dependencies; Firebase project via FlutterFire (Android + Web)
2. Supabase project, `thesis-documents` bucket, `StorageService` behind the interface
3. `AppUser` model and `users` collection
4. Auth: register (no role field), login, email verification, password reset
5. Firestore rules v1 — deny-by-default, `users`, invite promotion
6. First coordinator seeded manually in the Console
7. Role-based routing to four dashboards
8. Faculty mode-switch shell with persisted mode and inactive-mode badge
9. Responsive shell; light and dark theme
10. `AuditService` writing to `auditLogs`

**Exit criteria:** register a student; promote a faculty member by invite; sign in as each of the four account types and reach four visibly distinct dashboards; confirm rules refuse a student writing `role: 'dean'`.

### 9.2 Modules

| Module | Scope | Depends on |
|---|---|---|
| **M1 Nomination and title approval** | Title submission, nominate 3+, Conforme, coordinator recommend, dean approve, §1e fallback | Skeleton |
| **M2 Documents and revisions** | Upload, versioning, adviser feedback, revision history | M1 |
| **M3 Defense scheduling and live comments** | Scheduling, append-only bracketed comment log, consolidation | M1 |
| **M4 Evaluation** | Form 5c rubric, per-panelist scoring, computed grade, Pass/Fail | M3 |
| **M5 Repository and notifications** | Approved-thesis archive, search and filter, notifications | Skeleton |
| **M6 Form generation** | Pre-filled PDFs for Forms 1, 3, 4a/4b, 5a, 5c, 7, 8 | M1, M3, M4 |

**M1 lands first** — every later permission check reads the positions it writes. **M5 is the most independent** and is the safest module to run in parallel with M1. M3 is the heaviest (real-time listeners plus consolidation); M4 is the most self-contained.

### 9.3 Single-lane sequencing

With one developer there is no parallelism to exploit, so modules are built strictly in thesis-lifecycle order:

```
Walking skeleton → M1 → M2 → M3 → M4 → M5 → M6
```

**Why lifecycle order rather than dependency order.** Both satisfy the dependency graph, but lifecycle order has a property that matters more here: **at every stopping point the system tells a complete story up to that stage.** Stop after M2 and you can demonstrate registration, nomination, approval, upload, and revision feedback end to end. Stop midway through a dependency-optimised order and you have scattered half-features that don't demo as a narrative. With a single developer and a fixed defense date, where you stop is the variable most likely to move.

| Order | Module | Demonstrates |
|---|---|---|
| 1 | Walking skeleton | Objective 3 (auth, RBAC) |
| 2 | **M1** Nomination and title approval | Objective 1 |
| 3 | **M2** Documents and revisions | Objective 4 |
| 4 | **M3** Defense scheduling and live comments | Objective 2 (scheduling), the distinctive feature |
| 5 | **M4** Evaluation | Objective 2 (evaluation) |
| 6 | **M5** Repository and notifications | Objective 5 |
| 7 | **M6** Form generation | Objective 6 |

**Minimum defensible build:** skeleton + M1 + M2 + M3. That covers Objectives 1, 3, 4, and half of 2, and demonstrates the feature no reviewed system in Chapter II has — live multi-role defense commenting.

**Scope risk — the largest risk in this plan.** Six modules on a single developer is ambitious. If the schedule tightens, reduce *depth* rather than dropping modules: every module traces to a Specific Objective, and a dropped module becomes an objective with no implementation, which is precisely what a panel checks. Safest reductions in order:

1. Archive search narrowed to title and author only (M5)
2. Comment consolidation exported as plain text rather than formatted PDF (M3)
3. Form generation limited to Forms 1, 5c, and 8 (M6)
4. Notifications limited to in-app badges, dropping local tray notifications (M5)

---

## 10. Out of scope

Explicitly excluded from this spec:

- **Guideline enforcement rules** — §1c five-title-per-faculty cap, §4f defense quorum, §4c/§7c manuscript lead times, §4e ethics-review gate, §9b plagiarism certification checklist. Deferred to a later spec; each is small and cites the manual directly.
- Plagiarism detection, external journal integration, automated research evaluation (already excluded in the manuscript's Scope)
- iOS deployment (requires macOS build environment and Apple Developer enrolment)
- Thesis fee tracking (§2 of the Guidelines)
- Background push to closed apps (§6.5)

---

## 11. Documentation debt

Changes required in `Revised- eThesisHub Capstonemain 1-4.docx`, parked by decision during design review:

**Chapter I**
- Specific Objective #1: "adviser assignment" → adviser and panel **nomination**
- Specific Objective #2: extend to live defense comment capture; soften "automated notifications" per §6.5
- Specific Objective #3: add OWASP alignment
- Conceptual Framework INPUT box: five roles (Panelist currently omitted)
- Conceptual Framework PROCESS box: "Adviser/Panelist Assignment" → "Adviser/Panel Nomination and Approval"; add "Defense Comment Capture"
- **Conceptual Framework narrative (three paragraphs after Figure 1.0) describes a different study** — ISSN numbers, volume/issue, published date, "generates summaries of research papers". This is journal-repository text and contradicts the IPO boxes above it. Highest-visibility defect in the document.
- Significance: merge "For Research Coordinators" and "For Department Heads" to match the five-actor set
- Definition of Terms: add OWASP, Conforme, Defense Comment Log; replace Firebase Storage with Supabase Storage
- Scope and Limitations: Supabase file-access limitation (§7.2); notification limitation (§6.5)

**Chapter II** — add an application-security subsection so OWASP has literature support; update Synthesis

**Chapter III** — add OWASP Top 10 (2021) and OWASP MASVS to Legal and Technical Basis; replace the Firebase Storage subsection with Supabase Storage

**Chapter IV**
- Requirements Analysis actor list: six → five
- Functional Requirements: nomination chain replacing assignment; live comments; role provisioning; form generation
- Non-Functional Security: OWASP mapping
- Use Case narrative: rewrite for five actors
- **Activity Diagram narrative** currently routes approval to "final endorsement by the administrator" — that step dissolves under D1; approval routes coordinator → Dean. The same narrative also places title approval before nomination; the Guidelines run nomination first (§4.1)
- Database Design: comments collection, nomination fields, generatedForms, auditLogs
- **Database Design: `documents/revisions` becomes `documents/versions` plus `documents/feedback`** (M2, decision M2-1). One version has many reviewers; the bundled shape duplicated the file across rows with nothing marking the authoritative copy
- **Database Design: `candidateTitles` carries an explicit `position`** (M1b). Firestore returns an unordered collection sorted by random auto-generated id, and a single batch write gives every candidate the identical `submittedAt`, so nothing else records the order the group chose
- **Database Design: `defenses/comments` drops `editedAt`** (M3, decision M3-7). The field recorded an edit that §5.3 and §6.4 forbid outright
- **Database Design: `defenses` gains `adviserUid` and `consolidatedAt`** (M3). The first is the historical snapshot of who advised; the second is what releases the consolidated comments to the group
- Prototype: "Adviser and Panelist Assignment Module" → "Adviser and Panel Nomination Module"; add Defense Comment Module and Form Generation Module

---

## 12. Resolved questions

1. **Institutional email** — *Resolved.* All students hold institutional accounts, so the domain restriction is enabled for student self-registration (§6.3). Faculty are governed by invite instead.
2. **Form 5c Title weighting** — *Resolved.* Confirmed a typo in the manual; implemented at 5% (§5.4).
3. **Form 1 panel rows** — *Resolved.* Three panel members confirmed; generated Form 1 carries three or more rows (D4).
4. **Version control** — *Deferred by the team.* The project is not a git repository and no version control will be used initially. With a single developer there is no merge-conflict risk. Remaining risks accepted:
   - No recovery from a lost or failed machine, and no way to roll back a change that breaks working code — the practical failure mode is an AI-assisted refactor that breaks something subtle with no diff to inspect and no revert
   - Chapter IV states *"Version control was managed using Git with a GitHub"* — this claim must either be made true or removed from the manuscript before the panel reads it (the sentence is also truncated mid-phrase in the current draft)

5. **Defense date** — *Resolved.* End of September 2026; may slip later, unlikely to move earlier. See §13.

---

## 13. Schedule

Design start 2026-08-12; defense end of September 2026. Roughly seven weeks.

**The real development deadline is not the defense date.** Chapter IV commits to User Acceptance Testing with an ISO/IEC 25010 instrument, and Chapter I's hypothesis is tested against those responses. That requires a working system in front of respondents, then collected responses, then statistical analysis, then the results written into Chapter IV — none of which can start until the build is demonstrable. Budget two weeks for it.

| Window | Work |
|---|---|
| Week 1 | Walking skeleton (§9.1) |
| Week 2 | M1 Nomination and title approval |
| Week 3 | M2 Documents and revisions |
| Weeks 4–5 | M3 Defense scheduling and live comments · M4 Evaluation |
| Week 5 | **Feature freeze** — minimum defensible build complete |
| Weeks 6–7 | M5 and M6 if the schedule holds; UAT, ISO 25010 evaluation, statistical analysis, Chapter IV results |

**Implication:** code must be demonstrable by around **mid-September**, not end of September. M5 and M6 are the modules most likely to be squeezed, which is why the §9.3 depth reductions are listed in advance rather than improvised under pressure.

Documentation debt (§11) is worked by the four non-developing members in parallel throughout, not deferred to the final weeks.
