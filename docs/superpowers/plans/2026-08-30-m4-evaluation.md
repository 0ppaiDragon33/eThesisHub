# M4 Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each panelist scores a defence against Guidelines Form 5c, the adviser releases the set, and the panel's deliberated verdict is recorded.

**Architecture:** A new `evaluations/{evaluatorUid}` subcollection under the existing `defenses/{defenceId}`, keyed by evaluator so one panelist writes exactly one. Four new fields on the defence carry the seal and the verdict. The seal reuses the shape `consolidatedAt` already established — a timestamp whose presence is the gate — so there is one pattern to understand rather than two. Two pushed screens hang off the defence room.

**Tech Stack:** Flutter 3.44.2 / Dart 3.12, Riverpod 2.6.1, go_router 17.5, cloud_firestore, `fake_cloud_firestore` for Dart tests, `@firebase/rules-unit-testing` + the Firestore emulator for rules.

**Spec:** `docs/superpowers/specs/2026-08-30-m4-evaluation-design.md` — read it before Task 1. Every decision number cited below (D34–D47) is defined there.

## Global Constraints

- **Android and Web only.** `dart:io` must never be imported anywhere under `lib/`.
- **Riverpod is pinned at 2.6.1.** `Notifier`/`NotifierProvider` are available and used elsewhere. Forbidden: codegen (`@riverpod`), any 3.x-only API, and the deprecated `StreamProvider.stream`.
- **go_router is pinned at 17.5.** `GoRouter.configuration` is `@internal` — do not read it.
- **Firebase Spark plan: there are no Cloud Functions.** `firestore.rules` is the only authorization boundary. Anything a rule cannot express is not enforced, and must be made visible in the UI instead (D40).
- **`fake_cloud_firestore` enforces no rules and returns insertion order.** No Dart test proves an authorization claim. Any test asserting order must write documents out of order first.
- **A loading test must `pump()` once, never `pumpAndSettle()`** — settling resolves the stream before the assertion and makes the test vacuous.
- **Server timestamps.** Every field a rule pins to `request.time` must be written with `FieldValue.serverTimestamp()`. A client `Timestamp.now()` can never equal the server's commit time, so the write is denied in production while every fake-backed test still passes.
- **An empty result and a failed read must never render the same.** Four shipped bugs came from treating a missing document as a settled answer.

## File Structure

| File | Responsibility |
|---|---|
| `lib/data/models/evaluation_criteria.dart` (new) | The eleven criteria — key, label, weight, section, prompt. The single Dart source of truth for weights. |
| `lib/data/models/evaluation.dart` (new) | `Evaluation`, `PassFail`, section subtotals, `fromMap`. |
| `lib/data/models/defence.dart` (modify) | Four new fields on `Defence` and the getters that read them. |
| `lib/data/repositories/defence_repository.dart` (modify) | Submit/update an evaluation, watch them, release, record the verdict. |
| `lib/providers/defence_providers.dart` (modify) | `defenceEvaluationsProvider`, `myEvaluationProvider`. |
| `lib/features/defence/evaluation_screen.dart` (new) | The Form 5c sheet. |
| `lib/features/defence/defence_grades_screen.dart` (new) | Count before release, table after, release and verdict controls. |
| `lib/core/routing/app_router.dart` (modify) | Two routes. |
| `lib/features/defence/defence_room_screen.dart` (modify) | Entry points. |
| `lib/providers/needs_you_providers.dart` (modify) | One queue row. |
| `firestore.rules` (modify) | The subcollection block and two adviser arms. |
| `rules-test/rules.test.js` (modify) | Emulator proofs. |

---

### Task 1: The criteria table

The eleven criteria of Form 5c, in the order the form prints them. This
file is the Dart half of the duplication D34 accepts — the same weights
exist as literals in `firestore.rules`, which cannot import Dart.

**Files:**
- Create: `lib/data/models/evaluation_criteria.dart`
- Test: `test/data/models/evaluation_criteria_test.dart`

**Interfaces:**
- Produces: `EvaluationSection` (enum: `content`, `presentation`, each with `.label`), `EvaluationCriterion` (`key`, `label`, `weight`, `section`, `prompt`, `takesComment`), `const evaluationCriteria` (`List<EvaluationCriterion>`, 11 entries), `criterionKeys` (`List<String>`), `contentKeys` (`List<String>`), `criterionFor(String key)`.

- [ ] **Step 1: Write the failing test**

Create `test/data/models/evaluation_criteria_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';

void main() {
  test('the eleven criteria sum to 100', () {
    final total =
        evaluationCriteria.fold<int>(0, (sum, c) => sum + c.weight);
    expect(total, 100);
  });

  test('each section sums to 50', () {
    int sum(EvaluationSection s) => evaluationCriteria
        .where((c) => c.section == s)
        .fold<int>(0, (t, c) => t + c.weight);

    expect(sum(EvaluationSection.content), 50);
    expect(sum(EvaluationSection.presentation), 50);
  });

  // D35. The printed form says Title (50%), which would make Section A
  // sum to 95 against its own stated 50%. This test is what stops someone
  // "correcting" the table back to the manual.
  test('Title is 5, not the 50 the printed form says', () {
    expect(criterionFor('title')!.weight, 5);
  });

  test('there are eight Content criteria and three Presentation', () {
    expect(
        evaluationCriteria
            .where((c) => c.section == EvaluationSection.content)
            .length,
        8);
    expect(
        evaluationCriteria
            .where((c) => c.section == EvaluationSection.presentation)
            .length,
        3);
  });

  // D38: the printed form gives comment lines to Section A only.
  test('only Content criteria take a comment', () {
    for (final c in evaluationCriteria) {
      expect(c.takesComment, c.section == EvaluationSection.content,
          reason: c.key);
    }
  });

  test('keys are unique', () {
    expect(criterionKeys.toSet().length, criterionKeys.length);
  });

  test('contentKeys is the eight Content keys in form order', () {
    expect(contentKeys, [
      'title', 'introduction', 'materialsAndMethods', 'result',
      'discussion', 'conclusion', 'recommendation', 'references',
    ]);
  });

  test('an unknown key resolves to null rather than throwing', () {
    expect(criterionFor('nope'), isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/models/evaluation_criteria_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:ethesishub/data/models/evaluation_criteria.dart'`

- [ ] **Step 3: Write the implementation**

Create `lib/data/models/evaluation_criteria.dart`:

```dart
/// The two halves of Research Form 5c (Appendix 8, Evaluation Guide).
enum EvaluationSection {
  content('A. Content'),
  presentation('B. Presentation and Defense');

  const EvaluationSection(this.label);

  final String label;

  /// Each half is worth 50 of the 100. Asserted by the test rather than
  /// derived, so a wrong weight fails loudly instead of shifting the
  /// denominator underneath a grade.
  static const int sectionTotal = 50;
}

/// One row of Form 5c.
///
/// [prompt] is the form's OWN wording, transcribed from the Guidelines,
/// not a paraphrase. It is what turns eleven numbers into something a
/// panelist can fill in, and it must keep matching the paper the panel
/// may well have in front of them.
class EvaluationCriterion {
  const EvaluationCriterion({
    required this.key,
    required this.label,
    required this.weight,
    required this.section,
    required this.prompt,
  });

  /// The Firestore map key. Stable forever — it is stored in every
  /// evaluation document ever written, and named in `firestore.rules`.
  final String key;

  final String label;

  /// Points available. A score is 0..weight, NOT a 1-5 rating that gets
  /// multiplied (D34), so the eleven scores sum straight to the grade
  /// with no conversion anywhere in the app.
  final int weight;

  final EvaluationSection section;

  final String prompt;

  /// Section A carries comment lines on the printed form; Section B does
  /// not. Derived from the section rather than stored per criterion, so
  /// the two cannot drift apart.
  bool get takesComment => section == EvaluationSection.content;
}

/// THESE ELEVEN WEIGHTS EXIST TWICE. `firestore.rules` carries the same
/// numbers as literals in `match /evaluations/{evaluatorUid}`, because
/// rules cannot import Dart. If the two ever disagree the form accepts a
/// score the rules deny, so the rules suite pins every boundary — see the
/// "bounded per criterion" tests in `rules-test/rules.test.js`.
///
/// Order is the order Form 5c prints, and the screens render them in list
/// order rather than sorting.
const evaluationCriteria = <EvaluationCriterion>[
  EvaluationCriterion(
    key: 'title',
    label: 'Title',
    // The form prints 50%, which would put Section A at 95 against its
    // own stated 50% and the whole form at 145. Every other criterion is
    // internally consistent, so this is a typo in the manual (D35) and is
    // treated as one. Raised with the Research Coordinator; see the spec.
    weight: 5,
    section: EvaluationSection.content,
    prompt: 'Short, clear, accurate? Subject important?',
  ),
  EvaluationCriterion(
    key: 'introduction',
    label: 'Introduction',
    weight: 5,
    section: EvaluationSection.content,
    prompt: 'Too long? Too short? General to specific points? '
        'Giving background? Leading topic?',
  ),
  EvaluationCriterion(
    key: 'materialsAndMethods',
    // The form prints "Material and Methods", singular. Kept as the form
    // has it, since a panelist reads the two side by side.
    label: 'Material and Methods',
    weight: 10,
    section: EvaluationSection.content,
    prompt: 'Design clear? Manner practical? Time appropriate?',
  ),
  EvaluationCriterion(
    key: 'result',
    label: 'Result',
    weight: 10,
    section: EvaluationSection.content,
    prompt: 'Natural? Logic Sequence? Statistically evaluated?',
  ),
  EvaluationCriterion(
    key: 'discussion',
    label: 'Discussion',
    weight: 10,
    section: EvaluationSection.content,
    prompt: 'Convincing, i.e. documentation sufficient? Report objective? '
        'Prepared carefully?',
  ),
  EvaluationCriterion(
    key: 'conclusion',
    label: 'Conclusion',
    weight: 5,
    section: EvaluationSection.content,
    prompt: 'Valid and logical? Short and precise?',
  ),
  EvaluationCriterion(
    key: 'recommendation',
    label: 'Recommendation',
    weight: 2,
    section: EvaluationSection.content,
    prompt: 'Feasible? Specific?',
  ),
  EvaluationCriterion(
    key: 'references',
    label: 'References',
    weight: 3,
    section: EvaluationSection.content,
    prompt: 'Clearly related to the subject discussed? Sufficient no? '
        'Correctly cited?',
  ),
  EvaluationCriterion(
    key: 'preciseness',
    label: 'Preciseness and clarity',
    weight: 15,
    section: EvaluationSection.presentation,
    prompt: '',
  ),
  EvaluationCriterion(
    key: 'alertness',
    label: 'Alertness and smartness in answering question',
    weight: 25,
    section: EvaluationSection.presentation,
    prompt: '',
  ),
  EvaluationCriterion(
    key: 'personality',
    label: 'Personality',
    weight: 10,
    section: EvaluationSection.presentation,
    prompt: 'Voice quality, articulation, gestures, grooming',
  ),
];

/// All eleven keys, in form order.
final criterionKeys =
    List<String>.unmodifiable(evaluationCriteria.map((c) => c.key));

/// The eight that carry a comment field.
final contentKeys = List<String>.unmodifiable(evaluationCriteria
    .where((c) => c.takesComment)
    .map((c) => c.key));

/// Null rather than a throw or a default: an unknown key means stored data
/// disagrees with this table, and a screen must be able to skip it rather
/// than crash on someone's permanent record.
EvaluationCriterion? criterionFor(String key) {
  for (final c in evaluationCriteria) {
    if (c.key == key) return c;
  }
  return null;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/models/evaluation_criteria_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/evaluation_criteria.dart test/data/models/evaluation_criteria_test.dart
git commit -m "feat: add the Form 5c criteria table"
```

