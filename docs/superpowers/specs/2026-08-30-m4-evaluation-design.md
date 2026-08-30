# M4 — Evaluation

M3 gave a defence a room: the panel comments while it runs, the
adviser consolidates, the group reads what was said. That covers
Guidelines §9a — *"the student consolidates and incorporates all
comments, suggestions, and recommendations of the Thesis Panel
Members"*. It does not produce a grade.

§8a is explicit about what is still missing:

> The Thesis Panel Members shall rate the student using the Pass or
> Fail grading scheme. The evaluators should also complete Research
> Form 5c (Appendix 8: Evaluation Guide) so that a numerical grade
> value could be given to the student.

This milestone builds Form 5c: eleven weighted criteria scored by each
panelist, per-criterion comments on the eight Content items, a Pass or
Fail rating from each panelist, a sealed release, and the deliberated
verdict §8b assigns to the panel as a body.

The original design doc (`2026-08-12-ethesishub-design.md`, line 100)
sketched `evaluations/{evaluatorUid}` with `scores`, `remarks`,
`averageRating`, `finalGrade`, `verdict`. That sketch predates the
scale decision and is superseded here; §3 below is authoritative.

## 1. What this delivers

- An **evaluation sheet** per panelist per defence — eleven scores,
  eight optional comments, and that panelist's own Pass/Fail rating.
- A **live sectioned total**: Section A out of 50, Section B out of
  50, Final Grade out of 100, with no conversion step.
- A **seal**. Before release a panelist sees only their own sheet;
  after it, the panel, the adviser, the coordinator and the dean see
  all of them.
- **Release**, the adviser's act, mirroring consolidation.
- The **§8b verdict** — deliberated by the panel, recorded once by the
  adviser, never computed.
- Two routes off the defence room, and the entry points that reach
  them.

Applies to **both** pre-oral and final defences. The Guidelines
publish one evaluation form, not two.

## 2. Decisions taken

Numbering continues from the coordinator-admin spec, which ended at
D33.

**D34 — Scores are points out of each criterion's own weight.** Title
is marked 0–5, Alertness 0–25. The eleven therefore sum to the Final
Grade out of 100 with no weighting arithmetic anywhere in the app.

The alternative was a uniform scale — every criterion marked 1–5, then
multiplied by its weight. That reads more consistently to a panelist,
but it puts a conversion between what was entered and what was
recorded, and every such conversion is a place the displayed grade and
the stored grade can disagree. Form 5c already prints the weights next
to the criteria; scoring out of them keeps the screen and the paper
saying the same thing.

The cost is real and is accepted: eleven criteria with eleven
different maximums (5, 5, 10, 10, 10, 5, 2, 3, 15, 25, 10) give a
panelist no rhythm to settle into. §5 answers that with a stepper
rather than a free number field, so an out-of-range value is
unreachable instead of merely rejected.

**D35 — Title is 5%, not the 50% the form prints.** Appendix 8 lists
`1.Title (50%)`, which would make Section A sum to 95 against its own
stated 50% and the whole form to 145. Every other criterion in the
appendix is internally consistent. This is a typo in the manual and is
treated as one.

The weights table in Dart carries a comment saying so, because the
next person to hold Form 5c beside this code will otherwise assume the
code is wrong. It also goes on the list to raise with the Research
Coordinator — see §11.

**D36 — All eleven criteria are always scorable, on both defence
types.** A pre-oral defence has no Results chapter to speak of; a
panelist may still mark it. The panel scores what was presented, and a
criterion that could not be demonstrated is a low score with a comment
saying why, not a hidden field. Suppressing criteria by defence type
would also mean two different denominators, and §8a's numerical grade
would stop being comparable across the two defences.

**D37 — Panelists score. The adviser comments but never scores.** The
adviser is not in `panelUids`, and the rules refuse an evaluation
document from them. The reason is the user's, recorded verbatim
because it is the whole justification: *advisers could be bias*. The
adviser has spent months on this thesis and cannot mark it at arm's
length.

