# Editable Forms — Phase 3 (the other eight forms) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Forms 3, 4a, 4b, 5a, 5b, 5c, 7 and 8 can each be started as a named copy from their Forms-screen card and edited in the app, exactly as Form 1 already can. The official blank and filled PDFs of every form stay textually identical.

**Architecture:** Each form's `formN_pdf.dart` gains a `formNTemplate` (labelled text blocks, the form's own wording as defaults). Its page builder takes a `FormText` and reads every fixed string through it. Where the official *filled* form prints app data (names, dates, a title), the data still wins. Otherwise the block's typed text prints, or a ruled line if the block is still blank. The blank and filled builders pass an unedited `FormText`, so their output is unchanged. An editable copy passes the person's overrides with no data. Shared letter parts (heading, address, approval chain) and small helpers (`dataOr`, `valueOr`) keep the eight conversions from repeating one another.

**Tech Stack:** Flutter 3.44, the `pdf` package, Riverpod 2.6.1 (pinned), `test/features/forms/pdf_text.dart` (`extractPdfText`) for PDF text assertions.

**Spec:** `docs/superpowers/specs/2026-09-24-editable-forms-and-my-files-design.md`. This plan covers §11 step 3 (spec §4, §5.3, §12).

## Global Constraints

- **Commit only the files your task names.** The working tree has unrelated uncommitted changes: `android/app/src/main/kotlin/com/example/ethesishub/MainActivity.kt`, `lib/app.dart`, `lib/core/widgets/app_shell.dart`, `lib/core/theme/app_theme.dart`, `lib/features/dashboard/progress_rail.dart`, `lib/features/defence/consolidated_defence_screen.dart`, `lib/core/platform/native_back.dart`, `test/core/platform/`, the deleted `double_back_to_exit` files, `macos/…`, `android/build/`. Never `git add -A`, `git add .`, or `git commit -a`. Stage by explicit path; check `git status --short` before every commit.
- **The official PDFs do not change.** Every existing `test/features/forms/formN_pdf_test.dart` and `formN_data_test.dart` must pass **unchanged**. That is the proof the rewrite kept the blank and filled output identical. Do not edit those tests.
- **A new copy starts as the official blank.** For every converted form, the text of `buildFormPdf(formNTemplate, {})` must equal the text of the official `buildFormNBlank()`, as read by `extractPdfText`. `all_templates_test.dart` asserts this.
- **Letterhead fixed, everything below editable** (spec E10): the form code (`rdCode`) and title (`formTitle`) are blocks; the fixed institutional letterhead lines inside `formChrome` are not.
- **Criterion weights stay fixed** on Form 5c (the `(25%)` after each criterion and the `/ 25` after each score). They define the scoring the app computes. Criterion names, prompts, scores and comments are editable.
- Every block id is unique within its form and never changes once shipped (saved copies refer to it).
- No new dependencies. Every PDF still uses `pw.Document(compress: false, theme: await formTheme())`.
- User-facing wording in this plan is final copy. Use it verbatim.
- Every commit message ends with the trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Test command: `flutter test <path>` from the repo root.

## Rulings made while planning (the spec is amended in Task 0)

- **Q1: App data stays structural.** The spec (§4.3) said a filled builder turns its data into overrides. Instead, `_page` keeps its data parameter and prints the data where the official form does, falling back to the block when there is no data. This keeps variable-length parts (a panel list of any length, a sentence joining names) exactly as they are and leaves the official output untouched. An editable copy simply has no data.
- **Q2: When edited, a blank's typed text wraps inside the width of the ruled line it replaces** (`blankOr` wraps it in a `SizedBox` of that width). Otherwise a long entry in a row (Form 4a's adviser line) would overflow the page. The official forms never reach this path, because an unedited blank still prints its ruled line.
- **Q3: Signature names are editable text blocks that default to empty**, matching the official forms, which print an empty name above each role. They are not `blank` blocks, because the official forms draw no line there.
- **Q4: Letter-shaped forms (3, 4a, 4b, 5a) share one set of opening and approval blocks and layout** (`form_parts.dart`). Their heading, address, greeting and Recommending/Approved chain are identical on paper today.

## File structure

| File | Responsibility |
|---|---|
| `lib/features/forms/editable/form_pdf.dart` (modify) | `blankOr` gains `height` and wraps typed text to its width; new `dataOr`, `valueOr` |
| `lib/features/forms/editable/form_parts.dart` (new) | shared blocks and layout: form head, letter opening, letter approval chain, labelled-field block pairs |
| `lib/features/forms/formN_pdf.dart` ×8 (modify) | each gains `formNTemplate`; its `_page` reads every string through `FormText` |
| `lib/features/forms/editable/form_templates.dart` (modify) | registers each template |
| `lib/features/forms/forms_screen.dart` (modify) | New copy / My copies on each card |
| `test/features/forms/editable/all_templates_test.dart` (new) | per-template checks, including "a new copy prints exactly like the official blank" |

---

### Task 0: Record the planning rulings in the spec

**Files:**
- Modify: `docs/superpowers/specs/2026-09-24-editable-forms-and-my-files-design.md`
- Create: `docs/superpowers/plans/2026-09-25-editable-forms-phase3.md` (this file, already written)

- [ ] **Step 1:** At the end of §4.3 (after the paragraph that starts `**Form 1 is the exception.**`), append:

```markdown
**Phase 3 note (forms 3, 4a, 4b, 5a, 5b, 5c, 7, 8).** A filled builder does not
turn its app data into overrides. `_page` keeps its data parameter and prints
the data where the official form does, falling back to the block (its typed
text, or a ruled line while blank) when there is no data. Variable-length parts
(a panel list, names joined into a sentence) therefore stay exactly as they are.
An editable copy is simply the page with no data. On Form 5c the criterion
weights stay fixed, because they define the scoring; the criterion names,
prompts, scores and comments are editable.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-09-24-editable-forms-and-my-files-design.md docs/superpowers/plans/2026-09-25-editable-forms-phase3.md
git status --short   # only those two staged
git commit -m "docs(plan): editable forms phase 3, and the rulings it made

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: Shared parts, helpers and the all-templates test

**Files:**
- Modify: `lib/features/forms/editable/form_pdf.dart`
- Create: `lib/features/forms/editable/form_parts.dart`
- Test: `test/features/forms/editable/form_pdf_test.dart` (add tests)
- Test: `test/features/forms/editable/all_templates_test.dart` (new)

**Interfaces:**
- Consumes (Phase 1): `FormBlock`, `BlockKind`, `FormTemplate`, `FormText` (`form_template.dart`); `buildFormPdf`, `blankOr` (`form_pdf.dart`); `formTemplates` (`form_templates.dart`); `formChrome`, `signableLine`, `ruledLine` (`form_chrome.dart`).
- Produces:
  - `pw.Widget blankOr(FormText text, String id, {double width = 160, double height = 12, pw.TextStyle? style})`: a ruled line of `width`×`height` while blank, otherwise the typed text wrapped to `width`.
  - `pw.Widget dataOr(String? value, FormText text, String id, {double width = 160, double height = 12, pw.TextStyle? style})`: `pw.Text(value)` when `value != null`, else `blankOr(...)`.
  - `String? valueOr(String? value, FormText text, String id)`: `value` when non-null, else the block's text, else null while it is blank.
  - In `form_parts.dart`:
    - `List<FormBlock> formHeadBlocks({required String rdCode, required String formTitle})`: blocks `rdCode`, `formTitle`
    - `List<FormBlock> letterOpeningBlocks({required String rdCode, required String formTitle})`: head + `date` (blank), `dateLabel`, `addressee`, `addressCollege`, `addressUniversity`, `addressCity`, `salutation`
    - `const List<FormBlock> letterApprovalBlocks`: `recommendingHeading`, `coordinator`, `coordinator.role`, `approvedHeading`, `dean`, `dean.role`
    - `List<FormBlock> fieldBlocks(String id, String label)`: `'$id.label'` (text) + `id` (blank)
    - `List<pw.Widget> letterOpening(FormText t, {String college = ''})`
    - `List<pw.Widget> letterApproval(FormText t, {String college = ''})`

- [ ] **Step 1: Write the failing helper tests.** Append inside `main()` of `test/features/forms/editable/form_pdf_test.dart`:

```dart
  group('dataOr and valueOr', () {
    final helperTpl = FormTemplate(
      formId: 'helper',
      title: 'Helper',
      blocks: const [
        FormBlock(id: 'venue', label: 'Venue', kind: BlockKind.blank),
        FormBlock(id: 'lead', label: 'Lead', defaultText: 'Lead text'),
      ],
      layout: (t) => [
        pw.Text(t.of('lead')),
        dataOr(null, t, 'venue'),
      ],
    );

    test('valueOr prefers app data, then typed text, then nothing', () {
      expect(valueOr('AVR', FormText(helperTpl), 'venue'), 'AVR');
      expect(valueOr('', FormText(helperTpl), 'venue'), '',
          reason: 'an empty value from the app is still the app\'s value');
      expect(valueOr(null, FormText(helperTpl, {'venue': 'Room 2'}), 'venue'),
          'Room 2');
      expect(valueOr(null, FormText(helperTpl), 'venue'), isNull);
    });

    test('dataOr prints app data over anything typed', () async {
      final tpl = FormTemplate(
        formId: 'helper2',
        title: 'Helper',
        blocks: helperTpl.blocks,
        layout: (t) => [dataOr('From the app', t, 'venue')],
      );
      final text = extractPdfText(
          await buildFormPdf(tpl, const {'venue': 'Typed venue'}));
      expect(text, contains('From the app'));
      expect(text, isNot(contains('Typed venue')));
    });

    test('dataOr without app data prints the typed text', () async {
      final text = extractPdfText(
          await buildFormPdf(helperTpl, const {'venue': 'Typed venue'}));
      expect(text, contains('Typed venue'));
    });
  });