---

### Task 2: The Evaluation model

**Files:**
- Create: `lib/data/models/evaluation.dart`
- Test: `test/data/models/evaluation_test.dart`

**Interfaces:**
- Consumes: `evaluation_criteria.dart` from Task 1 — `evaluationCriteria`, `criterionFor`, `EvaluationSection`.
- Produces: `PassFail` (enum `pass`, `fail`, with `.value`, `.label`, `static PassFail? fromString(String?)`), `Evaluation` (`evaluatorUid`, `scores`, `comments`, `total`, `rating`, `submittedAt`, `updatedAt`, `sectionTotal(EvaluationSection)`, `Evaluation.fromMap(String, Map<String, dynamic>)`), and `int totalOf(Map<String, int>)`.

- [ ] **Step 1: Write the failing test**

Create `test/data/models/evaluation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';

Map<String, int> fullScores({int each = 1}) =>
    {for (final c in evaluationCriteria) c.key: each};

void main() {
  test('totalOf sums the eleven scores', () {
    expect(totalOf(fullScores()), 11);
  });

  test('a perfect sheet totals 100', () {
    final perfect = {for (final c in evaluationCriteria) c.key: c.weight};
    expect(totalOf(perfect), 100);
  });

  test('sectionTotal splits 50 and 50 on a perfect sheet', () {
    final e = Evaluation(
      evaluatorUid: 'p1',
      scores: {for (final c in evaluationCriteria) c.key: c.weight},
      comments: const {},
      total: 100,
      rating: PassFail.pass,
    );
    expect(e.sectionTotal(EvaluationSection.content), 50);
    expect(e.sectionTotal(EvaluationSection.presentation), 50);
  });

  test('fromMap reads scores, comments, total and rating', () {
    final e = Evaluation.fromMap('p1', {
      'scores': {'title': 4, 'alertness': 21},
      'comments': {'title': 'Narrow it.'},
      'total': 25,
      'rating': 'pass',
      'submittedAt': DateTime(2026, 9, 23, 11),
      'updatedAt': DateTime(2026, 9, 23, 12),
    });

    expect(e.evaluatorUid, 'p1');
    expect(e.scores['title'], 4);
    expect(e.comments['title'], 'Narrow it.');
    expect(e.total, 25);
    expect(e.rating, PassFail.pass);
    expect(e.submittedAt, DateTime(2026, 9, 23, 11));
    expect(e.updatedAt, DateTime(2026, 9, 23, 12));
  });

  // The same reasoning as DefenceType.fromString: a typo must not silently
  // become a pass. Here it must not silently become a fail either, so the
  // model surfaces null and the screen decides.
  test('an unreadable rating is null, not a default', () {
    expect(PassFail.fromString('Pass'), isNull);
    expect(PassFail.fromString(null), isNull);
    expect(PassFail.fromString('pass'), PassFail.pass);
    expect(PassFail.fromString('fail'), PassFail.fail);
  });

  test('a score key this build does not know is ignored, not fatal', () {
    final e = Evaluation.fromMap('p1', {
      'scores': {'title': 4, 'someFutureCriterion': 9},
      'comments': const <String, dynamic>{},
      'total': 13,
      'rating': 'fail',
    });
    // Kept in `scores` verbatim -- it is someone's permanent record --
    // but excluded from a section subtotal, which can only count criteria
    // it can place in a section.
    expect(e.scores['someFutureCriterion'], 9);
    expect(e.sectionTotal(EvaluationSection.content), 4);
  });

  test('a missing scores map reads as empty rather than throwing', () {
    final e = Evaluation.fromMap('p1', const {});
    expect(e.scores, isEmpty);
    expect(e.total, 0);
    expect(e.rating, isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/models/evaluation_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../evaluation.dart'`

- [ ] **Step 3: Write the implementation**

Create `lib/data/models/evaluation.dart`:

```dart
import 'package:ethesishub/data/models/evaluation_criteria.dart';

/// Guidelines §8a: *"The Thesis Panel Members shall rate the student using
/// the Pass or Fail grading scheme."*
///
/// Used for two different things that must never be confused: one
/// panelist's own rating on their sheet, and the panel's deliberated
/// verdict under §8b, which the adviser records and which is NEVER
/// computed from the ratings (D41).
enum PassFail {
  pass,
  fail;

  String get value => name;

  String get label => this == PassFail.pass ? 'Pass' : 'Fail';

  /// Null rather than a default. There is no safe default here: defaulting
  /// to `pass` passes a student on corrupt data, and defaulting to `fail`
  /// fails one. The caller must handle "we cannot read this".
  static PassFail? fromString(String? raw) {
    for (final v in PassFail.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// The sum of a score map. The stored `total` is written from this, and
/// `firestore.rules` recomputes the same sum before accepting a write --
/// a stored total that could disagree with its own scores would be worse
/// than no stored total at all.
int totalOf(Map<String, int> scores) =>
    scores.values.fold<int>(0, (sum, v) => sum + v);

/// One panelist's completed Form 5c for one defence.
///
/// Keyed in Firestore by the evaluator's uid, so a panelist has exactly
/// one and cannot file a second under another name.
class Evaluation {
  const Evaluation({
    required this.evaluatorUid,
    required this.scores,
    required this.comments,
    required this.total,
    required this.rating,
    this.submittedAt,
    this.updatedAt,
  });

  final String evaluatorUid;

  /// Criterion key -> points, each 0..that criterion's weight (D34).
  final Map<String, int> scores;

  /// Criterion key -> remark, for the eight Content criteria only.
  /// Optional per criterion (D45): requiring all eight produces filler.
  final Map<String, String> comments;

  /// 0..100. Stored rather than derived so a list can compare and order
  /// without loading eleven fields.
  final int total;

  /// This panelist's own §8a rating. Null only when the stored value is
  /// unreadable -- see [PassFail.fromString].
  final PassFail? rating;

  /// When this panelist first submitted. Survives every later edit, so
  /// "when did they submit" stays answerable (the rules pin it too).
  final DateTime? submittedAt;

  final DateTime? updatedAt;

  /// The subtotal for one half of the form.
  ///
  /// Counts only keys this build can place in a section. A key written by
  /// a future build is kept in [scores] -- it is part of someone's
  /// permanent record -- but cannot be added to a section it has no
  /// section for.
  int sectionTotal(EvaluationSection section) {
    var sum = 0;
    scores.forEach((key, value) {
      if (criterionFor(key)?.section == section) sum += value;
    });
    return sum;
  }

  factory Evaluation.fromMap(String evaluatorUid, Map<String, dynamic> map) {
    final rawScores = map['scores'] as Map? ?? const {};
    final rawComments = map['comments'] as Map? ?? const {};

    return Evaluation(
      evaluatorUid: evaluatorUid,
      scores: {
        for (final e in rawScores.entries)
          if (e.value is int) e.key as String: e.value as int,
      },
      comments: {
        for (final e in rawComments.entries)
          if (e.value is String) e.key as String: e.value as String,
      },
      total: map['total'] as int? ?? 0,
      rating: PassFail.fromString(map['rating'] as String?),
      submittedAt: map['submittedAt'] as DateTime?,
      updatedAt: map['updatedAt'] as DateTime?,
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/models/evaluation_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/evaluation.dart test/data/models/evaluation_test.dart
git commit -m "feat: add the Evaluation model"
```

---

### Task 3: Four new fields on the defence

**Files:**
- Modify: `lib/data/models/defence.dart` — the `Defence` class
- Test: `test/data/models/defence_test.dart` (append)

**Interfaces:**
- Consumes: `PassFail` from Task 2.
- Produces: on `Defence` — `evaluationsReleasedAt`, `panelVerdict`, `verdictRecordedBy`, `verdictRecordedAt`, plus `bool get evaluationsReleased` and `bool get hasVerdict`.

- [ ] **Step 1: Write the failing test**

Append to `test/data/models/defence_test.dart` (keep the existing imports; add `import 'package:ethesishub/data/models/evaluation.dart';`):

```dart
  // The four M4 fields are absent on every defence created before this
  // milestone, so absent must read as "not yet", never as an error and
  // never as a value.
  test('a defence with no evaluation fields is unreleased and unjudged',
      () {
    final d = Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'final',
      'venue': 'AVR',
      'panelUids': <String>['p1'],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'completed',
      'createdBy': 'c1',
    });

    expect(d.evaluationsReleasedAt, isNull);
    expect(d.evaluationsReleased, isFalse);
    expect(d.panelVerdict, isNull);
    expect(d.hasVerdict, isFalse);
    expect(d.verdictRecordedBy, isNull);
    expect(d.verdictRecordedAt, isNull);
  });

  test('a released, judged defence reads all four back', () {
    final d = Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'final',
      'venue': 'AVR',
      'panelUids': <String>['p1'],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'completed',
      'createdBy': 'c1',
      'evaluationsReleasedAt': DateTime(2026, 9, 23, 14),
      'panelVerdict': 'pass',
      'verdictRecordedBy': 'a1',
      'verdictRecordedAt': DateTime(2026, 9, 23, 15),
    });

    expect(d.evaluationsReleased, isTrue);
    expect(d.panelVerdict, PassFail.pass);
    expect(d.hasVerdict, isTrue);
    expect(d.verdictRecordedBy, 'a1');
    expect(d.verdictRecordedAt, DateTime(2026, 9, 23, 15));
  });

  // Release and consolidation are separate acts on separate gates. A
  // defence whose comments are released has not thereby released its
  // grades, and vice versa.
  test('releasing the comments does not release the evaluations', () {
    final d = Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'final',
      'venue': 'AVR',
      'panelUids': <String>['p1'],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'completed',
      'createdBy': 'c1',
      'consolidatedAt': DateTime(2026, 9, 23, 13),
    });

    expect(d.isReleased, isTrue);
    expect(d.evaluationsReleased, isFalse);
  });

  test('an unreadable verdict is null rather than a pass', () {
    final d = Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'final',
      'venue': 'AVR',
      'panelUids': <String>['p1'],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'completed',
      'createdBy': 'c1',
      'panelVerdict': 'PASSED',
    });

    expect(d.panelVerdict, isNull);
    expect(d.hasVerdict, isFalse);
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/models/defence_test.dart`
Expected: FAIL — `The getter 'evaluationsReleasedAt' isn't defined for the class 'Defence'`

- [ ] **Step 3: Write the implementation**

In `lib/data/models/defence.dart`, add the import at the top:

```dart
import 'package:ethesishub/data/models/evaluation.dart';
```

Add four parameters to the `Defence` constructor, after `this.consolidatedAt`:

```dart
    this.evaluationsReleasedAt,
    this.panelVerdict,
    this.verdictRecordedBy,
    this.verdictRecordedAt,
```

Add the fields after `consolidatedAt`/`isReleased`:

```dart
  /// When the adviser released the panel's evaluations to each other.
  ///
  /// The same shape as [consolidatedAt] and for the same reason: presence
  /// is the gate, so `firestore.rules` tests `'evaluationsReleasedAt' in
  /// resource.data` -- a presence check, never a sentinel comparison. The
  /// coordinator-admin milestone lost time twice to sentinel collisions
  /// (`.get(k, true)` colliding with a real `true`, then `.get(k, null)`
  /// with an explicit `null`); presence is value-blind and cannot collide.
  ///
  /// SEPARATE from [consolidatedAt]. One releases the room log to the
  /// group; this releases the grades to the panel. Neither implies the
  /// other.
  final DateTime? evaluationsReleasedAt;

  /// Guidelines §8b, deliberated by the panel as a body and recorded once.
  ///
  /// NEVER computed from the panelists' individual ratings (D41). §8b
  /// hands the decision to a conversation; deriving it would be the system
  /// overruling the body the manual says decides.
  final PassFail? panelVerdict;

  /// The adviser who recorded [panelVerdict].
  ///
  /// Exists so a reader can see the adviser TRANSCRIBED a decision rather
  /// than made one -- they are barred from scoring at all (D37), so their
  /// role here has to be visibly that of a scribe.
  final String? verdictRecordedBy;

  final DateTime? verdictRecordedAt;

  bool get evaluationsReleased => evaluationsReleasedAt != null;

  bool get hasVerdict => panelVerdict != null;