The adviser is not silenced — they comment in the M3 room like
everyone else, and they hold two acts nobody else holds (§6).

**D38 — There are two comment channels, and they stay separate.** The
M3 room log is §9a: what to improve, and the panel's recommendations,
addressed to the group. Form 5c's per-criterion comments are §8a:
scored assessment against a named criterion, addressed to the record.
Merging them would mean either scoring the room log or releasing
per-criterion marking notes to the group as if it were revision
guidance. They have different audiences and different release gates.

**D39 — Sealed until the adviser releases, mirroring
`consolidatedAt`.** Before release a panelist reads only their own
evaluation. This is not a courtesy: a panelist who can see two
colleagues at 78 and 81 before marking is anchored, and §8b's
deliberation is worth less if the numbers converged before anyone
spoke.

The mechanism is `evaluationsReleasedAt` on the defence — a timestamp,
absent until set, set once, exactly as `consolidatedAt` already works
in `firestore.rules`. Reusing the shape means one pattern to
understand rather than two.

**D40 — Release is a human act, and can happen at 2 of 3.** Firestore
rules cannot count the documents in a collection, so "all panelists
have submitted" is not expressible as a rule. The adviser could
release early.

This is a real limitation and is stated rather than glossed. It is
mitigated, not closed: the grades screen shows "2 of 3 submitted"
prominently and the release button carries the count, so releasing
early is a visible choice rather than an accident. The same is already
true of consolidation, which the adviser may release with one comment
in the log.

**D41 — The verdict is deliberated by humans and never computed.**
§8b: *"Should there be problems on the result of the final grades of
the student, the Thesis Panel Members will deliberate and decide
whether to pass or fail the student."* The Guidelines hand the
decision to a conversation. Deriving it — majority of the Pass/Fail
ratings, or a threshold on the mean grade — would be the system
overruling a body the manual says decides.

So there are two distinct things, and the screens must not blur them:
each panelist's **own rating** under §8a, and the panel's **verdict**
under §8b.

**D42 — The adviser records the verdict.** They already consolidate
for this defence, so the act sits with the person who already holds
the closing duties. `verdictRecordedBy` stores their uid, because a
person barred from scoring must be visibly a scribe: the field exists
so a reader can tell the adviser transcribed a decision rather than
made one.

**D43 — Release precedes the verdict.** §8b has the panel deliberate
over the final grades, so they must be able to see them. The sequence
is therefore: all panelists submit → adviser releases → the panel
deliberates with every grade and every rating visible → the adviser
records what they decided. The rules enforce the last step's
dependency: no verdict may be written before
`evaluationsReleasedAt` exists.

**D44 — An evaluation is editable until release, then frozen.** The
document existing is what counts toward "2 of 3 submitted", so there
is no separate draft state to reason about. Freezing on first submit
would make a mistyped 2-instead-of-20 permanent in a record that has
no delete.

This differs deliberately from M3 comments, which are append-only from
the moment they are written (D10). A comment is an utterance in a
live room; an evaluation is a form being filled in. Freezing each at
the point where it becomes part of the record gives the same guarantee
by different means.

**D45 — All eleven scores are required; comments are optional.** A
half-scored sheet that counted toward the seal would be worse than no
sheet, so the document is not written until all eleven are present.
Requiring all eight comments would produce filler; the form's own
prompting questions are there to help a panelist who has something to
say, not to compel eight paragraphs.

**D46 — `averageRating` is dropped.** Appendix 8 prints "Average
Rating" twice plus "Final Grade", without defining how the three
relate. Under D34 the Final Grade is already the sum, so an average of
the eleven criteria would be a number out of ~9 with no stated
meaning, and an average across panelists is what §7's panel mean
already is. Recorded here as a deliberate omission so a later reader
knows it was decided rather than missed. It also goes on the §11 list.

**D47 — The student sees the verdict, not the numbers.** §11b has the
adviser submit the grading sheet to the subject professor: the
numerical grade leaves the system on paper, through a person. The app
shows the group their verdict and their consolidated room comments —
what §9a requires them to act on — and does not show per-panelist
scores or the numeric grade. This is the institution's routing, not a
technical limit.