```

- [ ] **Step 2: Write the all-templates test** at `test/features/forms/editable/all_templates_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/editable/form_templates.dart';

import '../pdf_text.dart';

/// Each converted form's official blank. A new copy of the form must start
/// out printing exactly like it. Each conversion task adds its form here.
final Map<String, Future<Uint8List> Function()> officialBlanks = {};

void main() {
  // The forms embed Source Serif 4 via rootBundle, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final template in formTemplates.values) {
    group(template.formId, () {
      test('every block id is unique', () {
        final ids = template.blocks.map((b) => b.id).toList();
        expect(ids.toSet().length, ids.length);
      });

      // A block the layout never reads is a field the editor offers that
      // changes nothing on the page.
      test('every block reaches the page', () {
        final text = FormText(template);
        template.layout(text);
        expect(text.read, template.blocks.map((b) => b.id).toSet());
      });

      test('the form title can be edited', () async {
        final text = extractPdfText(await buildFormPdf(
            template, const {'formTitle': 'EDITED TITLE 42'}));
        expect(text, contains('EDITED TITLE 42'));
      });

      final blank = officialBlanks[template.formId];
      if (blank != null) {
        test('a new copy prints exactly like the official blank', () async {
          expect(
            extractPdfText(await buildFormPdf(template, const {})),
            extractPdfText(await blank()),
          );
        });
      }
    });
  }
}
```

- [ ] **Step 3: Run both and watch the helper tests fail**

Run: `flutter test test/features/forms/editable/form_pdf_test.dart test/features/forms/editable/all_templates_test.dart`
Expected: `form_pdf_test.dart` FAILS to compile (`dataOr` / `valueOr` undefined). `all_templates_test.dart` PASSES, because only Form 1 is registered and it has no official blank.

- [ ] **Step 4: Implement the helpers.** In `lib/features/forms/editable/form_pdf.dart`, replace the existing `blankOr` function with:

```dart
/// A block's text, or a ruled line of [width] × [height] while it is an
/// empty blank.
///
/// Typed text wraps within [width], the width of the line it replaces, so a
/// long entry in a row cannot push the row off the page.
pw.Widget blankOr(
  FormText text,
  String id, {
  double width = 160,
  double height = 12,
  pw.TextStyle? style,
}) {
  if (text.isBlank(id)) return ruledLine(width: width, height: height);
  return pw.SizedBox(width: width, child: pw.Text(text.of(id), style: style));
}

/// A value the app supplied, printed exactly as the official filled form
/// prints it. Without one, the block: its typed text, or a ruled line
/// while blank.
pw.Widget dataOr(
  String? value,
  FormText text,
  String id, {
  double width = 160,
  double height = 12,
  pw.TextStyle? style,
}) {
  if (value != null) return pw.Text(value, style: style);
  return blankOr(text, id, width: width, height: height, style: style);
}

/// For a labelled field or a summary row: the app's value when it supplied
/// one (even an empty one, which the field rules as a blank), otherwise the
/// block's typed text, otherwise null so the field rules a blank.
String? valueOr(String? value, FormText text, String id) =>
    value ?? (text.isBlank(id) ? null : text.of(id));
```

- [ ] **Step 5: Write the shared parts** at `lib/features/forms/editable/form_parts.dart`:

```dart
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

// Blocks and layout shared by the converted forms. The letter-shaped forms
// (3, 4a, 4b, 5a) open with the same heading, address and greeting and close
// with the same Recommending/Approved chain, so those live here once.

const _body = pw.TextStyle(fontSize: 11);

/// The editable part of every form's heading: its code and its title. The
/// institutional letterhead above them stays fixed (spec E10).
List<FormBlock> formHeadBlocks({
  required String rdCode,
  required String formTitle,
}) =>
    [
      FormBlock(id: 'rdCode', label: 'Form code', defaultText: rdCode),
      FormBlock(id: 'formTitle', label: 'Form title', defaultText: formTitle),
    ];

/// Heading, date, address and greeting of a letter-shaped form.
List<FormBlock> letterOpeningBlocks({
  required String rdCode,
  required String formTitle,
}) =>
    [
      ...formHeadBlocks(rdCode: rdCode, formTitle: formTitle),
      const FormBlock(id: 'date', label: 'Date', kind: BlockKind.blank),
      const FormBlock(
          id: 'dateLabel', label: 'Label under the date', defaultText: 'Date'),
      const FormBlock(
          id: 'addressee', label: 'Addressed to', defaultText: 'The Dean'),
      FormBlock(
        id: 'addressCollege',
        label: 'Address: college',
        defaultText: 'College of ${'_' * 20}',
      ),
      const FormBlock(
        id: 'addressUniversity',
        label: 'Address: university',
        defaultText:
            'Iloilo State University of Fisheries Science and Technology',
      ),
      const FormBlock(
        id: 'addressCity',
        label: 'Address: town',
        defaultText: 'Barotac Nuevo, Iloilo',
      ),
      const FormBlock(
          id: 'salutation', label: 'Greeting', defaultText: 'Sir/Madam:'),
    ];

/// The Recommending Approval / Approved chain a letter-shaped form ends on.
/// Signature names default to empty, as the printed forms leave them.
const List<FormBlock> letterApprovalBlocks = [
  FormBlock(
    id: 'recommendingHeading',
    label: 'Recommending heading',
    defaultText: 'Recommending Approval:',
  ),
  FormBlock(id: 'coordinator', label: 'Research Coordinator: name'),
  FormBlock(
    id: 'coordinator.role',
    label: 'Research Coordinator: title',
    defaultText: 'College Research Coordinator',
  ),
  FormBlock(
      id: 'approvedHeading', label: 'Approval heading', defaultText: 'Approved:'),
  FormBlock(id: 'dean', label: 'Dean: name'),
  FormBlock(id: 'dean.role', label: 'Dean: title', defaultText: 'Dean, ________'),
];

/// A labelled field's two blocks: its label, and its value (a blank).
List<FormBlock> fieldBlocks(String id, String label) => [
      FormBlock(id: '$id.label', label: '$label (label)', defaultText: label),
      FormBlock(id: id, label: label, kind: BlockKind.blank),
    ];

/// The top of a letter-shaped form, down to the greeting. [college], when
/// the app knows it, fills the college line as the filled form always has.
List<pw.Widget> letterOpening(FormText t, {String college = ''}) => [
      formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: blankOr(t, 'date', width: 140, style: _body),
      ),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t.of('dateLabel'), style: const pw.TextStyle(fontSize: 8)),
      ),
      pw.SizedBox(height: 16),
      pw.Text(t.of('addressee'), style: _body),
      pw.Text(
        college.isEmpty ? t.of('addressCollege') : 'College of $college',
        style: _body,
      ),
      pw.Text(t.of('addressUniversity'), style: _body),
      pw.Text(t.of('addressCity'), style: _body),
      pw.SizedBox(height: 12),
      pw.Text(t.of('salutation'), style: _body),
      pw.SizedBox(height: 10),
    ];

