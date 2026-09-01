# M5a — The thesis archive

Chapter I's role table gives every student the right to *"browse approved
archive"*, and the coordinator the duty to *"manage the archive"*.
Neither is built. The lifecycle in `2026-08-12-ethesishub-design.md` ends
`manuscript_final → archived`, but `ThesisStatus` stops at
`titleApproved` — **there is no archived state anywhere in the code, and
nothing sets one.**

So this is not a search feature laid over existing data. It needs a
terminal state, a person empowered to set it, a published record, and a
read rule for an audience the app has never had: the whole college.

Guidelines §9–§11 describe what happens between passing a defence and
being archived — grammar and plagiarism checking, R&D certification, the
panel signing Form 7, three bound copies to the Dean, the Library and
R&D, then Form 8. Almost all of it is on paper, outside this system. The
design's job is to record the end of that sequence truthfully, not to
simulate it.

## 0. Scope

**M5 as written in the original design doc is two independent
subsystems** — the archive, and notifications. They share no data, no
rules and no screens. They are therefore two specs. This is the first.
Notifications are **not** in scope here and get their own.

## 1. What this delivers

- A **final manuscript upload**: one consolidated PDF plus an abstract,
  submitted by the student after their final defence passes.
- **`archive/{thesisId}`** — a published, frozen snapshot, created by the
  coordinator.
- An **`/archive` destination for every role**, with search over title and
  author and filters for college, program and academic year.
- An **entry screen** with the full abstract and a link that opens the
  manuscript.
- A **coordinator queue** of theses waiting to be archived.
- **`ThesisStatus.archived`**, the terminal state the lifecycle has always
  named and never had.

## 2. Decisions taken

Numbering continues from the M4 spec, which ended at D47.

**D48 — The archive is a separate collection, not a view over `theses`.**
`theses` has the tightest read rules in the app: a thesis is visible to
its group, its adviser, its panel, the coordinator and the dean. Serving
the archive from it would mean adding *"…or anyone, if archived"* to that
rule, and then every student's archive query becomes a `list` over the
collection holding every unarchived thesis in the college.

This project has shipped four access bugs, and M3 established that a list
query must filter on exactly the field the matching rule arm reads. That
is a sharp edge to grind against on the collection where a mistake is
most expensive. A separate collection makes the rule trivial and
impossible to get wrong: **`archive` is readable by any signed-in user**,
and it cannot leak an unarchived thesis because unarchived theses are not
in it.

**D49 — The entry is a frozen snapshot.** Title, member names, adviser
and panel names are resolved once, at archive time, and never consulted
again. If a name is corrected next semester or a panel is reshuffled, the
archived record still says who actually did the work. This is the same
reasoning behind M3 snapshotting `panelUids` onto a defence and M4
denormalizing `evaluatorName` onto an evaluation. A publication should be
fixed.

The cost is duplication — the title exists in two places — and that is the
standard trade for a published record.

**D50 — One consolidated manuscript, not the five chapters.** M2 stores
Chapters I–V separately, each versioned, each carrying feedback. Those are
working artifacts. Linking them would mean the archive's contents change
whenever someone uploads a revision, and a reader would get a jigsaw
rather than a thesis.

§9c has the student *reproduce the final manuscript* and §10a has them
bind it — the physical object deposited in the Library is one document.
The archive matches it. The cost is one more upload at a moment when the
student is already doing paperwork.

**D51 — The student uploads; the coordinator archives.** Two acts, two
roles, matching the role table. The coordinator's click asserts something
the system genuinely cannot verify: that Form 8 was issued and three bound
copies reached the Dean, the Library and R&D.

That is deliberate, and it is the same shape as M4's §8b verdict — a human
recording a fact from outside the system rather than the system pretending
to know it. Archiving on upload would be simpler and would let a thesis
into the archive before the bound copies exist, making the coordinator's
stated duty a fiction.

**D52 — The gate is a Pass on a final defence, enforced in the rules.**
M4 records `panelVerdict` on the defence. A thesis that failed, or whose
verdict was never recorded, cannot be archived — not by a coordinator who
clicks the wrong row, and not by anyone with the SDK.

The entry carries `finalDefenceId` so the rule can `get()` that defence
directly. Rules cannot query, so without the id there would be no way to
find "the final defence for this thesis" at all.

**D53 — The pending manuscript lives on the thesis, not in `archive`.**
This corrects the first draft of this design, and the rules are what
exposed it: a Firestore `list` evaluates its rule against every document
returned, so a single pending entry in `archive` would fail a student's
query and break the whole screen.

Keeping the upload on `theses/{id}` means the existing per-thesis rules
already cover exactly the right readers, and `archive` contains nothing
but archived entries. The read rule then needs no presence gate.

**D54 — Search runs on the client.** Firestore has no substring or
full-text search. `where('title', isGreaterThanOrEqualTo: q)` matches
prefixes only, so a student typing *fisheries* would never find *A Study
of Coastal Fisheries*. One query loads the archive and filtering happens
in Dart.