```

And in `Defence.fromMap`, after the `consolidatedAt` line:

```dart
      evaluationsReleasedAt: map['evaluationsReleasedAt'] as DateTime?,
      panelVerdict: PassFail.fromString(map['panelVerdict'] as String?),
      verdictRecordedBy: map['verdictRecordedBy'] as String?,
      verdictRecordedAt: map['verdictRecordedAt'] as DateTime?,
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/models/defence_test.dart`
Expected: PASS — the four new tests plus every pre-existing one.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/defence.dart test/data/models/defence_test.dart
git commit -m "feat: carry the evaluation seal and verdict on the defence"
```

---

### Task 4: Rules — the evaluations subcollection

The authorization boundary. Nothing in this task is provable in Dart:
`fake_cloud_firestore` enforces no rules at all, so the emulator suite is
the only evidence that any of it works.

**Files:**
- Modify: `firestore.rules` — inside `match /defenses/{defenseId}`, after the `match /comments/{commentId}` block
- Test: `rules-test/rules.test.js` (append)

**Interfaces:**
- Produces: the `defenses/{id}/evaluations/{evaluatorUid}` contract every later task writes against — document keys `scores`, `comments`, `total`, `rating`, `submittedAt`, `updatedAt`.

- [ ] **Step 1: Write the failing tests**

Append to `rules-test/rules.test.js`, before the closing `test.after(...)` block:

```js
// ---------- M4: evaluations ----------

// The full eleven, all at their weight -- a perfect sheet totalling 100.
function fullScores(extra = {}) {
  return {
    title: 5, introduction: 5, materialsAndMethods: 10, result: 10,
    discussion: 10, conclusion: 5, recommendation: 2, references: 3,
    preciseness: 15, alertness: 25, personality: 10, ...extra,
  };
}

function evalDoc(extra = {}) {
  const scores = extra.scores ?? fullScores();
  const total = Object.values(scores).reduce((a, b) => a + b, 0);
  return {
    scores, comments: { title: "Narrow it." }, total,
    rating: "pass",
    // serverTimestamp(), not Timestamp.now(): the create rule pins both
    // stamps to request.time, and a client clock is never exactly equal.
    submittedAt: serverTimestamp(), updatedAt: serverTimestamp(),
    ...extra, ...(extra.scores ? { scores, total } : {}),
  };
}

async function seedM4(extra = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "theses/dt1"), defThesis());
    await setDoc(doc(db, "users/coord-uid"),
      { role: "coordinator", active: true });
    await setDoc(doc(db, "users/dean-uid"), { role: "dean", active: true });
    await setDoc(doc(db, "defenses/m4"),
      defDoc({ status: "completed", ...extra }));
  });
}

test("M4: a panelist writes their own evaluation", async () => {
  await seedM4();
  await assertSucceeds(setDoc(
    doc(asDefUser("pan-uid", "pan@isufst.edu.ph"),
        "defenses/m4/evaluations/pan-uid"),
    evalDoc()));
});

// D37, and the whole reason it is a rule and not a hidden button: the
// adviser has spent months on this thesis and cannot mark it at arm's
// length. They are not in panelUids, so isPanelistHere() refuses them.
test("M4 attack: the ADVISER may NOT write an evaluation", async () => {
  await seedM4();
  await assertFails(setDoc(
    doc(asDefUser("adviser-uid", "adviser@isufst.edu.ph"),
        "defenses/m4/evaluations/adviser-uid"),
    evalDoc()));
});

test("M4 attack: a non-panelist may NOT write one", async () => {
  await seedM4();
  for (const uid of ["leader-uid", "coord-uid", "dean-uid"]) {
    await assertFails(setDoc(
      doc(asDefUser(uid, `${uid}@isufst.edu.ph`),
          `defenses/m4/evaluations/${uid}`),
      evalDoc()));
  }
});

test("M4 attack: a panelist may NOT score in a colleague's name",
  async () => {
    await seedM4();
    await assertFails(setDoc(
      doc(asDefUser("pan-uid", "pan@isufst.edu.ph"),
          "defenses/m4/evaluations/pan2-uid"),
      evalDoc()));
  });

// THE DRIFT TEST. These eleven boundaries are the only thing tying
// firestore.rules to lib/data/models/evaluation_criteria.dart, which it
// cannot import. If someone changes a weight on one side only, the pair
// at that criterion fails here.
test("M4: each score is bounded by its own criterion's weight",
  async () => {
    await seedM4();
    const db = asDefUser("pan-uid", "pan@isufst.edu.ph");
    const weights = {
      title: 5, introduction: 5, materialsAndMethods: 10, result: 10,
      discussion: 10, conclusion: 5, recommendation: 2, references: 3,
      preciseness: 15, alertness: 25, personality: 10,
    };
    for (const [key, weight] of Object.entries(weights)) {
      await assertSucceeds(setDoc(
        doc(db, "defenses/m4/evaluations/pan-uid"),
        evalDoc({ scores: fullScores({ [key]: weight }) })));
      await assertFails(setDoc(
        doc(db, "defenses/m4/evaluations/pan-uid"),
        evalDoc({ scores: fullScores({ [key]: weight + 1 }) })));
      await assertFails(setDoc(
        doc(db, "defenses/m4/evaluations/pan-uid"),
        evalDoc({ scores: fullScores({ [key]: -1 }) })));
    }
  });

test("M4 attack: a total that does not equal the scores is denied",
  async () => {
    await seedM4();
    await assertFails(setDoc(
      doc(asDefUser("pan-uid", "pan@isufst.edu.ph"),
          "defenses/m4/evaluations/pan-uid"),
      { ...evalDoc(), total: 100 - 1 }));
  });

// D45: a half-scored sheet counting toward the seal would be worse than
// no sheet, so it is never written at all.
test("M4 attack: a sheet missing a criterion is denied", async () => {
  await seedM4();
  const scores = fullScores();
  delete scores.personality;
  await assertFails(setDoc(
    doc(asDefUser("pan-uid", "pan@isufst.edu.ph"),
        "defenses/m4/evaluations/pan-uid"),
    { scores, comments: {}, total: 90, rating: "pass",
      submittedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
});

test("M4 attack: a comment on a Section B criterion is denied", async () => {
  await seedM4();
  await assertFails(setDoc(
    doc(asDefUser("pan-uid", "pan@isufst.edu.ph"),
        "defenses/m4/evaluations/pan-uid"),
    { ...evalDoc(), comments: { alertness: "not a field on the form" } }));
});

test("M4 attack: a rating outside pass/fail is denied", async () => {
  await seedM4();
  await assertFails(setDoc(
    doc(asDefUser("pan-uid", "pan@isufst.edu.ph"),
        "defenses/m4/evaluations/pan-uid"),
    { ...evalDoc(), rating: "conditional" }));
});

test("M4: nothing may be scored before the defence is under way",
  async () => {
    for (const status of ["scheduled", "cancelled"]) {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "defenses/m4"),
          defDoc({ status }));
      });
      await assertFails(setDoc(
        doc(asDefUser("pan-uid", "pan@isufst.edu.ph"),
            "defenses/m4/evaluations/pan-uid"),
        evalDoc()));
    }
  });

test("M4: a live defence may be scored", async () => {
  await seedM4({ status: "inProgress" });
  await assertSucceeds(setDoc(
    doc(asDefUser("pan-uid", "pan@isufst.edu.ph"),
        "defenses/m4/evaluations/pan-uid"),
    evalDoc()));
});

// D39: a panelist who can see two colleagues at 78 and 81 before marking
// is anchored, and §8b's deliberation is worth less if the numbers
// converged before anyone spoke.
test("M4: before release, a panelist reads their own and NOT a colleague's",
  async () => {
    await seedM4();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "defenses/m4/evaluations/pan-uid"), evalDoc());
      await setDoc(doc(db, "defenses/m4/evaluations/pan2-uid"), evalDoc());
    });
    const db = asDefUser("pan-uid", "pan@isufst.edu.ph");
    await assertSucceeds(
      getDoc(doc(db, "defenses/m4/evaluations/pan-uid")));
    await assertFails(
      getDoc(doc(db, "defenses/m4/evaluations/pan2-uid")));
    await assertFails(getDocs(collection(db, "defenses/m4/evaluations")));
  });

// The adviser releases WITHOUT seeing the contents. Release is a
// procedural act on a count, not an editorial one.
test("M4: the adviser may NOT read an evaluation before release",
  async () => {
    await seedM4();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "defenses/m4/evaluations/pan-uid"),
        evalDoc());
    });
    await assertFails(getDoc(doc(
      asDefUser("adviser-uid", "adviser@isufst.edu.ph"),
      "defenses/m4/evaluations/pan-uid")));
  });

test("M4: after release the panel, adviser, coordinator and dean read all",
  async () => {
    await seedM4({ evaluationsReleasedAt: Timestamp.now() });
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "defenses/m4/evaluations/pan2-uid"),
        evalDoc());
    });
    for (const uid of ["pan-uid", "pan2-uid", "adviser-uid", "coord-uid",
                       "dean-uid"]) {
      await assertSucceeds(getDocs(collection(
        asDefUser(uid, `${uid}@isufst.edu.ph`),
        "defenses/m4/evaluations")));
    }
  });

// D47: the numbers are unreachable for the group, not merely unrendered.
// §11b routes the grading sheet to the subject professor on paper.
test("M4 attack: the LEADER may not read evaluations, even after release",
  async () => {
    await seedM4({ evaluationsReleasedAt: Timestamp.now() });
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "defenses/m4/evaluations/pan-uid"),
        evalDoc());
    });
    const db = asDefUser("leader-uid", "leader@isufst.edu.ph");
    await assertFails(getDoc(doc(db, "defenses/m4/evaluations/pan-uid")));
    await assertFails(getDocs(collection(db, "defenses/m4/evaluations")));
  });

// D44: before the seal it is a draft, after it it is the record.
test("M4: a panelist edits their sheet until release, then cannot",
  async () => {
    await seedM4();
    const db = asDefUser("pan-uid", "pan@isufst.edu.ph");
    await assertSucceeds(setDoc(
      doc(db, "defenses/m4/evaluations/pan-uid"), evalDoc()));
    await assertSucceeds(updateDoc(
      doc(db, "defenses/m4/evaluations/pan-uid"),
      { scores: fullScores({ title: 3 }), total: 98,
        updatedAt: serverTimestamp() }));

    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "defenses/m4"),
        { evaluationsReleasedAt: Timestamp.now() });
    });
    await assertFails(updateDoc(
      doc(db, "defenses/m4/evaluations/pan-uid"),
      { scores: fullScores({ title: 1 }), total: 96,
        updatedAt: serverTimestamp() }));
  });

test("M4 attack: an edit may not rewrite when it was first submitted",
  async () => {
    await seedM4();
    const db = asDefUser("pan-uid", "pan@isufst.edu.ph");
    await assertSucceeds(setDoc(
      doc(db, "defenses/m4/evaluations/pan-uid"), evalDoc()));
    await assertFails(updateDoc(
      doc(db, "defenses/m4/evaluations/pan-uid"),
      { submittedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });

// The record is evidence. Same reasoning as the defence itself, and as
// M3's append-only comments.
test("M4 attack: nobody may delete an evaluation", async () => {
  await seedM4();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "defenses/m4/evaluations/pan-uid"),
      evalDoc());
  });
  for (const uid of ["pan-uid", "adviser-uid", "coord-uid", "dean-uid"]) {
    await assertFails(deleteDoc(doc(
      asDefUser(uid, `${uid}@isufst.edu.ph`),
      "defenses/m4/evaluations/pan-uid")));
  }
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd rules-test && npm test`
Expected: FAIL. Every "MAY write / reads" case fails because no rule
grants the subcollection, so the default deny applies. The attack cases
pass vacuously — which is exactly why Step 4 must re-run them: an attack
test that passes before the feature exists proves nothing.