## 3. Data model

### 3.1 The weights

One table, in `lib/data/models/evaluation.dart`, ordered as Form 5c
prints them:

| Key | Criterion | Weight | Section |
|---|---|---|---|
| `title` | Title | 5 | A |
| `introduction` | Introduction | 5 | A |
| `materialsAndMethods` | Materials and Methods | 10 | A |
| `result` | Result | 10 | A |
| `discussion` | Discussion | 10 | A |
| `conclusion` | Conclusion | 5 | A |
| `recommendation` | Recommendation | 2 | A |
| `references` | References | 3 | A |
| `preciseness` | Preciseness and clarity | 15 | B |
| `alertness` | Alertness and smartness in answering questions | 25 | B |
| `personality` | Personality | 10 | B |

Section A sums to 50, Section B to 50. Each entry also carries the
form's prompting question (`Natural? Logic Sequence? Statistically
evaluated?`) and whether it takes a comment — true for all eight of A,
false for all three of B, because the printed form gives comment lines
only to A.

**These eleven numbers exist twice** — here, and in `firestore.rules`,
which must reject a score above its weight and cannot import Dart.
This is the same duplication as `defenceOpenGrace`, which the rules
already handle by commenting the Dart constant at the rule site and
pinning the boundary in `rules.test.js`. The same treatment applies:
each side names the other, and a test fails if they drift.

### 3.2 `defenses/{defenceId}/evaluations/{evaluatorUid}`

Keyed by the evaluator's uid, so a panelist has exactly one and
cannot file a second under another name.

```
scores      map<string,int>   all 11 keys, each 0..weight
comments    map<string,string> subset of the 8 Content keys, non-empty values
total       int               sum of scores, 0..100
rating      'pass' | 'fail'   this panelist's own §8a rating
submittedAt timestamp
updatedAt   timestamp         set on every write, including the first
```

`total` is stored rather than derived on read so a query can order and
compare without loading eleven fields, and the rules verify it against
the scores on every write — a stored total that could disagree with
its own scores would be worse than none.

### 3.3 `defenses/{defenceId}` — four new fields

```
evaluationsReleasedAt  timestamp   the seal; absent until set, set once
panelVerdict           'pass'|'fail'  §8b, deliberated
verdictRecordedBy      string      the adviser's uid
verdictRecordedAt      timestamp
```

All four are absent on a defence created today, so `Defence.fromMap`
reads them as nullable and every screen must handle absent. The four
are added to the model's `copyWith` and `toMap` and to the `hasOnly`
key set on `allow create` — a create must still refuse them, since
they belong to acts that happen after the defence closes.

The panel mean — the mean of the submitted `total` values — is
**computed on read, not stored**. It is a function of documents the
reader is already loading, and storing it would introduce a value that
can disagree with them.

## 4. Permissions

All of this lives under the existing `match /defenses/{defenseId}`
block, which already has `defence()`, `incoming()` and
`onThisDefence()` in scope.

### 4.1 The evaluations subcollection

```
match /evaluations/{evaluatorUid} {
  function parent() {
    return get(/databases/$(database)/documents/defenses/$(defenseId)).data;
  }
  function isPanelistHere() {
    return signedIn() && request.auth.uid in parent().panelUids;
  }
  function released() {
    return 'evaluationsReleasedAt' in parent();
  }
```

**Read.** Your own always; everyone else's only after release.

```
  allow get, list: if (signedIn() && request.auth.uid == evaluatorUid
                       && isPanelistHere())
                   || (released() && (isPanelistHere()
                                      || parent().adviserUid == request.auth.uid
                                      || isCoordinator() || isDean()));
```

The first arm authorises on the `{evaluatorUid}` wildcard, which is
sound here because a panelist reading their own document knows its id.
The second arm is field-blind by design — after release the whole set
is readable by the four roles named.

Note what the adviser cannot do: read a single evaluation before
release. They release without seeing the contents, which is correct —
release is a procedural act on a count, not an editorial one.

**Create and update.** Same shape, so the validation lives in one
helper:

```
  function wellFormed() {
    let s = incoming().scores;
    return incoming().keys().hasOnly(
             ['scores','comments','total','rating','submittedAt','updatedAt'])
        && s.keys().hasOnly(WEIGHT_KEYS) && s.keys().hasAll(WEIGHT_KEYS)
        && s.title >= 0 && s.title <= 5
        && s.introduction >= 0 && s.introduction <= 5
        // ... one line per criterion; the weights of §3.1
        && incoming().total == s.title + s.introduction + /* ... */ s.personality
        && incoming().rating in ['pass','fail']
        && incoming().comments.keys().hasOnly(CONTENT_KEYS);
  }

  allow create: if verified() && isPanelistHere()
                && request.auth.uid == evaluatorUid
                && parent().status in ['inProgress','completed']
                && !released()
                && wellFormed()
                && incoming().submittedAt == request.time
                && incoming().updatedAt == request.time;

  allow update: if verified() && isPanelistHere()
                && request.auth.uid == evaluatorUid
                && !released()
                && wellFormed()
                && incoming().submittedAt == resource.data.submittedAt
                && incoming().updatedAt == request.time;

  allow delete: if false;
}
```

`WEIGHT_KEYS` and `CONTENT_KEYS` are written that way for readability
only — the rules language has no constants, so both are inline string
lists at the call site, and the eleven bounds are eleven explicit
lines. That verbosity is the point: it is what the drift test in §9
reads against §3.1.

`parent()` costs one `get` per document evaluated, the same shape the
comments subcollection already uses. Safe here because an evaluations
subcollection holds at most one document per panelist — unlike the
`list` over `defenses`, which is why that block snapshots `leaderUid`
onto the defence rather than reading the thesis.

Four things this refuses, each deliberately:

- **The adviser.** `isPanelistHere()` reads `panelUids`, which the
  adviser is not in. D37 in the rules, not only in the UI.
- **A defence not yet under way.** `status in ['inProgress',
  'completed']` — nothing has been presented to score while it is
  merely `scheduled`, and a `cancelled` one is never scorable.
- **Writing after release.** `!released()` on both arms is D44's
  freeze.
- **Scoring in someone else's name.** `request.auth.uid ==
  evaluatorUid` on both arms.

`submittedAt` must survive an update unchanged, so "when did this
panelist first submit" stays answerable after an edit.

### 4.2 Two new arms on the defence document

Both are the adviser's, both mirror the existing consolidation arm.

```
// Adviser arm 2 -- RELEASE the evaluations. Once, after the defence closes.
allow update: if verified()
              && defence().adviserUid == request.auth.uid
              && defence().status == 'completed'
              && !('evaluationsReleasedAt' in defence())
              && incoming().diff(defence()).affectedKeys()
                 .hasOnly(['evaluationsReleasedAt'])
              && incoming().evaluationsReleasedAt == request.time;