/// The Recommending Approval / Approved chain at the foot of a letter-shaped
/// form. [college], when the app knows it, names the Dean's college.
List<pw.Widget> letterApproval(FormText t, {String college = ''}) => [
      pw.Text(
        t.of('recommendingHeading'),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
      signableLine(t.of('coordinator'), t.of('coordinator.role')),
      pw.Text(
        t.of('approvedHeading'),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
      signableLine(
        t.of('dean'),
        college.isEmpty ? t.of('dean.role') : 'Dean, $college',
      ),
    ];
```

- [ ] **Step 6: Run and watch them pass, and confirm Phase 1 is unaffected**

Run: `flutter test test/features/forms/`
Expected: all PASS, including `form1_template_test.dart` and `form_copy_editor_screen_test.dart`. Only the typed-text path of `blankOr` changed (it now wraps to the line's width); the Phase 1 tests read text, not layout.

- [ ] **Step 7: Commit**

```bash
git add lib/features/forms/editable/form_pdf.dart lib/features/forms/editable/form_parts.dart test/features/forms/editable/form_pdf_test.dart test/features/forms/editable/all_templates_test.dart
git status --short
git commit -m "feat(forms): shared parts for converting the remaining forms

blankOr takes a height and wraps typed text to its line's width; dataOr
and valueOr let a page prefer app data, then typed text, then a ruled
line. The letter forms' shared heading, address and approval chain, and
a test every registered template must pass.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Form 3 — Request to Convene the Panel for Pre-Oral Defense

**Files:**
- Modify: `lib/features/forms/form3_pdf.dart` (replace the whole file)
- Modify: `lib/features/forms/editable/form_templates.dart`
- Modify: `lib/features/forms/forms_screen.dart` (`_Form3Card`)
- Modify: `test/features/forms/editable/all_templates_test.dart` (register the official blank)

**Interfaces:**
- Consumes: Task 1 (`blankOr`, `dataOr`, `letterOpeningBlocks`, `letterApprovalBlocks`, `letterOpening`, `letterApproval`); `Form3Data`; `formTheme`, `monthName`, `panelSentence`, `signableLine` (`form_chrome.dart`); `FormCopiesSection` (Phase 1, `lib/features/forms/editable/form_copies_section.dart`).
- Produces: `final FormTemplate form3Template` (formId `'form3'`); `buildForm3Pdf(Form3Data)` and `buildForm3Blank()` keep their signatures and output.

- [ ] **Step 1: Register the official blank (the failing test).** In `test/features/forms/editable/all_templates_test.dart`, add `import 'package:ethesishub/features/forms/form3_pdf.dart';` and put `'form3': buildForm3Blank,` inside the `officialBlanks` map literal.

- [ ] **Step 2: Run it and watch it do nothing yet**

Run: `flutter test test/features/forms/editable/all_templates_test.dart`
Expected: PASS without any form3 group. Form 3 isn't registered in `formTemplates` yet, so the map entry is unused until Step 5. This step just confirms the file compiles.

- [ ] **Step 3: Replace `lib/features/forms/form3_pdf.dart`** with:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form3_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);

/// Form 3's text, block by block, for an editable copy (spec 2026-09-24).
/// Every string on the page below the letterhead comes from here; the
/// official blank and filled letters read it unedited, so they print as
/// they always have.
final FormTemplate form3Template = FormTemplate(
  formId: 'form3',
  title: 'Form 3 — Request to Convene the Panel for Pre-Oral Defense',
  blocks: [
    ...letterOpeningBlocks(
      rdCode: 'RD-33-06/24-04',
      formTitle:
          'Form 3. Request to Convene the Thesis Panel Members for '
          'Pre-Oral Defense',
    ),
    const FormBlock(
      id: 'request',
      label: 'Request',
      multiline: true,
      defaultText: 'I would like to request the Undergraduate Thesis Panel '
          'Members consisting of:',
    ),
    for (var i = 1; i <= 3; i++)
      FormBlock(
          id: 'panel.$i', label: 'Panel member $i', kind: BlockKind.blank),
    const FormBlock(
      id: 'convene',
      label: 'Purpose',
      multiline: true,
      defaultText: 'To convene and deliberate on the proposal of',
    ),
    const FormBlock(
        id: 'presenters', label: 'Presenters', kind: BlockKind.blank),
    const FormBlock(
        id: 'entitled', label: 'Before the title', defaultText: 'entitled'),
    const FormBlock(
      id: 'title',
      label: 'Thesis title',
      kind: BlockKind.blank,
      multiline: true,
    ),
    const FormBlock(id: 'onWord', label: 'Before the date', defaultText: 'on'),
    const FormBlock(
        id: 'scheduledDate', label: 'Defense date', kind: BlockKind.blank),
    const FormBlock(id: 'inWord', label: 'Before the place', defaultText: 'in'),
    const FormBlock(id: 'venue', label: 'Place', kind: BlockKind.blank),
    const FormBlock(id: 'atWord', label: 'Before the time', defaultText: 'at'),
    const FormBlock(id: 'time', label: 'Time', kind: BlockKind.blank),
    FormBlock(
      id: 'placeTimeLabel',
      label: 'Labels under place and time',
      defaultText: '(Place)${' ' * 45}(Time)',
    ),
    const FormBlock(
      id: 'closing',
      label: 'Closing line',
      defaultText: 'Your approval on this request is highly appreciated.',
    ),
    const FormBlock(
        id: 'valediction', label: 'Sign-off', defaultText: 'Very truly yours,'),
    const FormBlock(id: 'adviser', label: 'Thesis Adviser: name'),
    const FormBlock(
      id: 'adviser.role',
      label: 'Thesis Adviser: title',
      defaultText: 'Thesis Adviser',
    ),
    ...letterApprovalBlocks,
  ],
  layout: (t) => [_page(t)],
);

/// The whole printed page, shared by a real letter, the blank template and
/// an editable copy. `data == null` is the template and copy case.
///
/// Where the filled letter prints app data (presenters, panel, title, date,
/// place, time, college) the data wins; otherwise the block prints: its
/// typed text, or a ruled line while blank.
pw.Widget _page(FormText t, {Form3Data? data}) {
  final presenters = data == null || data.presenterNames.isEmpty
      ? null
      : panelSentence(data.presenterNames);
  final panel = data == null || data.panelNames.isEmpty
      ? null
      : data.panelNames;
  final title = data?.title.isNotEmpty == true ? data!.title : null;
  final scheduledAt = data?.scheduledAt;
  final venue = data?.venue.isNotEmpty == true ? data!.venue : null;
  final college = data?.college ?? '';

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      ...letterOpening(t, college: college),
      pw.Text(t.of('request'), style: _bodyStyle),
      pw.SizedBox(height: 8),
      if (panel != null)
        for (final name in panel)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(name, style: _bodyStyle),
          )
      else
        for (var i = 1; i <= 3; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: blankOr(t, 'panel.$i', width: 260, style: _bodyStyle),
          ),
      pw.SizedBox(height: 8),
      pw.Text('${t.of('convene')} ${presenters ?? ''}', style: _bodyStyle),
      if (presenters == null)
        blankOr(t, 'presenters', width: 220, style: _bodyStyle),
      pw.SizedBox(height: 4),
      pw.Text(t.of('entitled'), style: _bodyStyle),
      dataOr(title, t, 'title', width: 400, style: _bodyStyle),
      pw.SizedBox(height: 8),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('${t.of('onWord')} ', style: _bodyStyle),
          dataOr(
            scheduledAt == null
                ? null
                : '${scheduledAt.day} ${monthName(scheduledAt.month)} '
                    '${scheduledAt.year}',
            t,
            'scheduledDate',
            width: 100,
            style: _bodyStyle,
          ),
          pw.Text(' ${t.of('inWord')} ', style: _bodyStyle),
          pw.Expanded(child: dataOr(venue, t, 'venue', style: _bodyStyle)),
        ],
      ),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('${t.of('atWord')} ', style: _bodyStyle),
          dataOr(
            scheduledAt == null
                ? null
                : '${scheduledAt.hour.toString().padLeft(2, '0')}:'
                    '${scheduledAt.minute.toString().padLeft(2, '0')}',
            t,
            'time',
            width: 100,
            style: _bodyStyle,
          ),
          pw.Expanded(child: pw.SizedBox()),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        t.of('placeTimeLabel'),
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
      pw.SizedBox(height: 12),
      pw.Text(t.of('closing'), style: _bodyStyle),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t.of('valediction'), style: _bodyStyle),
      ),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: signableLine(t.of('adviser'), t.of('adviser.role')),
      ),
      pw.SizedBox(height: 8),
      ...letterApproval(t, college: college),
    ],
  );
}

/// Generates Form 3 — Request to Convene the Thesis Panel Members for
/// Pre-Oral Defense — as a PDF. `compress: false` keeps the content
/// streams text-greppable; see `form1_pdf.dart` for why that matters.
Future<Uint8List> buildForm3Pdf(Form3Data data) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form3Template), data: data),
    ),
  );
  return doc.save();
}

/// A blank Form 3: the same chrome and letter body as [buildForm3Pdf],
/// with every variable clause a ruled line. It is meant to be printed and
/// completed by hand, the way this letter is used before a defence exists
/// in the app at all.
Future<Uint8List> buildForm3Blank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form3Template)),
    ),
  );
  return doc.save();
}
```

- [ ] **Step 4: Run the official Form 3 tests unchanged**

Run: `flutter test test/features/forms/form3_pdf_test.dart`
Expected: PASS, with the test file untouched.

- [ ] **Step 5: Register the template.** In `lib/features/forms/editable/form_templates.dart`, add `import 'package:ethesishub/features/forms/form3_pdf.dart';` and the entry `form3Template.formId: form3Template,` to `formTemplates`. Also update its doc comment's first sentence to read: `/// Every form that can be edited in the app, by id.`

- [ ] **Step 6: Run the all-templates test**

Run: `flutter test test/features/forms/editable/all_templates_test.dart`
Expected: PASS, now including the `form3` group and its "a new copy prints exactly like the official blank" test.
If that equivalence test fails, compare the two extracted texts. The difference names the block whose default or placement is off; fix the template, never the test.

- [ ] **Step 7: Put copies on the Form 3 card.** In `lib/features/forms/forms_screen.dart`, in `_Form3Card`'s `_FormCard(` call (the one with `cardKey: const Key('form3Card')`), add as its last argument:

```dart
      footer: const FormCopiesSection(
        formId: 'form3',
        defaultName: 'Form 3 copy',
      ),
```

- [ ] **Step 8: Run the Forms suites and commit**

Run: `flutter test test/features/forms/`
Expected: all PASS.