- [ ] **Step 3: Write the rules**

In `firestore.rules`, inside `match /defenses/{defenseId}`, after the
closing brace of `match /comments/{commentId}`:

```
      // ---- M4: Form 5c evaluations ----
      //
      // One document per panelist, keyed by their uid so nobody files two.
      // Guidelines §8a: the panel rates Pass or Fail AND completes Form 5c
      // so a numerical grade can be given.
      match /evaluations/{evaluatorUid} {
        function parent() {
          return get(/databases/$(database)/documents/defenses/$(defenseId)).data;
        }
        // The adviser is deliberately NOT here. They advised this thesis
        // for months and cannot mark it at arm's length, so the rule --
        // not merely a hidden button -- refuses them. They comment in the
        // room like everyone else, and they hold the two acts below.
        function isPanelistHere() {
          return signedIn() && request.auth.uid in parent().panelUids;
        }
        // Presence, never a sentinel: `.get(k, <sentinel>) == <sentinel>`
        // silently changes meaning the day a legitimate value equals the
        // sentinel, which cost this project two rounds already.
        function released() {
          return 'evaluationsReleasedAt' in parent();
        }
        function scores() {
          return request.resource.data.scores;
        }

        // THESE ELEVEN NUMBERS EXIST TWICE. The other copy is
        // `evaluationCriteria` in lib/data/models/evaluation_criteria.dart,
        // which this cannot import. If they drift, the form accepts a
        // score this denies -- so rules.test.js walks every boundary at
        // weight and weight+1.
        function bounded() {
          let s = scores();
          return s.keys().hasAll(['title', 'introduction',
                    'materialsAndMethods', 'result', 'discussion',
                    'conclusion', 'recommendation', 'references',
                    'preciseness', 'alertness', 'personality'])
              && s.keys().hasOnly(['title', 'introduction',
                    'materialsAndMethods', 'result', 'discussion',
                    'conclusion', 'recommendation', 'references',
                    'preciseness', 'alertness', 'personality'])
              && s.title is int && s.title >= 0 && s.title <= 5
              && s.introduction is int
                 && s.introduction >= 0 && s.introduction <= 5
              && s.materialsAndMethods is int
                 && s.materialsAndMethods >= 0
                 && s.materialsAndMethods <= 10
              && s.result is int && s.result >= 0 && s.result <= 10
              && s.discussion is int
                 && s.discussion >= 0 && s.discussion <= 10
              && s.conclusion is int
                 && s.conclusion >= 0 && s.conclusion <= 5
              && s.recommendation is int
                 && s.recommendation >= 0 && s.recommendation <= 2
              && s.references is int
                 && s.references >= 0 && s.references <= 3
              && s.preciseness is int
                 && s.preciseness >= 0 && s.preciseness <= 15
              && s.alertness is int
                 && s.alertness >= 0 && s.alertness <= 25
              && s.personality is int
                 && s.personality >= 0 && s.personality <= 10;
        }

        function wellFormed() {
          let d = request.resource.data;
          let s = scores();
          return d.keys().hasAll(['scores', 'comments', 'total', 'rating',
                                  'submittedAt', 'updatedAt'])
              && d.keys().hasOnly(['scores', 'comments', 'total', 'rating',
                                   'submittedAt', 'updatedAt'])
              && bounded()
              // A stored total that could disagree with its own scores
              // would be worse than no stored total, so it is recomputed
              // here on every write rather than trusted.
              && d.total == s.title + s.introduction
                          + s.materialsAndMethods + s.result + s.discussion
                          + s.conclusion + s.recommendation + s.references
                          + s.preciseness + s.alertness + s.personality
              && d.rating in ['pass', 'fail']
              // Section B carries no comment lines on the printed form,
              // so its three keys are not accepted here.
              && d.comments.keys().hasOnly(['title', 'introduction',
                    'materialsAndMethods', 'result', 'discussion',
                    'conclusion', 'recommendation', 'references']);
        }

        // Your own always; everyone else's only once released (D39).
        // The first arm authorises on the {evaluatorUid} wildcard, which
        // is sound because a panelist reading their own knows its id.
        //
        // `parent()` costs one get per document evaluated. Safe here --
        // an evaluations subcollection holds at most one document per
        // panelist -- unlike the `list` over `defenses` above, which is
        // why that one snapshots leaderUid rather than reading the thesis.
        allow get, list: if (signedIn()
                             && request.auth.uid == evaluatorUid
                             && isPanelistHere())
                         || (released()
                             && (isPanelistHere()
                                 || parent().adviserUid == request.auth.uid
                                 || isCoordinator() || isDean()));

        // Nothing has been presented to score while the defence is merely
        // scheduled, and a cancelled one is never scorable.
        allow create: if verified()
                      && isPanelistHere()
                      && request.auth.uid == evaluatorUid
                      && parent().status in ['inProgress', 'completed']
                      && !released()
                      && wellFormed()
                      && request.resource.data.submittedAt == request.time
                      && request.resource.data.updatedAt == request.time;

        // Editable until the seal, then frozen (D44). Freezing on first
        // submit would make a mistyped 2-instead-of-20 permanent in a
        // record that has no delete.
        allow update: if verified()
                      && isPanelistHere()
                      && request.auth.uid == evaluatorUid
                      && !released()
                      && wellFormed()
                      // "When did this panelist first submit" must stay
                      // answerable after an edit.
                      && request.resource.data.submittedAt
                         == resource.data.submittedAt
                      && request.resource.data.updatedAt == request.time;

        // A grade entered and withdrawn is exactly the gap in the record
        // that §8b's deliberation would need to explain.
        allow delete: if false;
      }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd rules-test && npm test`
Expected: PASS — all 17 new M4 tests, and every pre-existing test still
green.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git commit -m "feat: authorise Form 5c evaluations, sealed until release"
```

---

### Task 5: Rules — the release and the verdict

**Files:**
- Modify: `firestore.rules` — two arms after the existing "Adviser arm: the release" on the defence document
- Test: `rules-test/rules.test.js` (append)

**Interfaces:**
- Consumes: `seedM4`, `asDefUser`, `defDoc` from Task 4.
- Produces: the defence-document contract for `evaluationsReleasedAt`, `panelVerdict`, `verdictRecordedBy`, `verdictRecordedAt`.

- [ ] **Step 1: Write the failing tests**

Append to `rules-test/rules.test.js`, before `test.after(...)`:

```js
// ---------- M4: release and verdict ----------

test("M4: the adviser releases the evaluations, once", async () => {
  await seedM4();
  const db = asDefUser("adviser-uid", "adviser@isufst.edu.ph");
  await assertSucceeds(updateDoc(doc(db, "defenses/m4"),
    { evaluationsReleasedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, "defenses/m4"),
    { evaluationsReleasedAt: serverTimestamp() }));
});

test("M4 attack: nobody but the adviser releases", async () => {
  await seedM4();
  for (const uid of ["pan-uid", "coord-uid", "dean-uid", "leader-uid"]) {
    await assertFails(updateDoc(
      doc(asDefUser(uid, `${uid}@isufst.edu.ph`), "defenses/m4"),
      { evaluationsReleasedAt: serverTimestamp() }));
  }
});

test("M4: a defence still running may not have its grades released",
  async () => {
    await seedM4({ status: "inProgress" });
    await assertFails(updateDoc(
      doc(asDefUser("adviser-uid", "adviser@isufst.edu.ph"),
          "defenses/m4"),
      { evaluationsReleasedAt: serverTimestamp() }));
  });

// The affectedKeys guard is what stops either new arm doubling as a
// status transition -- the same discipline the four coordinator arms use.
test("M4 attack: a release may not smuggle a status change", async () => {
  await seedM4();
  await assertFails(updateDoc(
    doc(asDefUser("adviser-uid", "adviser@isufst.edu.ph"), "defenses/m4"),
    { evaluationsReleasedAt: serverTimestamp(), status: "cancelled" }));
});

// D43. §8b has the panel deliberate OVER the final grades, so they must
// be able to see them first: release precedes the verdict, always.
test("M4: no verdict may be recorded before release", async () => {
  await seedM4();
  await assertFails(updateDoc(
    doc(asDefUser("adviser-uid", "adviser@isufst.edu.ph"), "defenses/m4"),
    { panelVerdict: "pass", verdictRecordedBy: "adviser-uid",
      verdictRecordedAt: serverTimestamp() }));
});

test("M4: after release the adviser records the verdict, once", async () => {
  await seedM4({ evaluationsReleasedAt: Timestamp.now() });
  const db = asDefUser("adviser-uid", "adviser@isufst.edu.ph");
  await assertSucceeds(updateDoc(doc(db, "defenses/m4"),
    { panelVerdict: "pass", verdictRecordedBy: "adviser-uid",
      verdictRecordedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, "defenses/m4"),
    { panelVerdict: "fail", verdictRecordedBy: "adviser-uid",
      verdictRecordedAt: serverTimestamp() }));
});

test("M4 attack: a panelist may not record the verdict", async () => {
  await seedM4({ evaluationsReleasedAt: Timestamp.now() });
  for (const uid of ["pan-uid", "coord-uid", "dean-uid"]) {
    await assertFails(updateDoc(
      doc(asDefUser(uid, `${uid}@isufst.edu.ph`), "defenses/m4"),
      { panelVerdict: "pass", verdictRecordedBy: uid,
        verdictRecordedAt: serverTimestamp() }));
  }
});

// The scribe must be named truthfully, or the field records nothing.
test("M4 attack: the adviser may not record it under another name",
  async () => {
    await seedM4({ evaluationsReleasedAt: Timestamp.now() });
    await assertFails(updateDoc(
      doc(asDefUser("adviser-uid", "adviser@isufst.edu.ph"),
          "defenses/m4"),
      { panelVerdict: "pass", verdictRecordedBy: "pan-uid",
        verdictRecordedAt: serverTimestamp() }));
  });

test("M4 attack: a verdict outside pass/fail is denied", async () => {
  await seedM4({ evaluationsReleasedAt: Timestamp.now() });
  await assertFails(updateDoc(
    doc(asDefUser("adviser-uid", "adviser@isufst.edu.ph"), "defenses/m4"),
    { panelVerdict: "redefend", verdictRecordedBy: "adviser-uid",
      verdictRecordedAt: serverTimestamp() }));
});

test("M4 attack: a partial verdict write is denied", async () => {
  await seedM4({ evaluationsReleasedAt: Timestamp.now() });
  await assertFails(updateDoc(
    doc(asDefUser("adviser-uid", "adviser@isufst.edu.ph"), "defenses/m4"),
    { panelVerdict: "pass" }));
});