// Adviser arm 3 -- RECORD the §8b verdict. Only after release (D43),
// and once: a recorded verdict is the panel's decision, not a draft.
allow update: if verified()
              && defence().adviserUid == request.auth.uid
              && 'evaluationsReleasedAt' in defence()
              && !('panelVerdict' in defence())
              && incoming().diff(defence()).affectedKeys()
                 .hasOnly(['panelVerdict','verdictRecordedBy','verdictRecordedAt'])
              && incoming().panelVerdict in ['pass','fail']
              && incoming().verdictRecordedBy == request.auth.uid
              && incoming().verdictRecordedAt == request.time;
```

The `affectedKeys().hasOnly(...)` on each is what stops either arm
doubling as a status transition or a schedule edit — the same
discipline the four coordinator arms already use.

**A presence check, not a sentinel.** Both arms test `'x' in
defence()`, never `defence().get('x', <sentinel>) == <sentinel>`. This
milestone's predecessor lost time twice to sentinel collisions — first
`true`, then `null` — where a legitimate value equalled the sentinel
and the rule silently changed meaning. Presence is value-blind and
cannot collide.

## 5. The evaluation screen

`/defence/room/:defenceId/evaluate`, pushed, so back returns to the
room.

Two cards — A. Content and B. Presentation and Defense — each with its
section subtotal and a progress bar, over a total block carrying
Section A, Section B and the Final Grade. Every criterion shows its
name, its weight, and a **stepper** rather than a free number field.

The stepper is doing real work, not decoration. It clamps at 0 and at
the weight, so 25 on a criterion worth 5 is unreachable rather than
entered-then-rejected; and on a phone it avoids summoning a numeric
keyboard eleven times. This is the mitigation D34 owes for eleven
different maximums.

The eight Content criteria carry the form's prompting question as
helper text and a comment field beneath, styled so an empty one
recedes and a filled one does not — a panelist can see at a glance
which they wrote on. The three Presentation criteria carry neither,
matching the printed form (D38's separation is visible here: this is
not the room log).

Below, the panelist's own Pass/Fail, labelled *Your rating* with one
line of explanation that this is §8a and not the panel's verdict. That
sentence exists because "I already marked Pass, why is there another
one" is the obvious confusion, and D41 depends on the two staying
distinct in the user's head as well as in the data.

Submit is enabled only when all eleven have a value (D45). After
submission the screen stays reachable and editable, with the button
reading *Update evaluation* and a line saying it can be changed until
release. Once released it renders read-only with a note saying why.

## 6. The grades screen

`/defence/room/:defenceId/grades`, pushed. What it shows depends
entirely on release, and it is the same route for everyone.

**Before release** it is a count and nothing else: *2 of 3 panelists
have submitted*, listing who has and who has not — names, not scores.
Nobody sees a number here, including the adviser.

For the adviser it also carries **Release evaluations**, with the
count on the button itself. Releasing at 2 of 3 is possible and the
button says so rather than hiding it — D40's mitigation, and the
reason the count is the most prominent thing on the screen.

**After release** it is a table: one row per panelist, their eleven
scores, their total, and their own Pass/Fail. Beneath it the panel
mean, computed on read (§3.3), and every per-criterion comment grouped
by criterion, so the group's weakest area reads as three panelists'
remarks side by side rather than three separate sheets.

Then the **verdict block**. For the adviser, before one is recorded:
Pass/Fail and *Record verdict*, with a line stating this is the
panel's deliberated decision under §8b and that they are recording it,
not making it. Once recorded, everyone sees the verdict with *recorded
by* and the timestamp — D42's visibility of the scribe.

The panelists and the coordinator and dean see the same table without
either the release or the record control.

**The group does not reach this screen at all.** Per D47 the leader
sees their verdict on the defence itself — `panelVerdict` sits on the
defence document, which `onThisDefence()` already lets them read — and
their consolidated room comments, which M3 already gives them. No arm
of §4.1 grants the leader an evaluation, so the numbers are
unreachable rather than merely unrendered. That is the point: hiding
scores in the UI while leaving them readable would be a worse answer
than not granting the read.

## 7. Entry points

Two screens that nothing navigates to is how M2 shipped a leader
upload flow nobody could reach, and it was caught only in final
review. So, explicitly:

- **The defence room**, once `status == completed`, gains an
  Evaluation card. For a panelist it reads *Evaluate* or *Your
  evaluation — 83/100* and goes to `/evaluate`. For the adviser it
  reads *Grades* with the submitted count. Both also link to
  `/grades`.
- **The defence list and calendar**, on a completed defence, gain the
  same affordance in the row — a panelist who has not yet evaluated
  sees it as an outstanding action rather than having to open the
  room.
- **The faculty dashboard's needs-you queue** gains one entry: a
  completed defence where you are a panelist and have not submitted.
  This follows the existing queue pattern, including its loading
  contract — the three queues shipped publishing `data([])` while
  loading, because `ref.listen(fireImmediately: true)` delivers
  `AsyncLoading`, which is not null and passed the null guard. A new
  queue must not repeat it.

Both routes use `isDeepForRole` so the shell keeps its navigation and
the back affordance behaves — the D23 revision applies unchanged.

## 8. Error handling

The rule this project keeps relearning: **an empty result and a failed
read must not look the same.** Four bugs have come from treating a
missing document as a settled answer — M2 permanently hiding a
leader's upload button, and the dashboards milestone routing a
profile-less dean down the faculty path.

So: no evaluations yet says *No evaluations submitted yet*; a failed
read says it failed, with the Firestore code. A defence that cannot be
loaded does not render an evaluation form against an empty panel list.

A denied write surfaces the reason rather than a generic failure. The
three that can actually happen are release arriving between load and
submit (*Evaluations were released while you were marking; your sheet
is now final*), a defence not yet opened, and a verdict already
recorded by a concurrent write. Each is a stale-view problem, so each
message says what changed underneath rather than that something went
wrong.

## 9. Testing

**Rules, in the emulator, `rules.test.js`.** Nothing here is provable
in `fake_cloud_firestore`, which enforces no rules at all:

- A panelist may write their own evaluation; the adviser may not
  write one at all; a non-panelist may not; nobody may write in
  another's name.
- Scores are bounded per criterion — 5 on Title passes, 6 denies; 25
  on Alertness passes, 26 denies. **This is the drift test**: it
  fails if the rules' weights and §3.1's table disagree.
- A `total` that does not equal the sum denies.
- A sheet missing one of the eleven keys denies.
- Create denies while `scheduled` and while `cancelled`; passes while
  `inProgress` and `completed`.
- Before release, a panelist reads their own and is denied a
  colleague's. After release, both succeed, and the adviser and
  coordinator succeed.
- Release: adviser once, only when `completed`, denied when already
  released, denied for a panelist and for the coordinator.
- Verdict: denied before release, allowed after, denied twice, denied
  for a panelist, and denied when the write also touches `status`.

**Widget tests.** The running total updates as scores change; the
stepper clamps at 0 and at the weight; Submit is disabled until all
eleven are present; a released evaluation renders read-only; the
grades screen shows the count before release and the table after;
the adviser sees Release and a panelist does not.

Two contracts this codebase has broken before and must pin again: a
**loading test must `pump()` once, not `pumpAndSettle()`**, which
resolves the stream before the assertion and makes the test vacuous;
and any test asserting ordering must **write documents out of order**,
because `fake_cloud_firestore` returns insertion order and will
otherwise pass an unsorted implementation.

**A dedicated test that the weights sum to 100**, and that Section A
and Section B each sum to 50. Trivial, and it is the test that catches
someone "fixing" Title back to 50 from the printed form.

## 10. Out of scope

- **Form 7, the consolidated grade sheet across both defences.** This
  milestone produces one grade per defence. Combining pre-oral and
  final into a submitted sheet is separate work.
- **Any export or print.** §11b routes the grading sheet to the
  subject professor on paper; generating that document is not built
  here.
- **Editing a recorded verdict.** Once written it stands. If the panel
  reconvenes, that is a process question the system should not
  pre-answer with an edit button.
- **Notifying panelists that a defence awaits evaluation.** The
  needs-you queue surfaces it in-app; push and email are not built.
- **§1e, the coordinator assigning an adviser.** Still its own spec.

## 11. Documentation debt

Three items to raise with the Research Coordinator, the first two
carried forward from earlier milestones:

1. **Form 5c prints Title at 50%**, which contradicts its own section
   total. D35 treats it as a typo; the manual should be corrected.
2. **The 5c / 6c numbering** is inconsistent between the appendix and
   the body of the Guidelines.
3. **"Average Rating" appears twice on Form 5c** alongside "Final
   Grade" without a stated relationship between the three. D46 drops
   it; a definition would let it come back.

Also outstanding from the coordinator-admin milestone and unaffected
by this one: the Chapter II form table in
`2026-08-12-ethesishub-design.md` diverges from the PDF in roughly
five places, and that document's line 100 sketch of `evaluations/` is
superseded by §3.2 above.