```bash
git add lib/features/forms/form3_pdf.dart lib/features/forms/editable/form_templates.dart lib/features/forms/forms_screen.dart test/features/forms/editable/all_templates_test.dart
git status --short
git commit -m "feat(forms): Form 3 can be edited as a copy

Form 3's page reads every string through its template; the official
blank and filled letters print exactly as before, and a new copy starts
as the official blank.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Forms 4a and 4b — Change of Adviser, Change of Title

**Files:**
- Modify: `lib/features/forms/form4a_pdf.dart` (replace the whole file)
- Modify: `lib/features/forms/form4b_pdf.dart` (replace the whole file)
- Modify: `lib/features/forms/editable/form_templates.dart`
- Modify: `lib/features/forms/forms_screen.dart` (`_Form4aCard`, `_Form4bCard`)
- Modify: `test/features/forms/editable/all_templates_test.dart`

**Interfaces:**
- Consumes: Task 1 (`blankOr`, `letterOpeningBlocks`, `letterApprovalBlocks`, `letterOpening`, `letterApproval`); `formTheme`, `signableLine`; `FormCopiesSection`.
- Produces: `final FormTemplate form4aTemplate` (`'form4a'`), `final FormTemplate form4bTemplate` (`'form4b'`); `buildForm4aBlank()` / `buildForm4bBlank()` unchanged in signature and output.

- [ ] **Step 1: Register both official blanks.** In `all_templates_test.dart` add the imports `form4a_pdf.dart` and `form4b_pdf.dart`, and put `'form4a': buildForm4aBlank,` and `'form4b': buildForm4bBlank,` in `officialBlanks`.

- [ ] **Step 2: Replace `lib/features/forms/form4a_pdf.dart`** with:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);
const _noteStyle = pw.TextStyle(fontSize: 8, color: PdfColors.grey600);

/// Form 4a's text, block by block, for an editable copy.
final FormTemplate form4aTemplate = FormTemplate(
  formId: 'form4a',
  title: 'Form 4a — Change of Undergraduate Thesis Adviser',
  blocks: [
    ...letterOpeningBlocks(
      rdCode: 'RD-34-06/24-04',
      formTitle: 'Form 4a. Change of Undergraduate Thesis Adviser',
    ),
    const FormBlock(
      id: 'request',
      label: 'Request',
      multiline: true,
      defaultText: 'I would like to request for the change of my '
          'undergraduate Thesis Adviser',
    ),
    const FormBlock(
        id: 'nominatedAdviser',
        label: 'Nominated adviser',
        kind: BlockKind.blank),
    const FormBlock(id: 'toWord', label: 'Between the names', defaultText: 'to'),
    const FormBlock(
      id: 'nominatedLabel',
      label: 'Label under the nominated adviser',
      defaultText: '(Nominated Adviser)',
    ),
    const FormBlock(
        id: 'formerAdviser', label: 'Former adviser', kind: BlockKind.blank),
    const FormBlock(
      id: 'formerLabel',
      label: 'Label under the former adviser',
      defaultText: '(Former Adviser)',
    ),
    const FormBlock(
      id: 'reasonsLead',
      label: 'Before the reasons',
      defaultText: 'for the following reasons:',
    ),
    for (var i = 1; i <= 3; i++)
      FormBlock(id: 'reason.$i', label: 'Reason $i', kind: BlockKind.blank),
    const FormBlock(
      id: 'closing',
      label: 'Closing line',
      defaultText: 'Your approval on this matter is highly appreciated.',
    ),
    const FormBlock(
        id: 'valediction', label: 'Sign-off', defaultText: 'Respectfully yours,'),
    const FormBlock(id: 'student', label: 'Student: name'),
    const FormBlock(
        id: 'student.role', label: 'Student: title', defaultText: 'Student'),
    const FormBlock(
        id: 'conformeHeading',
        label: 'Conforme heading',
        defaultText: 'Conforme:'),
    const FormBlock(id: 'nominated', label: 'Nominated adviser: name'),
    const FormBlock(
      id: 'nominated.role',
      label: 'Nominated adviser: title',
      defaultText: 'Nominated Adviser',
    ),
    const FormBlock(id: 'former', label: 'Former adviser: name'),
    const FormBlock(
      id: 'former.role',
      label: 'Former adviser: title',
      defaultText: 'Former Adviser',
    ),
    ...letterApprovalBlocks,
  ],
  layout: (t) => [_page(t)],
);

/// The printed page, for the blank template and an editable copy. Form 4a
/// has no filled version: the app tracks no adviser-reassignment workflow
/// (no former or nominated adviser, no reason for the change anywhere in
/// the data model), so the office prints this blank and completes it by
/// hand.
pw.Widget _page(FormText t) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      ...letterOpening(t),
      pw.Text(t.of('request'), style: _bodyStyle),
      pw.SizedBox(height: 4),
      pw.Row(
        children: [
          blankOr(t, 'nominatedAdviser', width: 260, style: _bodyStyle),
          pw.SizedBox(width: 6),
          pw.Text(t.of('toWord'), style: _bodyStyle),
        ],
      ),
      pw.SizedBox(height: 2),
      pw.Text(t.of('nominatedLabel'), style: _noteStyle),
      pw.SizedBox(height: 4),
      blankOr(t, 'formerAdviser', width: 260, style: _bodyStyle),
      pw.Text(t.of('formerLabel'), style: _noteStyle),
      pw.SizedBox(height: 10),
      pw.Text(t.of('reasonsLead'), style: _bodyStyle),
      pw.SizedBox(height: 6),
      for (var i = 1; i <= 3; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: blankOr(t, 'reason.$i', width: 460, style: _bodyStyle),
        ),
      pw.SizedBox(height: 10),
      pw.Text(t.of('closing'), style: _bodyStyle),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t.of('valediction'), style: _bodyStyle),
      ),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: signableLine(t.of('student'), t.of('student.role')),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        t.of('conformeHeading'),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
      signableLine(t.of('nominated'), t.of('nominated.role')),
      signableLine(t.of('former'), t.of('former.role')),
      ...letterApproval(t),
    ],
  );
}

/// Form 4a — Change of Undergraduate Thesis Adviser. Blank template only;
/// see [_page] for why there is no filled version.
Future<Uint8List> buildForm4aBlank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form4aTemplate)),
    ),
  );
  return doc.save();
}
```

- [ ] **Step 3: Replace `lib/features/forms/form4b_pdf.dart`** with:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);

/// Form 4b's text, block by block, for an editable copy.
final FormTemplate form4bTemplate = FormTemplate(
  formId: 'form4b',
  title: 'Form 4b — Change of Undergraduate Thesis Title',
  blocks: [
    ...letterOpeningBlocks(
      rdCode: 'RD-35-06/24-04',
      formTitle: 'Form 4b. Change of Undergraduate Thesis Title',
    ),
    const FormBlock(
      id: 'request',
      label: 'Request',
      multiline: true,
      defaultText: 'I would like to request for the change of my '
          'undergraduate Thesis Title',
    ),
    const FormBlock(
      id: 'oldTitle',
      label: 'Current title',
      kind: BlockKind.blank,
      multiline: true,
    ),
    const FormBlock(id: 'toWord', label: 'Between the titles', defaultText: 'to'),
    const FormBlock(
      id: 'newTitle',
      label: 'New title',
      kind: BlockKind.blank,
      multiline: true,
    ),
    const FormBlock(
      id: 'reasonsLead',
      label: 'Before the reasons',
      defaultText: 'for the following reasons:',
    ),
    for (var i = 1; i <= 3; i++)
      FormBlock(id: 'reason.$i', label: 'Reason $i', kind: BlockKind.blank),
    const FormBlock(
      id: 'closing',
      label: 'Closing line',
      defaultText: 'Your approval on this matter is highly appreciated.',
    ),
    const FormBlock(
        id: 'valediction', label: 'Sign-off', defaultText: 'Respectfully yours,'),
    const FormBlock(id: 'student', label: 'Student: name'),
    const FormBlock(
        id: 'student.role', label: 'Student: title', defaultText: 'Student'),
    const FormBlock(
        id: 'notedHeading', label: 'Noted heading', defaultText: 'Noted:'),
    const FormBlock(id: 'adviser', label: 'Thesis Adviser: name'),
    const FormBlock(
      id: 'adviser.role',
      label: 'Thesis Adviser: title',
      defaultText: 'Thesis Adviser',
    ),
    ...letterApprovalBlocks,
  ],
  layout: (t) => [_page(t)],
);

/// The printed page, for the blank template and an editable copy. Form 4b
/// has no filled version, for the same reason as Form 4a: the app has no
/// "change the approved title" workflow (title changes go through the
/// multi-round title defence instead).
pw.Widget _page(FormText t) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      ...letterOpening(t),
      pw.Text(t.of('request'), style: _bodyStyle),
      pw.SizedBox(height: 6),
      blankOr(t, 'oldTitle', width: 460, style: _bodyStyle),
      pw.SizedBox(height: 4),
      pw.Text(t.of('toWord'), style: _bodyStyle),
      pw.SizedBox(height: 6),
      blankOr(t, 'newTitle', width: 460, style: _bodyStyle),
      pw.SizedBox(height: 10),
      pw.Text(t.of('reasonsLead'), style: _bodyStyle),
      pw.SizedBox(height: 6),
      for (var i = 1; i <= 3; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: blankOr(t, 'reason.$i', width: 460, style: _bodyStyle),
        ),
      pw.SizedBox(height: 10),
      pw.Text(t.of('closing'), style: _bodyStyle),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t.of('valediction'), style: _bodyStyle),
      ),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: signableLine(t.of('student'), t.of('student.role')),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        t.of('notedHeading'),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
      signableLine(t.of('adviser'), t.of('adviser.role')),
      ...letterApproval(t),
    ],
  );
}

/// Form 4b — Change of Undergraduate Thesis Title. Blank template only;
/// see [_page] for why there is no filled version.
Future<Uint8List> buildForm4bBlank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form4bTemplate)),
    ),
  );
  return doc.save();
}
```

- [ ] **Step 4: Run the official 4a and 4b tests unchanged**

Run: `flutter test test/features/forms/form4a_pdf_test.dart test/features/forms/form4b_pdf_test.dart`
Expected: PASS, test files untouched.

- [ ] **Step 5: Register both templates.** In `form_templates.dart`, import `form4a_pdf.dart` and `form4b_pdf.dart`, and add `form4aTemplate.formId: form4aTemplate,` and `form4bTemplate.formId: form4bTemplate,`.

- [ ] **Step 6: Run the all-templates test**

Run: `flutter test test/features/forms/editable/all_templates_test.dart`
Expected: PASS, including both new groups and both blank-equivalence tests. On a mismatch, fix the template, never the test.

- [ ] **Step 7: Put copies on both cards.** In `forms_screen.dart`, add as the last argument of the `_FormCard(` call with `cardKey: const Key('form4aCard')`:

```dart
      footer: const FormCopiesSection(
        formId: 'form4a',
        defaultName: 'Form 4a copy',
      ),
```

and of the one with `cardKey: const Key('form4bCard')`:

```dart
      footer: const FormCopiesSection(
        formId: 'form4b',
        defaultName: 'Form 4b copy',
      ),
```

- [ ] **Step 8: Run the Forms suites and commit**

Run: `flutter test test/features/forms/`
Expected: all PASS.

```bash
git add lib/features/forms/form4a_pdf.dart lib/features/forms/form4b_pdf.dart lib/features/forms/editable/form_templates.dart lib/features/forms/forms_screen.dart test/features/forms/editable/all_templates_test.dart
git status --short
git commit -m "feat(forms): Forms 4a and 4b can be edited as copies

Both letters read every string through their templates; the official
blanks print exactly as before, and a new copy starts as the blank.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Form 5a — Request for Final Oral Defense

**Files:**
- Modify: `lib/features/forms/form5a_pdf.dart` (replace the whole file)
- Modify: `lib/features/forms/editable/form_templates.dart`
- Modify: `lib/features/forms/forms_screen.dart` (`_Form5aCard`)
- Modify: `test/features/forms/editable/all_templates_test.dart`

**Interfaces:**
- Consumes: Task 1 (`dataOr`, `letterOpeningBlocks`, `letterApprovalBlocks`, `letterOpening`, `letterApproval`); `Form5aData`; `formTheme`, `monthName`, `signableLine`; `FormCopiesSection`.
- Produces: `final FormTemplate form5aTemplate` (`'form5a'`); `buildForm5aPdf(Form5aData)` / `buildForm5aBlank()` unchanged in signature and output.

- [ ] **Step 1: Register the official blank.** In `all_templates_test.dart`, import `form5a_pdf.dart` and add `'form5a': buildForm5aBlank,` to `officialBlanks`.

- [ ] **Step 2: Replace `lib/features/forms/form5a_pdf.dart`** with:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form5a_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);

