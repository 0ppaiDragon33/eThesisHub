/// A frozen copy of every template's block ids, in page order, as they were
/// when this snapshot was last updated.
///
/// A saved copy stores overrides keyed by block id (see
/// `FormTemplate.overridesFrom`). If a block is later renamed, a copy saved
/// under the old id silently stops finding its text and falls back to the
/// template's default wording — the user's edit is orphaned, with no error
/// to signal it. Adding or removing a block is fine; renaming or reordering
/// an existing id is not something to do casually.
///
/// This snapshot exists to catch that class of accidental rename. Update it
/// only deliberately, alongside a migration that rewrites existing users'
/// saved copies from the old id to the new one.
const Map<String, List<String>> templateIdsSnapshot = {
  'form1': [
    'rdCode', 'formTitle', 'date', 'dateLabel', 'addressee', 'addressCollege',
    'addressUniversity', 'addressCity', 'salutation', 'adviserParagraph',
    'panelParagraph', 'closing', 'valediction', 'researcher.1',
    'researcher.1.role', 'researcher.2', 'researcher.2.role', 'researcher.3',
    'researcher.3.role', 'researcher.4', 'researcher.4.role', 'researcher.5',
    'researcher.5.role', 'conformeHeading', 'conforme.adviser',
    'conforme.adviser.role', 'conforme.panel.1', 'conforme.panel.1.role',
    'conforme.panel.2', 'conforme.panel.2.role', 'conforme.panel.3',
    'conforme.panel.3.role', 'recommendingHeading', 'coordinator',
    'coordinator.role', 'approvedHeading', 'dean', 'dean.role', 'coreValues',
  ],
  'form3': [
    'rdCode', 'formTitle', 'date', 'dateLabel', 'addressee', 'addressCollege',
    'addressUniversity', 'addressCity', 'salutation', 'request', 'panel.1',
    'panel.2', 'panel.3', 'convene', 'presenters', 'entitled', 'title',
    'onWord', 'scheduledDate', 'inWord', 'venue', 'atWord', 'time',
    'placeTimeLabel', 'closing', 'valediction', 'adviser', 'adviser.role',
    'recommendingHeading', 'coordinator', 'coordinator.role',
    'approvedHeading', 'dean', 'dean.role',
  ],
  'form4a': [
    'rdCode', 'formTitle', 'date', 'dateLabel', 'addressee', 'addressCollege',
    'addressUniversity', 'addressCity', 'salutation', 'request',
    'nominatedAdviser', 'toWord', 'nominatedLabel', 'formerAdviser',
    'formerLabel', 'reasonsLead', 'reason.1', 'reason.2', 'reason.3',
    'closing', 'valediction', 'student', 'student.role', 'conformeHeading',
    'nominated', 'nominated.role', 'former', 'former.role',
    'recommendingHeading', 'coordinator', 'coordinator.role',
    'approvedHeading', 'dean', 'dean.role',
  ],
  'form4b': [
    'rdCode', 'formTitle', 'date', 'dateLabel', 'addressee', 'addressCollege',
    'addressUniversity', 'addressCity', 'salutation', 'request', 'oldTitle',
    'toWord', 'newTitle', 'reasonsLead', 'reason.1', 'reason.2', 'reason.3',
    'closing', 'valediction', 'student', 'student.role', 'notedHeading',
    'adviser', 'adviser.role', 'recommendingHeading', 'coordinator',
    'coordinator.role', 'approvedHeading', 'dean', 'dean.role',
  ],
  'form5a': [
    'rdCode', 'formTitle', 'date', 'dateLabel', 'addressee', 'addressCollege',
    'addressUniversity', 'addressCity', 'salutation', 'request', 'title',
    'scheduleLead', 'scheduledDate', 'inWord', 'venue', 'atWord', 'time',
    'placeTimeLabel', 'closing', 'valediction', 'student', 'student.role',
    'notedHeading', 'adviser', 'adviser.role', 'recommendingHeading',
    'coordinator', 'coordinator.role', 'approvedHeading', 'dean',
    'dean.role',
  ],
  'form5b': [
    'rdCode', 'formTitle', 'presenter.label', 'presenter', 'degree.label',
    'degree', 'presentedDate.label', 'presentedDate', 'presentedTime.label',
    'presentedTime', 'venue.label', 'venue', 'studyTitle.label',
    'studyTitle', 'evaluator.label', 'evaluator', 'rank.label', 'rank',
    'specialization.label', 'specialization',
  ],
  'form5c': [
    'rdCode', 'formTitle', 'guideHeading', 'guideSubheading',
    'presenter.label', 'presenter', 'degree.label', 'degree',
    'presentedDate.label', 'presentedDate', 'presentedTime.label',
    'presentedTime', 'venue.label', 'venue', 'studyTitle.label',
    'studyTitle', 'defence.label', 'defence', 'evaluator.label', 'evaluator',
    'rank.label', 'rank', 'specialization.label', 'specialization',
    'sectionA', 'criterion.title.label', 'criterion.title.prompt',
    'criterion.title.score', 'criterion.title.comment',
    'criterion.introduction.label', 'criterion.introduction.prompt',
    'criterion.introduction.score', 'criterion.introduction.comment',
    'criterion.materialsAndMethods.label',
    'criterion.materialsAndMethods.prompt',
    'criterion.materialsAndMethods.score',
    'criterion.materialsAndMethods.comment', 'criterion.result.label',
    'criterion.result.prompt', 'criterion.result.score',
    'criterion.result.comment', 'criterion.discussion.label',
    'criterion.discussion.prompt', 'criterion.discussion.score',
    'criterion.discussion.comment', 'criterion.conclusion.label',
    'criterion.conclusion.prompt', 'criterion.conclusion.score',
    'criterion.conclusion.comment', 'criterion.recommendation.label',
    'criterion.recommendation.prompt', 'criterion.recommendation.score',
    'criterion.recommendation.comment', 'criterion.references.label',
    'criterion.references.prompt', 'criterion.references.score',
    'criterion.references.comment', 'sectionB', 'criterion.preciseness.label',
    'criterion.preciseness.score', 'criterion.alertness.label',
    'criterion.alertness.score', 'criterion.personality.label',
    'criterion.personality.score', 'summaryHeading', 'summaryA.label',
    'summaryA', 'summaryB.label', 'summaryB', 'average.label', 'average',
    'finalGrade.label', 'finalGrade', 'rating.label', 'rating',
  ],
  'form7': [
    'rdCode', 'formTitle', 'date', 'dateLabel', 'heading', 'certify',
    'presenters', 'presentersLabel', 'entitled', 'title', 'table.member',
    'table.approved', 'table.remarks', 'panel.1.name', 'panel.1.role',
    'panel.1.approved', 'panel.1.remarks', 'panel.2.name', 'panel.2.role',
    'panel.2.approved', 'panel.2.remarks', 'panel.3.name', 'panel.3.role',
    'panel.3.approved', 'panel.3.remarks', 'panel.4.name', 'panel.4.role',
    'panel.4.approved', 'panel.4.remarks', 'panel.5.name', 'panel.5.role',
    'panel.5.approved', 'panel.5.remarks', 'panel.6.name', 'panel.6.role',
    'panel.6.approved', 'panel.6.remarks', 'panel.7.name', 'panel.7.role',
    'panel.7.approved', 'panel.7.remarks',
  ],
  'form8': [
    'rdCode', 'formTitle', 'date', 'dateLabel', 'heading', 'certifyLead',
    'students', 'certifyMiddle', 'thesisTitle', 'signer.role',
  ],
};