// Consolidation and release are separate gates on separate things.
test("M4: releasing the grades does not release the comments", async () => {
  await seedM4();
  const db = asDefUser("adviser-uid", "adviser@isufst.edu.ph");
  await assertSucceeds(updateDoc(doc(db, "defenses/m4"),
    { evaluationsReleasedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(db, "defenses/m4"),
    { consolidatedAt: serverTimestamp() }));
});

// A defence created today must still refuse fields that belong to acts
// happening after it closes.
test("M4 attack: a create may not pre-set the seal or the verdict",
  async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "theses/dt1"), defThesis());
      await setDoc(doc(db, "users/coord-uid"),
        { role: "coordinator", active: true });
    });
    await assertFails(setDoc(
      doc(asDefUser("coord-uid", "coord@isufst.edu.ph"), "defenses/m4b"),
      defDoc({ evaluationsReleasedAt: serverTimestamp() })));
    await assertFails(setDoc(
      doc(asDefUser("coord-uid", "coord@isufst.edu.ph"), "defenses/m4c"),
      defDoc({ panelVerdict: "pass" })));
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd rules-test && npm test`
Expected: FAIL on every `assertSucceeds` case — no arm grants either
field, so the default deny applies.

- [ ] **Step 3: Write the rules**

In `firestore.rules`, immediately after the existing "Adviser arm: the
release, once, and only after it is closed" block and before `// The
defence record is evidence.`:

```
      // Adviser arm 2 -- RELEASE the evaluations to the panel.
      //
      // §8b has the panel deliberate over the final grades, so they must
      // be able to see them: this is what opens the set. It is the same
      // shape as the consolidation arm above, deliberately -- one pattern
      // to learn rather than two.
      //
      // NOT conditioned on "everyone has submitted": Firestore rules
      // cannot count the documents in a collection, so that sentence is
      // not expressible here. The adviser can release at 2 of 3. The
      // grades screen therefore prints the count on the button itself, so
      // an early release is a visible choice rather than an accident.
      allow update: if verified()
                    && defence().adviserUid == request.auth.uid
                    && defence().status == 'completed'
                    && !('evaluationsReleasedAt' in defence())
                    && incoming().diff(defence()).affectedKeys()
                       .hasOnly(['evaluationsReleasedAt'])
                    && incoming().evaluationsReleasedAt == request.time;

      // Adviser arm 3 -- RECORD the §8b verdict.
      //
      // Only after release (the panel must see the grades to deliberate),
      // and only once: a recorded verdict is the panel's decision, not a
      // draft. `verdictRecordedBy` must be the adviser themselves --
      // someone barred from scoring at all has to be visibly the scribe,
      // and a field that could name anyone would record nothing.
      allow update: if verified()
                    && defence().adviserUid == request.auth.uid
                    && 'evaluationsReleasedAt' in defence()
                    && !('panelVerdict' in defence())
                    && incoming().diff(defence()).affectedKeys()
                       .hasOnly(['panelVerdict', 'verdictRecordedBy',
                                 'verdictRecordedAt'])
                    && incoming().panelVerdict in ['pass', 'fail']
                    && incoming().verdictRecordedBy == request.auth.uid
                    && incoming().verdictRecordedAt == request.time;
```

The `allow create` arm above already uses `hasOnly([...])` on its key
set, which refuses all four new fields at creation with no change needed
— the "a create may not pre-set the seal" test proves it.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd rules-test && npm test`
Expected: PASS — 12 new tests plus everything before them.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git commit -m "feat: let the adviser release grades and record the verdict"
```

---

### Task 6: Repository — submit, edit and watch evaluations

**Files:**
- Modify: `lib/data/repositories/defence_repository.dart`
- Test: `test/data/repositories/evaluation_repository_test.dart` (new)

**Interfaces:**
- Consumes: `Evaluation`, `PassFail`, `totalOf` (Task 2); `evaluationCriteria`, `contentKeys`, `criterionFor` (Task 1).
- Produces: `DefenceRepository.submitEvaluation({required String defenceId, required String evaluatorUid, required Map<String, int> scores, required Map<String, String> comments, required PassFail rating})`, `Stream<List<Evaluation>> watchEvaluations(String defenceId)`, `Stream<Evaluation?> watchMyEvaluation(String defenceId, String uid)`.

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/evaluation_repository_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';

Map<String, int> perfect() =>
    {for (final c in evaluationCriteria) c.key: c.weight};

Future<FakeFirebaseFirestore> seed({
  String status = 'completed',
  DateTime? releasedAt,
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1',
    'type': 'final',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
    'venue': 'AVR',
    'panelUids': <String>['p1', 'p2', 'p3'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': status,
    'createdBy': 'c1',
    if (releasedAt != null)
      'evaluationsReleasedAt': Timestamp.fromDate(releasedAt),
  });
  return db;
}

void main() {
  test('a submitted evaluation reads back with its computed total',
      () async {
    final repo = DefenceRepository(await seed());

    await repo.submitEvaluation(
      defenceId: 'd1',
      evaluatorUid: 'p1',
      scores: perfect(),
      comments: const {'title': 'Narrow it.'},
      rating: PassFail.pass,
    );

    final mine = await repo.watchMyEvaluation('d1', 'p1').first;
    expect(mine!.total, 100);
    expect(mine.rating, PassFail.pass);
    expect(mine.comments['title'], 'Narrow it.');
    expect(mine.sectionTotal(EvaluationSection.content), 50);
  });

  test('a second submit edits the same document, not a new one', () async {
    final db = await seed();
    final repo = DefenceRepository(db);

    await repo.submitEvaluation(
      defenceId: 'd1', evaluatorUid: 'p1', scores: perfect(),
      comments: const {}, rating: PassFail.pass);
    await repo.submitEvaluation(
      defenceId: 'd1', evaluatorUid: 'p1',
      scores: {...perfect(), 'title': 1}, comments: const {},
      rating: PassFail.fail);

    final all = await repo.watchEvaluations('d1').first;
    expect(all.length, 1);
    expect(all.single.total, 96);
    expect(all.single.rating, PassFail.fail);
  });

  test('a missing criterion is refused before it reaches Firestore',
      () async {
    final repo = DefenceRepository(await seed());
    final short = perfect()..remove('personality');

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', scores: short,
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a score above its own weight is refused', () async {
    final repo = DefenceRepository(await seed());

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1',
        scores: {...perfect(), 'title': 6}, comments: const {},
        rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1',
        scores: {...perfect(), 'alertness': -1}, comments: const {},
        rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a comment on a Section B criterion is refused', () async {
    final repo = DefenceRepository(await seed());

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', scores: perfect(),
        comments: const {'alertness': 'no such field'},
        rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a blank comment is dropped rather than stored empty', () async {
    final repo = DefenceRepository(await seed());

    await repo.submitEvaluation(
      defenceId: 'd1', evaluatorUid: 'p1', scores: perfect(),
      comments: const {'title': '   ', 'result': ' ok '},
      rating: PassFail.pass);

    final mine = await repo.watchMyEvaluation('d1', 'p1').first;
    expect(mine!.comments.containsKey('title'), isFalse);
    expect(mine.comments['result'], 'ok');
  });

  // fake_cloud_firestore enforces NO rules, so without this check every
  // test would pass against a write the emulator denies.
  test('a defence that has not started cannot be scored', () async {
    final repo = DefenceRepository(await seed(status: 'scheduled'));

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', scores: perfect(),
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  test('a released evaluation can no longer be edited', () async {
    final repo =
        DefenceRepository(await seed(releasedAt: DateTime(2026, 9, 23)));

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', scores: perfect(),
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  // fake_cloud_firestore returns INSERTION order, so these are written
  // out of order deliberately -- otherwise an unsorted implementation
  // would pass this test.
  test('evaluations come back ordered by evaluator uid', () async {
    final db = await seed();
    final repo = DefenceRepository(db);

    for (final uid in ['p3', 'p1', 'p2']) {
      await repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: uid, scores: perfect(),
        comments: const {}, rating: PassFail.pass);
    }

    final all = await repo.watchEvaluations('d1').first;
    expect(all.map((e) => e.evaluatorUid), ['p1', 'p2', 'p3']);
  });

  test('no evaluation yet reads as null, not as an empty sheet', () async {
    final repo = DefenceRepository(await seed());
    expect(await repo.watchMyEvaluation('d1', 'p1').first, isNull);
    expect(await repo.watchEvaluations('d1').first, isEmpty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/repositories/evaluation_repository_test.dart`
Expected: FAIL — `The method 'submitEvaluation' isn't defined for the type 'DefenceRepository'`

- [ ] **Step 3: Write the implementation**

Add to the imports of `lib/data/repositories/defence_repository.dart`:

```dart
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
```

Add to `DefenceRepository`, after `watchComments`:

```dart
  CollectionReference<Map<String, dynamic>> _evaluations(String defenceId) =>
      _defence(defenceId).collection('evaluations');

  Evaluation _toEvaluation(String id, Map<String, dynamic> raw) {
    return Evaluation.fromMap(id, {
      ...raw,
      'submittedAt': (raw['submittedAt'] as Timestamp?)?.toDate(),
      'updatedAt': (raw['updatedAt'] as Timestamp?)?.toDate(),
    });
  }

  /// Every submitted sheet for a defence, ordered by evaluator uid.
  ///
  /// Sorted in Dart rather than with `orderBy`: the document id IS the
  /// evaluator uid, so there is no field to order on, and a stable order
  /// is what stops the grades table reshuffling its columns between
  /// snapshots.
  Stream<List<Evaluation>> watchEvaluations(String defenceId) {
    return _evaluations(defenceId).snapshots().map((s) {
      final list =
          s.docs.map((d) => _toEvaluation(d.id, d.data())).toList();
      list.sort((a, b) => a.evaluatorUid.compareTo(b.evaluatorUid));
      return list;
    });
  }

  /// One panelist's own sheet, or null if they have not submitted.
  ///
  /// Null is a real answer here, not a failure: before release the rules
  /// let a panelist read only this one document, so this is the only
  /// evaluation stream they can open at all.
  Stream<Evaluation?> watchMyEvaluation(String defenceId, String uid) {
    return _evaluations(defenceId).doc(uid).snapshots().map(
        (s) => s.exists ? _toEvaluation(s.id, s.data()!) : null);
  }

  /// Writes or replaces one panelist's Form 5c.
  ///
  /// `set` with no merge, so an edit replaces the sheet wholesale rather
  /// than leaving a criterion from an earlier version behind.
  ///
  /// Every check below is ALSO a rule. They are repeated here because
  /// `fake_cloud_firestore` enforces none of them, so without these the
  /// whole Dart suite would pass against writes production denies -- and
  /// because a client-side refusal can say WHY, which a
  /// `permission-denied` cannot.
  Future<void> submitEvaluation({
    required String defenceId,
    required String evaluatorUid,
    required Map<String, int> scores,
    required Map<String, String> comments,
    required PassFail rating,
  }) async {
    for (final c in evaluationCriteria) {
      final v = scores[c.key];
      if (v == null) {
        throw ArgumentError('Score every criterion before submitting.');
      }
      if (v < 0 || v > c.weight) {
        throw ArgumentError(
            '${c.label} is scored out of ${c.weight}.');
      }
    }
    if (scores.length != evaluationCriteria.length) {
      throw ArgumentError('That sheet has a criterion this form does not.');
    }
    for (final key in comments.keys) {
      if (!contentKeys.contains(key)) {
        throw ArgumentError(
            'Only the Content criteria take a comment on Form 5c.');
      }
    }

    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final data = snap.data()!;

    final status = DefenceStatus.fromString(data['status'] as String?);
    if (status != DefenceStatus.inProgress &&
        status != DefenceStatus.completed) {
      throw StateError(
          'A defence can only be scored once it is under way.');
    }
    if (data['evaluationsReleasedAt'] != null) {
      throw StateError(
          'These evaluations have been released and can no longer be '
          'changed.');
    }

    // Trimmed, and blanks dropped rather than stored: an empty string is
    // not a comment, and the rules accept the key either way, so the
    // distinction has to be made here.
    final cleaned = <String, String>{};
    comments.forEach((key, value) {
      final text = value.trim();
      if (text.isNotEmpty) cleaned[key] = text;
    });

    final existing = await _evaluations(defenceId).doc(evaluatorUid).get();

    await _evaluations(defenceId).doc(evaluatorUid).set({
      'scores': scores,
      'comments': cleaned,
      'total': totalOf(scores),
      'rating': rating.value,
      // On an edit, submittedAt must survive unchanged -- the rules pin
      // it to its stored value, so re-stamping it here would be denied in
      // production while passing against the fake.
      'submittedAt': existing.exists
          ? existing.data()!['submittedAt']
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/repositories/evaluation_repository_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/defence_repository.dart test/data/repositories/evaluation_repository_test.dart
git commit -m "feat: submit, edit and read Form 5c evaluations"
```