At a college's scale — hundreds of theses across years — this is correct
and fast. **At thousands it needs a real index service**, and the limit is
recorded here rather than discovered later.

**D55 — Search covers title and author only.** The original design's §9.3
listed this as a pre-agreed depth reduction under schedule pressure. Kept.
The abstract is displayed but not searched.

**D56 — An abstract is required at upload.** Search and browse are
different acts. A student skimming twenty entries for prior work needs to
know what each study was about, and titles in this corpus are long and
similar. The abstract already exists in the manuscript, so it is a
copy-paste rather than new writing.

**D57 — The archive entry is updatable and deletable by the coordinator.**
A departure from this project's habit, and deliberate. Everywhere else the
answer is `allow delete: if false`, because the record is evidence. An
archive entry is not evidence of a process — it is a **publication**.

- **Update**, display metadata only: a typo in a permanent public record
  has to be fixable. Never the manuscript URL, never the archive stamps.
- **Delete**: if the wrong thesis is published — someone else's work, made
  readable to the whole college — it must be retractable. Refusing would
  make an accident permanent.

**Honest cost:** a deletion leaves no trace, because `auditLogs` is named
in the original design and built nowhere. Saying so plainly is better than
pretending `if false` would be principled here.

**D58 — Archived manuscripts are effectively public.** §7.2 already
accepts that the Supabase bucket is public and anyone holding a URL can
fetch the file, with unguessable paths as the only protection. Publishing
that URL in the archive makes discoverable what was already reachable.

For an approved, bound, Library-deposited thesis that is defensible — §10a
puts a physical copy in the Library for exactly this purpose. But it means
an archived manuscript is readable by anyone with the link, not only
signed-in students, and **that belongs in Scope and Limitations beside
§7.2** rather than being discovered later.

## 3. Data model

### 3.1 `theses/{thesisId}` — four new fields

```
manuscriptPath        storage path, unguessable
manuscriptUrl         the public Supabase URL
manuscriptAbstract    supplied by the student
manuscriptUploadedAt
```

Absent on every existing thesis, so all four read as nullable and every
screen must handle absent. `ThesisStatus` gains **`archived`**.

`thesisStage()` switches exhaustively over `ThesisStatus` on purpose — its
own comment says a status added later should fail at compile time rather
than vanish silently from a chart. Adding `archived` will trip exactly
that, which is the safety net working.

### 3.2 `archive/{thesisId}`

Keyed by thesis id, so a thesis is archived at most once and duplication
is impossible by construction.

```
title            resolved from the approved CandidateTitle's titleText
memberNames      already names on the thesis
abstract
college          program          academicYear
adviserName      panelNames[]     resolved from the directory
manuscriptUrl    manuscriptPath   
finalDefenceId   the defence whose Pass authorises this
uploadedAt       uploadedBy
archivedAt       archivedBy
```

Everything is resolved and frozen at archive time. `approvedTitleId` points
at a `CandidateTitle`, and `adviserUid`/`panelistUids` are uids, so all
three are read once and copied. After creation the entry consults no other
document — that is what makes it a publication rather than a live view.

## 4. Permissions

```
match /archive/{thesisId} {
  function thesis() {
    return get(/databases/$(database)/documents/theses/$(thesisId)).data;
  }
  function incoming() { return request.resource.data; }
  function finalDefence() {
    return get(/databases/$(database)/documents/defenses/
               $(incoming().finalDefenceId)).data;
  }

  // The whole college reads the archive, and there is nothing else in
  // here to leak: a manuscript awaiting archiving lives on its thesis
  // (D53), under the per-thesis rules that already exist.
  allow get, list: if signedIn();

  allow create: if verified()
                && isCoordinator()
                && incoming().archivedBy == request.auth.uid
                && incoming().archivedAt == request.time
                // The manuscript must be the one the STUDENT uploaded --
                // a coordinator cannot publish a different file.
                && incoming().manuscriptUrl == thesis().manuscriptUrl
                // D52. Rules cannot query, so the entry names the defence
                // and this verifies it is the right one.
                && finalDefence().thesisId == thesisId
                && finalDefence().type == 'final'
                && finalDefence().panelVerdict == 'pass';

  // D57: display metadata only. Never the manuscript, never the stamps.
  allow update: if verified() && isCoordinator()
                && incoming().diff(resource.data).affectedKeys()
                   .hasOnly(['title', 'abstract', 'memberNames',
                             'adviserName', 'panelNames']);

  allow delete: if verified() && isCoordinator();
}
```

Three document reads on create — the thesis, the defence, and the
coordinator's own profile for `isCoordinator()` — comfortably inside the
budget.

**What this deliberately does not verify.** The title text, member names,
and adviser and panel names are copied by the client and checked by
nobody. Verifying them would need a fourth `get` into the titles
subcollection and a fifth into the directory, to defend against a
coordinator mistyping a display string. The rules exist to stop the wrong
*thesis* reaching the wrong *audience*; they are not a spellchecker. The
line is drawn explicitly, because "validate everything" is how a rules
file becomes unmaintainable.