/// Form 5a's text, block by block, for an editable copy.
final FormTemplate form5aTemplate = FormTemplate(
  formId: 'form5a',
  title: 'Form 5a — Request for Final Oral Defense',
  blocks: [
    ...letterOpeningBlocks(
      rdCode: 'RD-36-06/24-04',
      formTitle: 'Form 5a. Request for Final Oral Defense',
    ),
    const FormBlock(
      id: 'request',
      label: 'Request',
      multiline: true,
      defaultText: 'I have the honor to request for the final oral defense '
          'of my undergraduate thesis entitled',
    ),
    const FormBlock(
      id: 'title',
      label: 'Thesis title',
      kind: BlockKind.blank,
      multiline: true,
    ),
    const FormBlock(
      id: 'scheduleLead',
      label: 'Before the schedule',
      defaultText: 'The final oral defense will be conducted on',
    ),
    const FormBlock(
        id: 'scheduledDate', label: 'Defense date', kind: BlockKind.blank),
    const FormBlock(id: 'inWord', label: 'Before the place', defaultText: 'in'),
    const FormBlock(id: 'venue', label: 'Place', kind: BlockKind.blank),
    const FormBlock(id: 'atWord', label: 'Before the time', defaultText: 'at'),
    const FormBlock(id: 'time', label: 'Time', kind: BlockKind.blank),
    FormBlock(
      id: 'placeTimeLabel',
      label: 'Labels under place and time',
      defaultText: '(Place)${' ' * 50}(Time)',
    ),
    const FormBlock(
      id: 'closing',
      label: 'Closing line',
      defaultText: 'Your approval on this matter is highly appreciated.',
    ),
    const FormBlock(
        id: 'valediction', label: 'Sign-off', defaultText: 'Respectfully yours,'),
    const FormBlock(id: 'student', label: 'Student: name'),
    const FormBlock(
        id: 'student.role', label: 'Student: title', defaultText: 'Student'),
    const FormBlock(
        id: 'notedHeading', label: 'Noted heading', defaultText: 'Noted:'),
    const FormBlock(id: 'adviser', label: 'Thesis Adviser: name'),
    const FormBlock(
      id: 'adviser.role',
      label: 'Thesis Adviser: title',
      defaultText: 'Thesis Adviser',
    ),
    ...letterApprovalBlocks,
  ],
  layout: (t) => [_page(t)],
);

/// The whole printed page, shared by a real letter, the blank template and
/// an editable copy. `data == null` is the template and copy case. Where
/// the filled letter prints app data (title, date, place, time, college)
/// the data wins; otherwise the block prints.
pw.Widget _page(FormText t, {Form5aData? data}) {
  final title = data?.title.isNotEmpty == true ? data!.title : null;
  final scheduledAt = data?.scheduledAt;
  final venue = data?.venue.isNotEmpty == true ? data!.venue : null;
  final college = data?.college ?? '';

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      ...letterOpening(t, college: college),
      pw.Text(t.of('request'), style: _bodyStyle),
      pw.SizedBox(height: 4),
      dataOr(title == null ? null : '"$title".', t, 'title',
          width: 400, style: _bodyStyle),
      pw.SizedBox(height: 8),
      pw.Text(t.of('scheduleLead'), style: _bodyStyle),
      pw.SizedBox(height: 4),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          dataOr(
            scheduledAt == null
                ? null
                : '${scheduledAt.day} ${monthName(scheduledAt.month)} '
                    '${scheduledAt.year}',
            t,
            'scheduledDate',
            width: 100,
            style: _bodyStyle,
          ),
          pw.Text(' ${t.of('inWord')} ', style: _bodyStyle),
          pw.Expanded(child: dataOr(venue, t, 'venue', style: _bodyStyle)),
          pw.Text(' ${t.of('atWord')} ', style: _bodyStyle),
          dataOr(
            scheduledAt == null
                ? null
                : '${scheduledAt.hour.toString().padLeft(2, '0')}:'
                    '${scheduledAt.minute.toString().padLeft(2, '0')}',
            t,
            'time',
            width: 80,
            style: _bodyStyle,
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        t.of('placeTimeLabel'),
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
      pw.SizedBox(height: 12),
      pw.Text(t.of('closing'), style: _bodyStyle),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t.of('valediction'), style: _bodyStyle),
      ),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: signableLine(t.of('student'), t.of('student.role')),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        t.of('notedHeading'),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
      signableLine(t.of('adviser'), t.of('adviser.role')),
      ...letterApproval(t, college: college),
    ],
  );
}

/// Generates Form 5a — Request for Final Oral Defense — as a PDF.
Future<Uint8List> buildForm5aPdf(Form5aData data) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5aTemplate), data: data),
    ),
  );
  return doc.save();
}

/// A blank Form 5a: the same chrome and letter body as [buildForm5aPdf],
/// with every variable clause a ruled line.
Future<Uint8List> buildForm5aBlank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5aTemplate)),
    ),
  );
  return doc.save();
}
```

- [ ] **Step 3: Run the official Form 5a tests unchanged**

Run: `flutter test test/features/forms/form5a_pdf_test.dart`
Expected: PASS, test file untouched.

- [ ] **Step 4: Register the template.** In `form_templates.dart`, import `form5a_pdf.dart` and add `form5aTemplate.formId: form5aTemplate,`.

- [ ] **Step 5: Run the all-templates test**

Run: `flutter test test/features/forms/editable/all_templates_test.dart`
Expected: PASS, including `form5a` and its blank equivalence.

- [ ] **Step 6: Put copies on the card.** In `forms_screen.dart`, add as the last argument of the `_FormCard(` call with `cardKey: const Key('form5aCard')`:

```dart
      footer: const FormCopiesSection(
        formId: 'form5a',
        defaultName: 'Form 5a copy',
      ),
```

- [ ] **Step 7: Run the Forms suites and commit**

Run: `flutter test test/features/forms/`
Expected: all PASS.

```bash
git add lib/features/forms/form5a_pdf.dart lib/features/forms/editable/form_templates.dart lib/features/forms/forms_screen.dart test/features/forms/editable/all_templates_test.dart
git status --short
git commit -m "feat(forms): Form 5a can be edited as a copy

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Forms 5b and 5c — Presenter and Evaluator Profile, Evaluation Guide

**Files:**
- Modify: `lib/features/forms/form5b_pdf.dart` (replace the whole file)
- Modify: `lib/features/forms/form5c_pdf.dart` (replace the whole file)
- Modify: `lib/features/forms/editable/form_templates.dart`
- Modify: `lib/features/forms/forms_screen.dart` (`_Form5bCard`, `_Form5cCard`)
- Modify: `test/features/forms/editable/all_templates_test.dart`

**Interfaces:**
- Consumes: Task 1 (`valueOr`, `formHeadBlocks`, `fieldBlocks`); `Form5bData`, `Form5cData` (its totals are non-null `int`s, `rating` is `PassFail?`); `evaluationCriteria`, `EvaluationCriterion` (`key`, `label`, `weight`, `section`, `prompt`, `takesComment`), `EvaluationSection` (`lib/data/models/evaluation_criteria.dart`); `formChrome`, `formField`, `formRule`, `formAccent`, `formTheme`, `monthName`; `FormCopiesSection`.
- Produces: `final FormTemplate form5bTemplate` (`'form5b'`), `final FormTemplate form5cTemplate` (`'form5c'`); the four builders unchanged in signature and output.

- [ ] **Step 1: Register both official blanks.** In `all_templates_test.dart`, import `form5b_pdf.dart` and `form5c_pdf.dart` and add `'form5b': buildForm5bBlank,` and `'form5c': buildForm5cBlank,`.

- [ ] **Step 2: Replace `lib/features/forms/form5b_pdf.dart`** with:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form5b_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// Form 5b's text, block by block, for an editable copy: each field's label
/// and its value.
final FormTemplate form5bTemplate = FormTemplate(
  formId: 'form5b',
  title: 'Form 5b — Presenter and Evaluator Profile',
  blocks: [
    ...formHeadBlocks(
      rdCode: 'RD-37-06/24-04',
      formTitle: 'Res. Form 5b. Presenter and Evaluator Profile',
    ),
    ...fieldBlocks('presenter', 'Name of Presenter'),
    ...fieldBlocks('degree', 'Degree and Field of Specialization'),
    ...fieldBlocks('presentedDate', 'Date of Presentation'),
    ...fieldBlocks('presentedTime', 'Time of Presentation'),
    ...fieldBlocks('venue', 'Venue'),
    ...fieldBlocks('studyTitle', 'Title of the Study'),
    ...fieldBlocks('evaluator', 'Evaluator'),
    ...fieldBlocks('rank', 'Academic Rank'),
    ...fieldBlocks('specialization', 'Field of Specialization'),
  ],
  layout: (t) => [_page(t)],
);

/// The whole printed page, shared by a real profile, the blank template and
/// an editable copy. A field prints the app's value when there is one,
/// otherwise its typed text, otherwise a ruled blank.
pw.Widget _page(FormText t, {Form5bData? data}) {
  final presentedOn = data?.presentedOn;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
      pw.SizedBox(height: 16),
      formField(
        t.of('presenter.label'),
        valueOr(
          data == null || data.presenterNames.isEmpty
              ? null
              : data.presenterNames.join(', '),
          t,
          'presenter',
        ),
      ),
      formField(t.of('degree.label'), valueOr(null, t, 'degree')),
      formField(
        t.of('presentedDate.label'),
        valueOr(
          presentedOn == null
              ? null
              : '${presentedOn.day} ${monthName(presentedOn.month)} '
                  '${presentedOn.year}',
          t,
          'presentedDate',
        ),
      ),
      formField(
        t.of('presentedTime.label'),
        valueOr(
          presentedOn == null
              ? null
              : '${presentedOn.hour.toString().padLeft(2, '0')}:'
                  '${presentedOn.minute.toString().padLeft(2, '0')}',
          t,
          'presentedTime',
        ),
      ),
      formField(t.of('venue.label'), valueOr(data?.venue, t, 'venue')),
      formField(
          t.of('studyTitle.label'), valueOr(data?.title, t, 'studyTitle')),
      pw.SizedBox(height: 12),
      formField(t.of('evaluator.label'),
          valueOr(data?.evaluatorName, t, 'evaluator')),
      formField(t.of('rank.label'), valueOr(null, t, 'rank')),
      formField(t.of('specialization.label'),
          valueOr(data?.evaluatorField, t, 'specialization')),
    ],
  );
}