---

### Task 7: Repository — release and record the verdict

**Files:**
- Modify: `lib/data/repositories/defence_repository.dart`
- Test: `test/data/repositories/evaluation_repository_test.dart` (append)

**Interfaces:**
- Produces: `DefenceRepository.releaseEvaluations(String defenceId)`, `DefenceRepository.recordVerdict({required String defenceId, required String adviserUid, required PassFail verdict})`.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/data/repositories/evaluation_repository_test.dart`:

```dart
  test('release marks the defence and cannot be repeated', () async {
    final repo = DefenceRepository(await seed());

    await repo.releaseEvaluations('d1');
    final d = await repo.watchDefence('d1').first;
    expect(d!.evaluationsReleased, isTrue);

    expect(() => repo.releaseEvaluations('d1'),
        throwsA(isA<StateError>()));
  });

  test('a defence still running cannot have its grades released',
      () async {
    final repo = DefenceRepository(await seed(status: 'inProgress'));
    expect(() => repo.releaseEvaluations('d1'),
        throwsA(isA<StateError>()));
  });

  // D43: §8b has the panel deliberate over the grades, so they must be
  // able to see them first.
  test('no verdict before release', () async {
    final repo = DefenceRepository(await seed());
    expect(
      () => repo.recordVerdict(
          defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  test('after release the verdict is recorded with its scribe', () async {
    final repo =
        DefenceRepository(await seed(releasedAt: DateTime(2026, 9, 23)));

    await repo.recordVerdict(
        defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.pass);

    final d = await repo.watchDefence('d1').first;
    expect(d!.panelVerdict, PassFail.pass);
    expect(d.verdictRecordedBy, 'a1');
    expect(d.hasVerdict, isTrue);
  });

  test('a recorded verdict is final', () async {
    final repo =
        DefenceRepository(await seed(releasedAt: DateTime(2026, 9, 23)));

    await repo.recordVerdict(
        defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.pass);

    expect(
      () => repo.recordVerdict(
          defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.fail),
      throwsA(isA<StateError>()),
    );
  });

  test('only the adviser of record may record the verdict', () async {
    final repo =
        DefenceRepository(await seed(releasedAt: DateTime(2026, 9, 23)));

    expect(
      () => repo.recordVerdict(
          defenceId: 'd1', adviserUid: 'p1', verdict: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/repositories/evaluation_repository_test.dart`
Expected: FAIL — `The method 'releaseEvaluations' isn't defined`

- [ ] **Step 3: Write the implementation**

Add to `DefenceRepository`, after the existing `release`:

```dart
  /// The adviser's release of the panel's evaluations to each other.
  ///
  /// Deliberately NOT conditioned on "everyone has submitted". Firestore
  /// rules cannot count documents in a collection, so that condition is
  /// unenforceable at the boundary -- and a check here that the rules
  /// cannot back would be theatre: anyone with the SDK could bypass it.
  /// The grades screen prints the count on the button instead, so an
  /// early release is a visible choice.
  Future<void> releaseEvaluations(String defenceId) async {
    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final data = snap.data()!;

    if (DefenceStatus.fromString(data['status'] as String?) !=
        DefenceStatus.completed) {
      throw StateError(
          'Release the evaluations once the defence is closed.');
    }
    if (data['evaluationsReleasedAt'] != null) {
      throw StateError('These evaluations have already been released.');
    }

    await _defence(defenceId)
        .update({'evaluationsReleasedAt': FieldValue.serverTimestamp()});
  }

  /// Records the verdict the panel deliberated under Guidelines §8b.
  ///
  /// The adviser is the scribe, not the decider -- they are barred from
  /// scoring at all. Nothing here derives the verdict from the panelists'
  /// ratings, and nothing should: §8b hands the decision to a
  /// conversation between people.
  Future<void> recordVerdict({
    required String defenceId,
    required String adviserUid,
    required PassFail verdict,
  }) async {
    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final data = snap.data()!;

    if (data['adviserUid'] != adviserUid) {
      throw StateError(
          'Only the adviser for this defence records the verdict.');
    }
    if (data['evaluationsReleasedAt'] == null) {
      throw StateError(
          'Release the evaluations first — the panel deliberates over the '
          'grades.');
    }
    if (data['panelVerdict'] != null) {
      throw StateError('A verdict has already been recorded.');
    }

    await _defence(defenceId).update({
      'panelVerdict': verdict.value,
      'verdictRecordedBy': adviserUid,
      'verdictRecordedAt': FieldValue.serverTimestamp(),
    });
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/repositories/evaluation_repository_test.dart`
Expected: PASS, 16 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/defence_repository.dart test/data/repositories/evaluation_repository_test.dart
git commit -m "feat: release evaluations and record the deliberated verdict"
```

---

### Task 8: Providers

**Files:**
- Modify: `lib/providers/defence_providers.dart`
- Test: `test/providers/evaluation_providers_test.dart` (new)

**Interfaces:**
- Produces: `defenceEvaluationsProvider` (`StreamProvider.family<List<Evaluation>, String>`), `myEvaluationProvider` (`StreamProvider.family<Evaluation?, String>`).

- [ ] **Step 1: Write the failing test**

Create `test/providers/evaluation_providers_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1', 'type': 'final',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
    'venue': 'AVR', 'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1', 'leaderUid': 'l1', 'status': 'completed',
    'createdBy': 'c1',
  });
  for (final uid in ['p2', 'p1']) {
    await db
        .collection('defenses').doc('d1')
        .collection('evaluations').doc(uid)
        .set({
      'scores': {for (final c in evaluationCriteria) c.key: c.weight},
      'comments': const <String, String>{},
      'total': 100,
      'rating': 'pass',
    });
  }
  return db;
}

ProviderContainer containerFor(FakeFirebaseFirestore db, String uid) {
  return ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
    ),
  ]);
}

void main() {
  test('defenceEvaluationsProvider yields both sheets in uid order',
      () async {
    final c = containerFor(await seed(), 'p1');
    addTearDown(c.dispose);

    final list = await c.read(defenceEvaluationsProvider('d1').future);
    expect(list.map((e) => e.evaluatorUid), ['p1', 'p2']);
  });

  test('myEvaluationProvider yields only the signed-in panelist\'s',
      () async {
    final c = containerFor(await seed(), 'p2');
    addTearDown(c.dispose);

    final mine = await c.read(myEvaluationProvider('d1').future);
    expect(mine!.evaluatorUid, 'p2');
  });

  test('myEvaluationProvider is null when nobody is signed in', () async {
    final db = await seed();
    final c = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider
          .overrideWithValue(MockFirebaseAuth(signedIn: false)),
    ]);
    addTearDown(c.dispose);

    expect(await c.read(myEvaluationProvider('d1').future), isNull);
  });

  test('myEvaluationProvider is null when this panelist has not submitted',
      () async {
    final c = containerFor(await seed(), 'p3');
    addTearDown(c.dispose);

    expect(await c.read(myEvaluationProvider('d1').future), isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/providers/evaluation_providers_test.dart`
Expected: FAIL — `Undefined name 'defenceEvaluationsProvider'`

- [ ] **Step 3: Write the implementation**

Add to the imports of `lib/providers/defence_providers.dart`:

```dart
import 'package:ethesishub/data/models/evaluation.dart';
```

Append to the file:

```dart
/// Every submitted evaluation for a defence.
///
/// Before release the rules let a panelist read only their own, so this
/// stream ERRORS for them rather than returning an empty list -- which is
/// correct and must not be smoothed over: an empty list would read as
/// "nobody has submitted", and the grades screen would then show a
/// confident, wrong zero. The screen uses [myEvaluationProvider] and the
/// defence's own release flag to decide whether to open this at all.
final defenceEvaluationsProvider =
    StreamProvider.family<List<Evaluation>, String>((ref, defenceId) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(defenceRepositoryProvider).watchEvaluations(defenceId);
});

/// The signed-in panelist's own sheet for a defence, or null.
///
/// Null covers three different things on purpose -- nobody signed in, not
/// a panelist, or a panelist who has not submitted -- because the screen
/// treats all three the same way: there is nothing of yours to show. A
/// FAILED read is not among them; that arrives as an error on the
/// AsyncValue and must render as one.
final myEvaluationProvider =
    StreamProvider.family<Evaluation?, String>((ref, defenceId) {
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) return Stream.value(null);
  return ref
      .watch(defenceRepositoryProvider)
      .watchMyEvaluation(defenceId, uid);
});
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/providers/evaluation_providers_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/defence_providers.dart test/providers/evaluation_providers_test.dart
git commit -m "feat: add evaluation providers"
```

---

### Task 9: The evaluation screen

**Files:**
- Create: `lib/features/defence/evaluation_screen.dart`
- Test: `test/features/defence/evaluation_screen_test.dart`

**Interfaces:**
- Consumes: `myEvaluationProvider`, `defenceProvider`, `defenceRepositoryProvider`, `signedInUidProvider`, `evaluationCriteria`, `EvaluationSection`, `PassFail`, `totalOf`.
- Produces: `EvaluationScreen({required String defenceId})`.

Read `lib/features/defence/consolidated_defence_screen.dart` first and
follow its `_framed` helper pattern exactly — a `KeyedSubtree` around a
`PageShell`, with no `Scaffold` and no `AppBar` of its own, because the
shell above supplies both.

- [ ] **Step 1: Write the failing test**

Create `test/features/defence/evaluation_screen_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/features/defence/evaluation_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seed({
  String status = 'completed',
  DateTime? releasedAt,
  Map<String, int>? existing,
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1', 'type': 'final',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
    'venue': 'AVR', 'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1', 'leaderUid': 'l1', 'status': status,
    'createdBy': 'c1',
    if (releasedAt != null)
      'evaluationsReleasedAt': Timestamp.fromDate(releasedAt),
  });
  if (existing != null) {
    await db
        .collection('defenses').doc('d1')
        .collection('evaluations').doc('p1')
        .set({
      'scores': existing,
      'comments': const <String, String>{},
      'total': existing.values.fold<int>(0, (a, b) => a + b),
      'rating': 'pass',
    });
  }
  return db;
}

Widget app(FakeFirebaseFirestore db, String uid) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: EvaluationScreen(defenceId: 'd1')),
    ),
  );
}