**The thesis-side upload** extends the existing leader arm on `theses` to
permit the four new fields, written only by the group's own leader.

**It does NOT gate on the final defence, and it cannot.** A thesis does
not know its own defence id, and rules cannot query — the same constraint
that forces `finalDefenceId` onto the archive entry in D52. Gating the
upload would mean denormalizing that id onto the thesis, and adding a
write path for it, to prevent something harmless.

Uploading a manuscript early is not a security problem: it sits on the
group's own thesis, readable by exactly the people who could already read
everything else there. **Publishing** it is the act that matters, and that
is gated. The upload button is hidden until the Pass is recorded, so the
UI still tells the truth; the rule simply does not duplicate a check it
cannot express. Recorded here so a later reader does not mistake the
absence for an oversight.

## 5. Screens

### 5.1 `/archive` — every role

Archive joins `destinationsFor` for all five roles, unconditionally. It is
the only destination in the app not scoped to what the reader is involved
in, which is the point: a student browses theses they had nothing to do
with.

One card per entry — title, authors, year, program, and the opening lines
of the abstract. A single search box over title and author (D55), and
filters for college, program and academic year. All filtering is in Dart
over one loaded list (D54).

### 5.2 `/archive/:thesisId` — the entry

Title, authors, the abstract in full, adviser and panel, college, program,
year, and **Open manuscript** — which leaves the app. The bucket is public
and there is no in-app PDF viewer, so the URL opens in the browser.

### 5.3 The student's upload

On the thesis screen, appearing only once the final defence carries a
Pass. Two fields, the PDF and the abstract, reusing `StorageService`'s
existing validation, MIME allowlist and size cap. After upload it shows as
submitted and awaiting the coordinator, so the group can see where they
stand.

### 5.4 The coordinator's queue

A queue of theses that passed their final defence and have a manuscript
uploaded but are not yet archived. **A queue, not a button on a thesis
page**: otherwise the coordinator must already know which theses are
waiting. M2 shipped a flow nothing navigated to, and this is the shape
that prevents it.

## 6. Error handling

**An empty archive and a failed read must never render the same.** This
project has shipped four bugs from treating a missing document as a
settled answer. An empty archive says *No theses have been archived yet*;
a failed read says it failed, with the Firestore code. A student will see
the first constantly in the early days and must never see it when the
truth is the second.

A denied archive attempt names the reason — no manuscript, no passed final
defence, already archived — rather than a bare `permission-denied`.

## 7. Testing

**Rules, in the emulator.** Nothing here is provable in
`fake_cloud_firestore`, which enforces no rules:

- Any signed-in user reads the archive; a signed-out one does not.
- Only a coordinator creates; adviser, panelist, leader and dean are all
  refused.
- Create is denied when the named defence is pre-oral, belongs to another
  thesis, or has no Pass — and denied when `panelVerdict` is `fail`.
- Create is denied when `manuscriptUrl` differs from the thesis's.
- Update touching `manuscriptUrl` or `archivedAt` is denied; a title
  correction succeeds.
- A student may attach a manuscript to their own thesis and **not** to
  another group's. Note there is deliberately no test that an undefended
  thesis refuses a manuscript — the rule does not check that and cannot
  (see §4); a test asserting it would be asserting a fiction.

**Widget tests.** Search matches mid-string, not just prefixes — the
specific failure D54 exists to avoid. Filters combine. An empty archive
and a failed read render differently. The upload appears only after a
Pass. The coordinator's queue lists exactly the waiting theses.

Two contracts this codebase has broken before: a loading test must
`pump()` once, never `pumpAndSettle()`, which resolves the stream and
makes the assertion vacuous; and any ordering test must write documents
out of order, because `fake_cloud_firestore` returns insertion order.

## 8. Out of scope

- **Notifications** — the other half of the original M5 line item, its own
  spec.
- **In-app PDF viewing.** The manuscript opens in the browser.
- **Full-text search**, and search over the abstract (D54, D55).
- **`auditLogs`.** Named in the original design, built nowhere, and its
  absence is what makes D57's deletion untraceable.
- **Any of §9–§11's paper steps** — plagiarism checking, Form 7
  signatures, Form 8 issuance. The system records that the sequence
  finished; it does not run it.

## 9. Documentation debt

1. **Scope and Limitations gains D58** — archived manuscripts are
   effectively public, beside the existing §7.2 entry.
2. The original design's lifecycle names states this build does not have
   (`in_progress`, `manuscript_final`). This milestone adds `archived`
   only; the intermediate names remain aspirational and should either be
   built or struck from the manuscript.
3. Carried forward and still open: Form 5c's Title 50% typo, the 5c/6c
   numbering inconsistency, and Form 5c's undefined "Average Rating".