/// Generates Form 5b — Presenter and Evaluator Profile — as a PDF.
/// `compress: false` keeps the content streams text-greppable.
Future<Uint8List> buildForm5bPdf(Form5bData data) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5bTemplate), data: data),
    ),
  );
  return doc.save();
}

/// A blank Form 5b: the same chrome and fields as [buildForm5bPdf], every
/// one of them a ruled line.
Future<Uint8List> buildForm5bBlank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5bTemplate)),
    ),
  );
  return doc.save();
}
```

- [ ] **Step 3: Replace `lib/features/forms/form5c_pdf.dart`** with:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form5c_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _valueStyle = pw.TextStyle(fontSize: 10.5);
const _promptStyle = pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600);
const _sectionHeaderStyle = pw.TextStyle(
  fontSize: 11,
  fontWeight: pw.FontWeight.bold,
  color: formAccent,
);

List<EvaluationCriterion> _criteriaIn(EvaluationSection section) =>
    evaluationCriteria.where((c) => c.section == section).toList();

/// A criterion's editable blocks: its name, its prompt (Section A only, and
/// only where the rubric has one), its score, and its comment (Section A
/// only). The weight is not a block: it defines the scoring.
List<FormBlock> _criterionBlocks(EvaluationCriterion c) => [
      FormBlock(
        id: 'criterion.${c.key}.label',
        label: '${c.label}: criterion',
        defaultText: c.label,
      ),
      if (c.takesComment && c.prompt.isNotEmpty)
        FormBlock(
          id: 'criterion.${c.key}.prompt',
          label: '${c.label}: prompt',
          defaultText: c.prompt,
          multiline: true,
        ),
      FormBlock(
        id: 'criterion.${c.key}.score',
        label: '${c.label}: score (out of ${c.weight})',
        kind: BlockKind.blank,
      ),
      if (c.takesComment)
        FormBlock(
          id: 'criterion.${c.key}.comment',
          label: '${c.label}: comment',
          kind: BlockKind.blank,
          multiline: true,
        ),
    ];

/// Form 5c's text, block by block, for an editable copy.
final FormTemplate form5cTemplate = FormTemplate(
  formId: 'form5c',
  title: 'Form 5c — Evaluation Guide',
  blocks: [
    ...formHeadBlocks(
      rdCode: 'RD-37-06/24-04',
      formTitle: 'Form 5c. Evaluation Guide',
    ),
    const FormBlock(
        id: 'guideHeading', label: 'Heading', defaultText: 'EVALUATION GUIDE'),
    const FormBlock(
      id: 'guideSubheading',
      label: 'Subheading',
      defaultText: 'FOR REPORTS ON RESEARCHES AND TECHNICAL PAPERS',
    ),
    ...fieldBlocks('presenter', 'Name of Presenter'),
    ...fieldBlocks('degree', 'Degree and Field of Specialization'),
    ...fieldBlocks('presentedDate', 'Date of Presentation'),
    ...fieldBlocks('presentedTime', 'Time of Presentation'),
    ...fieldBlocks('venue', 'Venue'),
    ...fieldBlocks('studyTitle', 'Title of the Study'),
    ...fieldBlocks('defence', 'Defence'),
    ...fieldBlocks('evaluator', 'Evaluator'),
    ...fieldBlocks('rank', 'Academic Rank'),
    ...fieldBlocks('specialization', 'Field of Specialization'),
    const FormBlock(
        id: 'sectionA', label: 'Section A heading', defaultText: 'A. CONTENT (50%)'),
    for (final c in _criteriaIn(EvaluationSection.content))
      ..._criterionBlocks(c),
    const FormBlock(
      id: 'sectionB',
      label: 'Section B heading',
      defaultText: 'B. PRESENTATION AND DEFENSE (50%)',
    ),
    for (final c in _criteriaIn(EvaluationSection.presentation))
      ..._criterionBlocks(c),
    const FormBlock(
        id: 'summaryHeading', label: 'Summary heading', defaultText: 'SUMMARY'),
    ...fieldBlocks('summaryA', 'A. CONTENT'),
    ...fieldBlocks('summaryB', 'B. PRESENTATION AND DEFENSE'),
    ...fieldBlocks('average', 'Average Rating'),
    ...fieldBlocks('finalGrade', 'Final Grade'),
    const FormBlock(
        id: 'rating.label', label: 'Rating (label)', defaultText: 'Rating (§8a):'),
    const FormBlock(id: 'rating', label: 'Rating', defaultText: '—'),
  ],
  layout: (t) => _page(t),
);

/// One rubric row: name + weight, the prompt (Section A only), the score out
/// of the weight, and a comment line where one was written (Section A only).
///
/// With app data ([scores] non-null) a missing score rules a blank, never a
/// 0: "0 / 25" would read as a genuine zero. Without app data (the blank
/// template, an editable copy) the score and comment come from the blocks.
pw.Widget _criterionRow(
  FormText t,
  EvaluationCriterion c, {
  Map<String, int>? scores,
  Map<String, String>? comments,
}) {
  final score = scores != null
      ? scores[c.key]?.toString()
      : valueOr(null, t, 'criterion.${c.key}.score');
  final comment = !c.takesComment
      ? null
      : comments != null
          ? comments[c.key]
          : valueOr(null, t, 'criterion.${c.key}.comment');
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                '${t.of('criterion.${c.key}.label')} (${c.weight}%)',
                style: const pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            if (score == null)
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  formRule(width: 26),
                  pw.SizedBox(width: 4),
                  pw.Text('/ ${c.weight}', style: _valueStyle),
                ],
              )
            else
              pw.Text('$score / ${c.weight}', style: _valueStyle),
          ],
        ),
        if (c.takesComment && c.prompt.isNotEmpty)
          pw.Text(t.of('criterion.${c.key}.prompt'), style: _promptStyle),
        if (comment != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text('Comment: $comment', style: _promptStyle),
          ),
      ],
    ),
  );
}

/// A "label ... total" summary row. A null [value] rules a blank rather than
/// printing a total of 0.
pw.Widget _summaryRow(String label, String? value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: _valueStyle),
        value == null
            ? formRule(width: 40)
            : pw.Text(value, style: _valueStyle),
      ],
    ),
  );
}

/// The whole printed sheet, shared by a real evaluation, the blank template
/// and an editable copy. `data == null` is the template and copy case: every
/// field, score and total comes from its block (typed text, or a ruled
/// blank). With app data, the data prints exactly as it always has.
List<pw.Widget> _page(FormText t, {Form5cData? data}) {
  final presentedOn = data?.presentedOn;
  final scores = data?.scores;
  final comments = data?.comments;

  return [
    formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
    pw.SizedBox(height: 10),
    pw.Center(
      child: pw.Column(
        children: [
          pw.Text(
            t.of('guideHeading'),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            t.of('guideSubheading'),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    ),
    pw.SizedBox(height: 12),

    formField(t.of('presenter.label'),
        valueOr(data?.presenterNames.join(', '), t, 'presenter')),
    formField(t.of('degree.label'), valueOr(null, t, 'degree')),
    formField(
      t.of('presentedDate.label'),
      valueOr(
        presentedOn == null
            ? null
            : '${presentedOn.day} ${monthName(presentedOn.month)} '
                '${presentedOn.year}',
        t,
        'presentedDate',
      ),
    ),
    formField(
      t.of('presentedTime.label'),
      valueOr(
        presentedOn == null
            ? null
            : '${presentedOn.hour.toString().padLeft(2, '0')}:'
                '${presentedOn.minute.toString().padLeft(2, '0')}',
        t,
        'presentedTime',
      ),
    ),
    formField(t.of('venue.label'), valueOr(data?.venue, t, 'venue')),
    formField(t.of('studyTitle.label'), valueOr(data?.title, t, 'studyTitle')),
    formField(t.of('defence.label'),
        valueOr(data?.defenceType.label, t, 'defence')),
    formField(t.of('evaluator.label'),
        valueOr(data?.evaluatorName, t, 'evaluator')),
    formField(t.of('rank.label'), valueOr(null, t, 'rank')),
    formField(t.of('specialization.label'),
        valueOr(data?.evaluatorField, t, 'specialization')),

    pw.SizedBox(height: 14),
    pw.Container(height: 1, color: PdfColors.grey400),
    pw.SizedBox(height: 8),

    pw.Text(t.of('sectionA'), style: _sectionHeaderStyle),
    pw.SizedBox(height: 4),
    for (final c in _criteriaIn(EvaluationSection.content))
      _criterionRow(t, c, scores: scores, comments: comments),

    pw.SizedBox(height: 8),
    pw.Text(t.of('sectionB'), style: _sectionHeaderStyle),
    pw.SizedBox(height: 4),
    for (final c in _criteriaIn(EvaluationSection.presentation))
      _criterionRow(t, c, scores: scores, comments: comments),

    pw.SizedBox(height: 14),
    pw.Container(height: 1, color: PdfColors.grey400),
    pw.SizedBox(height: 8),
    pw.Text(
      t.of('summaryHeading'),
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 6),
    _summaryRow(t.of('summaryA.label'),
        valueOr(data?.sectionATotal.toString(), t, 'summaryA')),
    _summaryRow(t.of('summaryB.label'),
        valueOr(data?.sectionBTotal.toString(), t, 'summaryB')),
    // The app does not compute an average (D62); a labelled blank says so.
    formField(t.of('average.label'), valueOr(null, t, 'average')),
    _summaryRow(t.of('finalGrade.label'),
        valueOr(data?.finalGrade.toString(), t, 'finalGrade')),
    pw.SizedBox(height: 6),
    pw.Text(
      '${t.of('rating.label')} ${data?.rating?.label ?? t.of('rating')}',
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    ),
  ];
}

/// Generates Form 5c — Evaluation Guide — one panelist's completed scoring
/// sheet, as a PDF. MultiPage: eleven criteria with prompts and comments do
/// not fit one sheet (see form1_pdf.dart for why Page silently clips).
Future<Uint8List> buildForm5cPdf(Form5cData data) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5cTemplate), data: data),
    ),
  );
  return doc.save();
}

/// A blank Form 5c: the same chrome, criteria, headings and summary rows as
/// [buildForm5cPdf], nothing filled in. An unfilled rubric needs no template
/// marking; a page of ruled lines is obviously unfilled.
Future<Uint8List> buildForm5cBlank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5cTemplate)),
    ),
  );
  return doc.save();
}
```

