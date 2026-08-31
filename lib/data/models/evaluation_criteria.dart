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