void main() {
  testWidgets('renders every criterion of Form 5c', (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    for (final c in evaluationCriteria) {
      expect(find.byKey(Key('score_${c.key}')), findsOneWidget,
          reason: c.key);
    }
  });

  testWidgets('only Content criteria carry a comment field',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comment_title')), findsOneWidget);
    expect(find.byKey(const Key('comment_alertness')), findsNothing);
  });

  testWidgets('the running total sums the scores as they change',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('finalGrade')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const Key('finalGrade'))).data, '0');

    await tester.tap(find.byKey(const Key('plus_title')));
    await tester.pump();
    expect(
        tester.widget<Text>(find.byKey(const Key('finalGrade'))).data, '1');
  });

  // D34's mitigation: eleven different maximums, so the control refuses
  // out-of-range rather than accepting then rejecting it.
  testWidgets('a stepper clamps at zero and at its own weight',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    // recommendation is worth 2 -- three taps must not reach 3.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('plus_recommendation')));
      await tester.pump();
    }
    expect(
        tester
            .widget<Text>(find.byKey(const Key('score_recommendation')))
            .data,
        '2');

    await tester.tap(find.byKey(const Key('minus_title')));
    await tester.pump();
    expect(
        tester.widget<Text>(find.byKey(const Key('score_title'))).data, '0');
  });

  testWidgets('submit is disabled until every criterion is scored',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submitEvaluation')))
            .onPressed,
        isNull);
  });

  testWidgets('an existing sheet loads its scores back', (tester) async {
    final scores = {for (final c in evaluationCriteria) c.key: c.weight};
    await tester.pumpWidget(app(await seed(existing: scores), 'p1'));
    await tester.pumpAndSettle();

    expect(
        tester.widget<Text>(find.byKey(const Key('finalGrade'))).data, '100');
  });

  testWidgets('a released evaluation is read-only', (tester) async {
    final scores = {for (final c in evaluationCriteria) c.key: c.weight};
    await tester.pumpWidget(app(
        await seed(existing: scores, releasedAt: DateTime(2026, 9, 23)),
        'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('submitEvaluation')), findsNothing);
    expect(find.byKey(const Key('releasedNotice')), findsOneWidget);
  });

  testWidgets('the adviser is told they do not score', (tester) async {
    await tester.pumpWidget(app(await seed(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adviserRefusal')), findsOneWidget);
    expect(find.byKey(const Key('submitEvaluation')), findsNothing);
  });

  // The distinction D41 depends on staying visible.
  testWidgets('the panelist rating is labelled as their own, not the panel\'s',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ratingIsYours')), findsOneWidget);
  });

  // pump() once, NOT pumpAndSettle -- settling resolves the stream and
  // the assertion becomes vacuous.
  testWidgets('shows a loading state before the defence resolves',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pump();

    expect(find.byKey(const Key('evaluationLoading')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/defence/evaluation_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../evaluation_screen.dart'`

- [ ] **Step 3: Write the implementation**

Create `lib/features/defence/evaluation_screen.dart`. It is a
`ConsumerStatefulWidget` holding `Map<String, int> _scores`, `Map<String,
TextEditingController> _comments`, and `PassFail? _rating` in local
state, seeded once from `myEvaluationProvider` when it first resolves.

Required behaviour and keys:

- Watch `defenceProvider(defenceId)` and `myEvaluationProvider(defenceId)`.
  While either `isLoading`, render `LoadingState` under
  `Key('evaluationLoading')`. On error, render the error and the Firestore
  code — never an empty form.
- If the defence is null, render the same "not found" `EmptyState` the
  room screen uses.
- If `uid == defence.adviserUid`, render only a `Key('adviserRefusal')`
  message: *"Advisers comment on a defence but do not score it. Your
  remarks are in the defence log."* and a button to `/grades`. Decided
  from the defence alone, before any evaluation stream is consulted —
  the same discipline `defence_room_screen.dart` uses for the leader.
- If `uid` is not in `defence.panelUids`, render a `Key('notPanelist')`
  message.
- Seed `_scores` from the loaded evaluation exactly once (guard with a
  `bool _seeded`), so a later snapshot does not overwrite what the
  panelist is typing.
- For each criterion in `evaluationCriteria`, grouped by
  `EvaluationSection`, render a row with:
  - `Text(c.label)` and the weight
  - a stepper: `IconButton(key: Key('minus_${c.key}'))`, `Text(key:
    Key('score_${c.key}'))`, `IconButton(key: Key('plus_${c.key}'))`.
    Clamp with `(current + delta).clamp(0, c.weight)`.
  - if `c.prompt.isNotEmpty`, the prompt as helper text
  - if `c.takesComment`, a `TextField(key: Key('comment_${c.key}'))`
- Section subtotals and `Text(key: Key('finalGrade'))` carrying
  `totalOf(_scores).toString()`.
- A Pass/Fail `SegmentedButton` under a `Key('ratingIsYours')` caption:
  *"Your own rating under §8a. The panel's verdict is decided separately,
  after deliberation."*
- `FilledButton(key: Key('submitEvaluation'))`, with `onPressed: null`
  unless `_scores.length == evaluationCriteria.length && _rating != null`.
  On press, call `submitEvaluation` and show the thrown message in a
  `SnackBar` on failure.
- If `defence.evaluationsReleased`, render every control disabled, hide
  the submit button, and show `Key('releasedNotice')`: *"These
  evaluations have been released. This sheet is now part of the record."*

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/defence/evaluation_screen_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/defence/evaluation_screen.dart test/features/defence/evaluation_screen_test.dart
git commit -m "feat: add the Form 5c evaluation screen"
```

---

### Task 10: The grades screen

**Files:**
- Create: `lib/features/defence/defence_grades_screen.dart`
- Test: `test/features/defence/defence_grades_screen_test.dart`

**Interfaces:**
- Consumes: `defenceProvider`, `defenceEvaluationsProvider`, `myEvaluationProvider`, `defenceRepositoryProvider`, `signedInUidProvider`.
- Produces: `DefenceGradesScreen({required String defenceId})`.

- [ ] **Step 1: Write the failing test**

Create `test/features/defence/defence_grades_screen_test.dart`, reusing
the `seed`/`app` helpers from Task 9's test (copy them in — the two
suites must not share a file):

```dart
void main() {
  testWidgets('before release it shows the count and no scores',
      (tester) async {
    // panel of p1, p2; only p1 has submitted.
    await tester.pumpWidget(app(await seedWithOne(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('submittedCount')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const Key('submittedCount'))).data,
        '1 of 2 panelists have submitted');
    expect(find.byKey(const Key('gradesTable')), findsNothing);
  });

  // D40's mitigation. The count is on the button, so releasing early is a
  // visible choice rather than an accident.
  testWidgets('the release button carries the count', (tester) async {
    await tester.pumpWidget(app(await seedWithOne(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('Release 1 of 2 evaluations'), findsOneWidget);
  });

  testWidgets('a panelist sees the count but no release control',
      (tester) async {
    await tester.pumpWidget(app(await seedWithOne(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('submittedCount')), findsOneWidget);
    expect(find.byKey(const Key('releaseEvaluations')), findsNothing);
  });

  testWidgets('after release the table shows every panelist\'s total',
      (tester) async {
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gradesTable')), findsOneWidget);
    expect(find.byKey(const Key('panelMean')), findsOneWidget);
  });

  testWidgets('the panel mean is the mean of the submitted totals',
      (tester) async {
    // p1 at 100, p2 at 50.
    await tester.pumpWidget(app(await seedReleased(second: 50), 'p1'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('panelMean'))).data,
        '75');
  });

  testWidgets('the adviser records the verdict after release',
      (tester) async {
    await tester.pumpWidget(app(await seedReleased(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recordVerdict')), findsOneWidget);
  });

  testWidgets('a panelist may not record the verdict', (tester) async {
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recordVerdict')), findsNothing);
  });

  // D42: the adviser is visibly the scribe.
  testWidgets('a recorded verdict names who recorded it', (tester) async {
    await tester.pumpWidget(
        app(await seedReleased(verdict: 'pass'), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('verdict')), findsOneWidget);
    expect(find.byKey(const Key('verdictScribe')), findsOneWidget);
    expect(find.byKey(const Key('recordVerdict')), findsNothing);
  });

  testWidgets('no evaluations yet says so, and does not look like a zero',
      (tester) async {
    await tester.pumpWidget(app(await seedNone(), 'a1'));
    await tester.pumpAndSettle();

    expect(
        tester.widget<Text>(find.byKey(const Key('submittedCount'))).data,
        '0 of 2 panelists have submitted');
    expect(find.byKey(const Key('panelMean')), findsNothing);
  });

  testWidgets('shows a loading state before the defence resolves',
      (tester) async {
    await tester.pumpWidget(app(await seedNone(), 'a1'));
    await tester.pump();

    expect(find.byKey(const Key('gradesLoading')), findsOneWidget);
  });
}
```

Write `seedWithOne()`, `seedReleased({int second = 100, String? verdict})`
and `seedNone()` as variations on Task 9's `seed`, each writing the
`evaluations` documents directly.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/defence/defence_grades_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../defence_grades_screen.dart'`

- [ ] **Step 3: Write the implementation**

Create `lib/features/defence/defence_grades_screen.dart`, following the
same `_framed` pattern.

Required behaviour:

- Watch `defenceProvider(defenceId)`. While loading, `LoadingState` under
  `Key('gradesLoading')`. On error, the error and its code.
- **Open `defenceEvaluationsProvider` only when
  `defence.evaluationsReleased` is true.** Before release the rules deny
  that read to everyone, so opening it early produces a
  `permission-denied` the screen would have to explain away. The count
  before release comes from a different source: watch
  `defenceEvaluationsProvider` for the adviser only if released, and
  otherwise derive the count from a dedicated lightweight read — a
  `watchEvaluations` call is denied, so instead the screen shows
  `myEvaluationProvider` for a panelist and, for the adviser, a count
  provider added in this task:

```dart
/// How many panelists have submitted, and who.
///
/// Reads the subcollection ids only. Before release the rules deny a
/// panelist any document but their own, so this stream is for the ADVISER
/// -- and it is the number they release on (D40), which is exactly why it
/// must not be silently emptied on error.
final evaluationCountProvider =
    StreamProvider.family<List<String>, String>((ref, defenceId) {
  ref.watch(signedInUidProvider);
  return ref
      .watch(defenceRepositoryProvider)
      .watchEvaluatorUids(defenceId);
});
```

  Add the matching repository method:

```dart
  /// The uids that have submitted, nothing else.
  ///
  /// Separate from [watchEvaluations] because the adviser needs the COUNT
  /// before release and is denied the CONTENTS until after it -- release
  /// is a procedural act on a number, not an editorial one.
  Stream<List<String>> watchEvaluatorUids(String defenceId) {
    return _evaluations(defenceId).snapshots().map((s) {
      final ids = s.docs.map((d) => d.id).toList()..sort();
      return ids;
    });
  }
```

  Note for the reviewer: the rules as written in Task 4 deny a `list`
  over `evaluations` before release for everyone including the adviser,
  so `watchEvaluatorUids` will be denied then too. Resolve this by adding
  one arm to the subcollection's `allow list` permitting the adviser a
  list that returns no document data is NOT possible in Firestore — a
  list returns documents. **So: the count before release is shown from
  the adviser's perspective only after adding `parent().adviserUid ==
  request.auth.uid` to the read rule's first arm.** That widens the
  adviser's pre-release access from "nothing" to "everything", which
  contradicts D39's note that the adviser releases without seeing
  contents. Flag this to the user before implementing; the two honest
  options are (a) let the adviser read pre-release and drop that note, or
  (b) keep the seal absolute and have the release button say only
  *"Release evaluations"* with no count, losing D40's mitigation. **Do
  not choose silently.**
- After release: a `DataTable(key: Key('gradesTable'))` with one row per
  evaluation — the eleven scores, the total, the rating — plus
  `Text(key: Key('panelMean'))` carrying the integer mean of the totals,
  and the per-criterion comments grouped by criterion.
- The verdict block: for the adviser with no verdict recorded, a
  Pass/Fail control and `FilledButton(key: Key('recordVerdict'))` under a
  caption saying this records the panel's deliberated decision under §8b.
  Once recorded, `Key('verdict')` and `Key('verdictScribe')` for everyone.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/defence/defence_grades_screen_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/defence/defence_grades_screen.dart lib/data/repositories/defence_repository.dart lib/providers/defence_providers.dart test/features/defence/defence_grades_screen_test.dart
git commit -m "feat: add the grades screen, release and verdict"
```

---

### Task 11: Routes and entry points

Two screens nothing navigates to is how M2 shipped a leader upload flow
nobody could reach. This task is what stops that recurring.

**Files:**
- Modify: `lib/core/routing/app_router.dart`
- Modify: `lib/features/defence/defence_room_screen.dart`
- Modify: `lib/features/defence/defences_list.dart`
- Test: `test/features/defence/defence_room_screen_test.dart` (append)

**Interfaces:**
- Consumes: `EvaluationScreen`, `DefenceGradesScreen`.
- Produces: routes `/defence/room/:defenceId/evaluate` and `/defence/room/:defenceId/grades`.

- [ ] **Step 1: Write the failing test**

Append to `test/features/defence/defence_room_screen_test.dart`:

```dart
  testWidgets('a panelist on a closed defence is offered the sheet',
      (tester) async {
    await tester.pumpWidget(app(await seed(status: 'completed'), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToEvaluate')), findsOneWidget);
  });

  testWidgets('nobody is offered the sheet before the defence closes',
      (tester) async {
    await tester.pumpWidget(app(await seed(status: 'scheduled'), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToEvaluate')), findsNothing);
  });

  testWidgets('the adviser is offered the grades, not the sheet',
      (tester) async {
    await tester.pumpWidget(app(await seed(status: 'completed'), 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToGrades')), findsOneWidget);
    expect(find.byKey(const Key('goToEvaluate')), findsNothing);
  });

  // D47. The verdict is the outcome the group must know, and it lives on
  // the defence document they can already read -- so it reaches them
  // without any evaluation ever being readable to them.
  testWidgets('the leader is shown their verdict once it is recorded',
      (tester) async {
    await tester.pumpWidget(app(
        await seed(status: 'completed', verdict: 'pass'), 'l1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('leaderVerdict')), findsOneWidget);
  });

  testWidgets('the leader is shown no grade and no route to one',
      (tester) async {
    await tester.pumpWidget(app(
        await seed(status: 'completed', verdict: 'pass'), 'l1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToGrades')), findsNothing);
    expect(find.byKey(const Key('goToEvaluate')), findsNothing);
  });

  testWidgets('before a verdict the leader is told it is pending',
      (tester) async {
    await tester.pumpWidget(app(await seed(status: 'completed'), 'l1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('leaderVerdictPending')), findsOneWidget);
  });
```

Extend the test file's `seed` helper with a `String? verdict` parameter
that writes `panelVerdict`, `verdictRecordedBy: 'a1'` and
`verdictRecordedAt` onto the defence when given.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/defence/defence_room_screen_test.dart`
Expected: FAIL — `goToEvaluate` not found.

- [ ] **Step 3: Write the implementation**

In `app_router.dart`, after the `/defence/room/:defenceId/consolidated`
route:

```dart
      // Both are three segments, so ':defenceId' at position 2 can never
      // swallow them -- the same reasoning as 'consolidated' above.
      GoRoute(
        path: '/defence/room/:defenceId/evaluate',
        builder: (context, state) => EvaluationScreen(
            defenceId: state.pathParameters['defenceId']!),
      ),
      GoRoute(
        path: '/defence/room/:defenceId/grades',
        builder: (context, state) => DefenceGradesScreen(
            defenceId: state.pathParameters['defenceId']!),
      ),
```

Both fall under the existing `'/defence/room/'` prefix that
`app_shell_host.dart:57` and the `isDefenceRoomRoute` check at
`app_router.dart:265` already handle, so the shell, the sidebar and the
back control need no change. Verify that by reading both call sites
before assuming it.

In `defence_room_screen.dart`, on a `completed` defence, add an
Evaluation card above the comment log:

- for a uid in `defence.panelUids`: `FilledButton(key:
  Key('goToEvaluate'))` reading *"Evaluate"*, or *"Your evaluation —
  N/100"* when `myEvaluationProvider` has resolved to a sheet; pushes
  `/defence/room/$id/evaluate`.
- for `defence.adviserUid`: `OutlinedButton(key: Key('goToGrades'))`
  reading *"Grades"*; pushes `/defence/room/$id/grades`.
- both also offer `/grades` once `defence.evaluationsReleased`.

Use `context.push`, not `context.go` — these are deep screens under the
Defences destination, and `go` would replace the destination rather than
stack on it. In `defences_list.dart`, add the same affordance to a
completed row.

**And the group's half of D47.** The room screen already branches on
`isLeader` before consulting any comment stream. Extend that branch on a
`completed` defence, from the defence document alone:

```dart
      if (defence.hasVerdict)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Panel verdict: ${defence.panelVerdict!.label}',
            key: const Key('leaderVerdict'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        )
      else if (defence.status == DefenceStatus.completed)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'The panel has not recorded a verdict for this defence yet.',
            key: Key('leaderVerdictPending'),
          ),
        ),
```

Nothing here reads an evaluation, and nothing must: the group's route to
the numbers is §11b's paper grading sheet through the subject professor,
and no arm of the rules grants them one. Do not add a link to `/grades`
in this branch — the screen would load and then deny.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/defence/`
Expected: PASS — the whole defence suite.

- [ ] **Step 5: Commit**

```bash
git add lib/core/routing/app_router.dart lib/features/defence/ test/features/defence/
git commit -m "feat: route to the evaluation and grades screens"
```

---

### Task 12: The needs-you queue row

**Files:**
- Modify: `lib/providers/needs_you_providers.dart` — `facultyNeedsYouProvider`
- Test: `test/providers/needs_you_providers_test.dart` (append)

**Interfaces:**
- Consumes: `myEvaluationProvider` is NOT usable here (it is per-defence); this task adds a fan-in over the defences the faculty member sits on.

- [ ] **Step 1: Write the failing test**

Append to `test/providers/needs_you_providers_test.dart`. Follow the
file's existing container-and-seed helpers; the shape below assumes its
`facultyContainer(db, uid)` helper and a `defences` seed:

```dart
  test('a panelist owes a sheet on a closed, unreleased defence',
      () async {
    final db = await seedFacultyWorld();
    await db.collection('defenses').doc('d9').set({
      'thesisId': 't1', 'type': 'final',
      'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
      'venue': 'AVR', 'panelUids': <String>['fac-uid'],
      'adviserUid': 'a1', 'leaderUid': 'l1', 'status': 'completed',
      'createdBy': 'c1',
    });
    final c = facultyContainer(db, 'fac-uid');
    addTearDown(c.dispose);

    final items = await c.read(facultyNeedsYouProvider.future);
    final row = items.where((i) => i.chipLabel == 'Evaluate');

    expect(row, hasLength(1));
    expect(row.single.route, '/defence/room/d9/evaluate');
    expect(row.single.title, 'Final defence');
  });

  test('the row goes once that panelist has submitted', () async {
    final db = await seedFacultyWorld();
    await db.collection('defenses').doc('d9').set({
      'thesisId': 't1', 'type': 'final',
      'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
      'venue': 'AVR', 'panelUids': <String>['fac-uid'],
      'adviserUid': 'a1', 'leaderUid': 'l1', 'status': 'completed',
      'createdBy': 'c1',
    });
    await db
        .collection('defenses').doc('d9')
        .collection('evaluations').doc('fac-uid')
        .set({
      'scores': {for (final cr in evaluationCriteria) cr.key: cr.weight},
      'comments': const <String, String>{},
      'total': 100, 'rating': 'pass',
    });
    final c = facultyContainer(db, 'fac-uid');
    addTearDown(c.dispose);

    final items = await c.read(facultyNeedsYouProvider.future);
    expect(items.where((i) => i.chipLabel == 'Evaluate'), isEmpty);
  });

  test('a released defence owes nothing, submitted or not', () async {
    final db = await seedFacultyWorld();
    await db.collection('defenses').doc('d9').set({
      'thesisId': 't1', 'type': 'final',
      'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
      'venue': 'AVR', 'panelUids': <String>['fac-uid'],
      'adviserUid': 'a1', 'leaderUid': 'l1', 'status': 'completed',
      'createdBy': 'c1',
      'evaluationsReleasedAt':
          Timestamp.fromDate(DateTime(2026, 9, 24)),
    });
    final c = facultyContainer(db, 'fac-uid');
    addTearDown(c.dispose);

    final items = await c.read(facultyNeedsYouProvider.future);
    expect(items.where((i) => i.chipLabel == 'Evaluate'), isEmpty);
  });

  // The adviser is barred from scoring, so they can never owe a sheet --
  // and this is the queue that would otherwise nag them forever.
  test('the adviser is never asked to evaluate', () async {
    final db = await seedFacultyWorld();
    await db.collection('defenses').doc('d9').set({
      'thesisId': 't1', 'type': 'final',
      'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
      'venue': 'AVR', 'panelUids': <String>['p1'],
      'adviserUid': 'fac-uid', 'leaderUid': 'l1', 'status': 'completed',
      'createdBy': 'c1',
    });
    final c = facultyContainer(db, 'fac-uid');
    addTearDown(c.dispose);

    final items = await c.read(facultyNeedsYouProvider.future);
    expect(items.where((i) => i.chipLabel == 'Evaluate'), isEmpty);
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/providers/needs_you_providers_test.dart`
Expected: FAIL — no such row.

- [ ] **Step 3: Write the implementation**

In `facultyNeedsYouProvider`, inside the existing
`for (final d in defences!.requireValue)` loop, add:

```dart
      // A panelist owes a sheet on every defence they sat that has
      // closed and not yet been released.
      if (d.panelUids.contains(uid) &&
          d.status == DefenceStatus.completed &&
          !d.evaluationsReleased &&
          !submittedOn.contains(d.id)) {
        items.add(NeedsYouItem(
          title: d.type.label,
          detail: 'Score this defence against Form 5c.',
          route: '/defence/room/${d.id}/evaluate',
          chipLabel: 'Evaluate',
          tone: NeedsYouTone.act,
          deep: isDeepForRole(
              UserRole.faculty, '/defence/room/${d.id}/evaluate'),
        ));
      }
```

`submittedOn` is a `Set<String>` maintained by a per-defence subscription
fan-in, opened and closed exactly as `syncChapterSubs` does for chapters
— read that function and mirror it. **Do not** collapse it into an `await
for` with `.first` on the other stream: that shape only advances when the
first stream emits, and this project has shipped that exact bug once
already. Extend the existing `emit()` gate so it waits for every open
evaluation subscription to have reported once, the same way it already
waits on `chaptersByThesis`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/providers/needs_you_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the whole suite and commit**

```bash
flutter analyze
flutter test
git add lib/providers/needs_you_providers.dart test/providers/needs_you_providers_test.dart
git commit -m "feat: surface an owed evaluation in the faculty queue"
```

---

## Notes carried out of planning

Three things surfaced while writing this plan that are not tasks:

1. **Task 10 contains a genuine design conflict** — the adviser cannot
   both be denied pre-release reads and be shown a submitted count, because
   a Firestore `list` returns documents. It is flagged inline with two
   honest options. Resolve it with the user before Task 10 begins.

2. **`facultyNeedsYouProvider` routes existing defence rows to
   `/defence/${d.id}`**, which the router maps to `TitleDefenceScreen`
   (`/defence/:thesisId`), not the defence room — `d.id` is a defence id
   being passed where a thesis id is expected. This predates M4 and may be
   a live bug. Not fixed here; verify and raise separately.

3. **Dark mode has never had a full pass** since the toggle shipped. Both
   new screens should be checked in dark before the branch merges.