- [ ] **Step 4: Run the official 5b and 5c tests unchanged**

Run: `flutter test test/features/forms/form5b_pdf_test.dart test/features/forms/form5c_pdf_test.dart test/features/forms/form5c_data_test.dart`
Expected: PASS, test files untouched.

- [ ] **Step 5: Register both templates.** In `form_templates.dart`, import `form5b_pdf.dart` and `form5c_pdf.dart` and add `form5bTemplate.formId: form5bTemplate,` and `form5cTemplate.formId: form5cTemplate,`.

- [ ] **Step 6: Run the all-templates test**

Run: `flutter test test/features/forms/editable/all_templates_test.dart`
Expected: PASS, including `form5b`, `form5c` and both blank equivalences.

- [ ] **Step 7: Put copies on both cards.** In `forms_screen.dart`, add as the last argument of the `_FormCard(` call with `cardKey: const Key('form5bCard')`:

```dart
      footer: const FormCopiesSection(
        formId: 'form5b',
        defaultName: 'Form 5b copy',
      ),
```

and of the one with `cardKey: const Key('form5cCard')`:

```dart
      footer: const FormCopiesSection(
        formId: 'form5c',
        defaultName: 'Form 5c copy',
      ),
```

- [ ] **Step 8: Run the Forms suites and commit**

Run: `flutter test test/features/forms/`
Expected: all PASS.

```bash
git add lib/features/forms/form5b_pdf.dart lib/features/forms/form5c_pdf.dart lib/features/forms/editable/form_templates.dart lib/features/forms/forms_screen.dart test/features/forms/editable/all_templates_test.dart
git status --short
git commit -m "feat(forms): Forms 5b and 5c can be edited as copies

Every label and field of the profile, and every criterion name, prompt,
score and comment of the evaluation guide, reads through its template;
criterion weights stay fixed because they define the scoring. The
official blank and filled sheets print exactly as before.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Forms 7 and 8 — Certificate of Review, Certification of Bound Copies

**Files:**
- Modify: `lib/features/forms/form7_pdf.dart` (replace the whole file)
- Modify: `lib/features/forms/form8_pdf.dart` (replace the whole file)
- Modify: `lib/features/forms/editable/form_templates.dart`
- Modify: `lib/features/forms/forms_screen.dart` (`_Form7Card`, `_Form8Card`)
- Modify: `test/features/forms/editable/all_templates_test.dart`

**Interfaces:**
- Consumes: Task 1 (`blankOr`, `dataOr`, `formHeadBlocks`); `Form7Data`, `Form8Data`; `formChrome`, `formTheme`, `monthName`, `panelSentence`; `FormCopiesSection`.
- Produces: `final FormTemplate form7Template` (`'form7'`), `final FormTemplate form8Template` (`'form8'`); the four builders unchanged in signature and output.

- [ ] **Step 1: Register both official blanks.** In `all_templates_test.dart`, import `form7_pdf.dart` and `form8_pdf.dart` and add `'form7': buildForm7Blank,` and `'form8': buildForm8Blank,`.

- [ ] **Step 2: Replace `lib/features/forms/form7_pdf.dart`** with:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form7_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);
const _cellStyle = pw.TextStyle(fontSize: 9);

/// The seven roles the printed review table lists, in order. Each is the
/// default of its row's role block. Never resolved from data: two of these
/// roles are not modelled anywhere in this app (see `Form7Data`).
const _panelRoles = [
  'Dean',
  'Research Coordinator',
  'Thesis Adviser',
  'Member',
  'Member',
  'Grammarian',
  'Statistician',
];

/// Form 7's text, block by block, for an editable copy.
final FormTemplate form7Template = FormTemplate(
  formId: 'form7',
  title: 'Form 7 — Certificate of Review',
  blocks: [
    ...formHeadBlocks(
      rdCode: 'RD-38-06/24-04',
      formTitle: 'Form 7. Certificate of Review',
    ),
    const FormBlock(id: 'date', label: 'Date', kind: BlockKind.blank),
    const FormBlock(
        id: 'dateLabel', label: 'Label under the date', defaultText: 'Date'),
    const FormBlock(
      id: 'heading',
      label: 'Heading',
      defaultText: 'CERTIFICATION OF REVIEW',
    ),
    const FormBlock(
      id: 'certify',
      label: 'Certification',
      multiline: true,
      defaultText: 'This is to certify that the undersigned Thesis Panel '
          'Members have reviewed and approved for reproduction of the '
          'manuscript of',
    ),
    const FormBlock(
        id: 'presenters', label: 'Name of student', kind: BlockKind.blank),
    const FormBlock(
      id: 'presentersLabel',
      label: 'Label under the name',
      defaultText: '(Name of Student)',
    ),
    const FormBlock(
        id: 'entitled', label: 'Before the title', defaultText: 'Entitled'),
    const FormBlock(
      id: 'title',
      label: 'Thesis title',
      kind: BlockKind.blank,
      multiline: true,
    ),
    const FormBlock(
        id: 'table.member',
        label: 'Column: panel member',
        defaultText: 'Panel Member'),
    const FormBlock(
        id: 'table.approved', label: 'Column: approved', defaultText: 'Approved'),
    const FormBlock(
        id: 'table.remarks', label: 'Column: remarks', defaultText: 'Remarks'),
    for (var i = 1; i <= _panelRoles.length; i++) ...[
      FormBlock(
          id: 'panel.$i.name', label: 'Row $i: name', kind: BlockKind.blank),
      FormBlock(
        id: 'panel.$i.role',
        label: 'Row $i: role',
        defaultText: _panelRoles[i - 1],
      ),
      FormBlock(
          id: 'panel.$i.approved',
          label: 'Row $i: approved',
          kind: BlockKind.blank),
      FormBlock(
          id: 'panel.$i.remarks',
          label: 'Row $i: remarks',
          kind: BlockKind.blank),
    ],
  ],
  layout: (t) => [_page(t)],
);

pw.Widget _tableCell(String text, {bool header = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: pw.Text(
        text,
        style: header
            ? pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)
            : _cellStyle,
      ),
    );

/// The whole printed page, shared by a real certificate, the blank template
/// and an editable copy. With app data, the presenter and the title print
/// from it; everything else, and both of those without data, comes from the
/// blocks.
pw.Widget _page(FormText t, {Form7Data? data}) {
  final presenters = data == null || data.presenterNames.isEmpty
      ? null
      : panelSentence(data.presenterNames);
  final title = data?.title.isNotEmpty == true ? data!.title : null;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: blankOr(t, 'date', width: 140, style: _bodyStyle),
      ),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t.of('dateLabel'), style: const pw.TextStyle(fontSize: 8)),
      ),
      pw.SizedBox(height: 16),
      pw.Center(
        child: pw.Text(
          t.of('heading'),
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 14),
      pw.Text(
        t.of('certify'),
        style: _bodyStyle,
        textAlign: pw.TextAlign.justify,
      ),
      pw.SizedBox(height: 4),
      dataOr(presenters, t, 'presenters', width: 300, style: _bodyStyle),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          t.of('presentersLabel'),
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Text(t.of('entitled'), style: _bodyStyle),
      pw.SizedBox(height: 4),
      dataOr(title == null ? null : '"$title"', t, 'title',
          width: 460, style: _bodyStyle),
      pw.SizedBox(height: 18),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.6),
          1: pw.FlexColumnWidth(2.4),
          2: pw.FlexColumnWidth(2.0),
        },
        children: [
          pw.TableRow(
            children: [
              _tableCell(t.of('table.member'), header: true),
              _tableCell(t.of('table.approved'), header: true),
              _tableCell(t.of('table.remarks'), header: true),
            ],
          ),
          for (var i = 1; i <= _panelRoles.length; i++)
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('$i.', style: _cellStyle),
                      blankOr(t, 'panel.$i.name',
                          width: 140, height: 10, style: _cellStyle),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        t.of('panel.$i.role'),
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  child: blankOr(t, 'panel.$i.approved',
                      width: 100, height: 10, style: _cellStyle),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  child: blankOr(t, 'panel.$i.remarks',
                      width: 90, height: 10, style: _cellStyle),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

/// Generates Form 7 — Certificate of Review — as a PDF. `compress: false`
/// keeps the content streams text-greppable.
Future<Uint8List> buildForm7Pdf(Form7Data data) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => [_page(FormText(form7Template), data: data)],
    ),
  );
  return doc.save();
}

/// A blank Form 7: the same chrome, certification sentence and review table
/// as [buildForm7Pdf], with the presenter and title lines ruled.
Future<Uint8List> buildForm7Blank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => [_page(FormText(form7Template))],
    ),
  );
  return doc.save();
}
```

- [ ] **Step 3: Replace `lib/features/forms/form8_pdf.dart`** with:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form8_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// Form 8's text, block by block, for an editable copy.
///
/// The two identifying clauses sit mid-sentence inside justified prose, so
/// they are plain underscores rather than ruled lines: a rule widget cannot
/// be dropped into the middle of a `pw.Text`. As editable blocks they are
/// ordinary text whose default is those underscores.
final FormTemplate form8Template = FormTemplate(
  formId: 'form8',
  title: 'Form 8 — Certification of Submission of Bound Copies',
  blocks: [
    ...formHeadBlocks(
      rdCode: 'RD-39-06/24-04',
      formTitle: 'Form 8. Certification of Submission of Bound Copies',
    ),
    const FormBlock(id: 'date', label: 'Date', kind: BlockKind.blank),
    const FormBlock(
        id: 'dateLabel', label: 'Label under the date', defaultText: 'Date'),
    const FormBlock(id: 'heading', label: 'Heading', defaultText: 'CERTIFICATION'),
    const FormBlock(
      id: 'certifyLead',
      label: 'Before the names',
      defaultText: 'This is to certify that',
    ),
    FormBlock(
      id: 'students',
      label: 'Student names',
      defaultText: '_' * 31,
    ),
    const FormBlock(
      id: 'certifyMiddle',
      label: 'Between the names and the title',
      multiline: true,
      defaultText: 'has submitted bound copies of his/her undergraduate '
          'thesis entitled',
    ),
    FormBlock(
      id: 'thesisTitle',
      label: 'Thesis title',
      multiline: true,
      defaultText: '_' * 55,
    ),
    const FormBlock(
      id: 'signer.role',
      label: 'Signer: title',
      defaultText: 'Research Coordinator/Chair',
    ),
  ],
  layout: (t) => [_page(t)],
);

/// The whole printed page, shared by a real certificate, the blank template
/// and an editable copy. With app data, the date, the names and the title
/// print from it; without, from the blocks.
///
/// No "blank template" marking and no watermark: both were built and then
/// taken out. The blank is a sheet somebody prints and completes by hand;
/// once completed and signed it IS an issued certification. `Form8Unissuable`
/// guards the case that matters, a certificate generated from incomplete
/// real data.
pw.Widget _page(FormText t, {Form8Data? data}) {
  final issuedOn = data?.issuedOn;
  final studentsText =
      data == null ? t.of('students') : panelSentence(data.studentNames);
  final titleText = data == null ? t.of('thesisTitle') : data.title;

  final pw.Widget date;
  if (issuedOn != null) {
    date = pw.Text(
      '${issuedOn.day} ${monthName(issuedOn.month)} ${issuedOn.year}',
      textAlign: pw.TextAlign.center,
    );
  } else if (t.isBlank('date')) {
    date = pw.Container(
      height: 14,
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
      ),
    );
  } else {
    date = pw.Text(t.of('date'), textAlign: pw.TextAlign.center);
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(width: 160, child: date),
            pw.SizedBox(height: 2),
            pw.Text(t.of('dateLabel'), style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
      pw.SizedBox(height: 20),
      pw.Center(
        child: pw.Text(
          t.of('heading'),
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 16),
      pw.Text(
        '${t.of('certifyLead')} $studentsText ${t.of('certifyMiddle')} '
        '"$titleText".',
        textAlign: pw.TextAlign.justify,
        style: const pw.TextStyle(fontSize: 11),
      ),
      pw.SizedBox(height: 60),
      pw.Center(
        child: pw.Column(
          children: [
            pw.Container(width: 220, height: 1, color: PdfColors.grey700),
            pw.SizedBox(height: 3),
            pw.Text(t.of('signer.role'), style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    ],
  );
}

/// Generates Form 8 — Certification of Submission of Bound Copies — as a
/// PDF. `compress: false` keeps the content streams text-greppable; see
/// `form1_pdf.dart` for why that matters.
Future<Uint8List> buildForm8Pdf(Form8Data data) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form8Template), data: data),
    ),
  );
  return doc.save();
}

/// A blank Form 8: the same chrome, date rule, prose and signature line as
/// [buildForm8Pdf], with the two identifying clauses as underscores. It is
/// meant to be printed and completed by hand.
Future<Uint8List> buildForm8Blank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form8Template)),
    ),
  );
  return doc.save();
}
```

- [ ] **Step 4: Run the official 7 and 8 tests unchanged**

Run: `flutter test test/features/forms/form7_pdf_test.dart test/features/forms/form8_pdf_test.dart test/features/forms/form8_data_test.dart`
Expected: PASS, test files untouched.

- [ ] **Step 5: Register both templates.** In `form_templates.dart`, import `form7_pdf.dart` and `form8_pdf.dart` and add `form7Template.formId: form7Template,` and `form8Template.formId: form8Template,`.

- [ ] **Step 6: Run the all-templates test**

Run: `flutter test test/features/forms/editable/all_templates_test.dart`
Expected: PASS, including `form7`, `form8` and both blank equivalences.

- [ ] **Step 7: Put copies on both cards.** In `forms_screen.dart`, add as the last argument of the `_FormCard(` call with `cardKey: const Key('form7Card')`:

```dart
      footer: const FormCopiesSection(
        formId: 'form7',
        defaultName: 'Form 7 copy',
      ),
```

and of the one with `cardKey: const Key('form8Card')`:

```dart
          footer: const FormCopiesSection(
            formId: 'form8',
            defaultName: 'Form 8 copy',
          ),
```

- [ ] **Step 8: Run the Forms suites and commit**

Run: `flutter test test/features/forms/`
Expected: all PASS.

```bash
git add lib/features/forms/form7_pdf.dart lib/features/forms/form8_pdf.dart lib/features/forms/editable/form_templates.dart lib/features/forms/forms_screen.dart test/features/forms/editable/all_templates_test.dart
git status --short
git commit -m "feat(forms): Forms 7 and 8 can be edited as copies

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Every form editable, proven, and the whole app checked

**Files:**
- Modify: `test/features/forms/editable/all_templates_test.dart` (one test)
- Modify: `test/features/forms/forms_screen_test.dart` (one test)

**Interfaces:**
- Consumes: `formTemplates` (now nine entries); the forms-screen test helpers `seedUser`, `app`, `useTallSurface` already in `forms_screen_test.dart`.

- [ ] **Step 1: Assert the registry is complete.** In `all_templates_test.dart`, add at the top of `main()`, after the binding line:

```dart
  test('all nine forms can be edited as copies', () {
    expect(formTemplates.keys.toSet(), {
      'form1', 'form3', 'form4a', 'form4b', 'form5a', 'form5b', 'form5c',
      'form7', 'form8',
    });
    expect(officialBlanks.keys.toSet(), {
      'form3', 'form4a', 'form4b', 'form5a', 'form5b', 'form5c', 'form7',
      'form8',
    }, reason: 'every form with an official blank is checked against it');
  });
```

- [ ] **Step 2: Assert every card offers a copy.** In `test/features/forms/forms_screen_test.dart`, add at the end of `main()`:

```dart
  testWidgets('every form card offers a copy to edit in the app',
      (tester) async {
    useTallSurface(tester);
    final db = await seedUser('s1');
    await tester.pumpWidget(app(db, 's1'));
    await tester.pumpAndSettle();

    for (final form in [
      'form1', 'form3', 'form4a', 'form4b', 'form5a', 'form5b', 'form5c',
      'form7', 'form8',
    ]) {
      expect(
        find.descendant(
          of: find.byKey(Key('${form}Card')),
          matching: find.byKey(Key('${form}NewCopy')),
        ),
        findsOneWidget,
        reason: form,
      );
    }
  });
```

- [ ] **Step 3: Run both**

Run: `flutter test test/features/forms/editable/all_templates_test.dart test/features/forms/forms_screen_test.dart`
Expected: PASS.

- [ ] **Step 4: The whole suite**

Run: `flutter test`
Expected: `All tests passed!`. (One unrelated test, `evaluation_repository_test.dart` "a second submit edits the same document", has flaked once under full-suite load. If it alone fails, re-run once and report both runs.)

- [ ] **Step 5: Analyze**

Run: `flutter analyze`
Expected: no new issues in any file this plan changed.

- [ ] **Step 6: Commit**

```bash
git add test/features/forms/editable/all_templates_test.dart test/features/forms/forms_screen_test.dart
git status --short
git commit -m "test(forms): every form can be edited as a copy

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Report, with no commit.** Nothing to deploy: the Firestore rules already accept all nine form ids (Phase 1). Rebuild the APK. On a device, open Forms and, for a couple of forms, **New copy** → edit a field → **Save** → **Download PDF**. Check that **Download blank** still prints the unedited official blank.
