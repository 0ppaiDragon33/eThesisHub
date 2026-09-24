# Editable Forms — Phase 1 (Form 1 and saved copies) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Any signed-in user can start a named copy of Form 1 from the Forms screen, edit all of its text in the app with a live preview of the printed form, save it, come back to it, and download it as a PDF.

**Architecture:** A form becomes a `FormTemplate`: an ordered list of labelled text blocks (with today's wording as defaults) plus a layout function that reads every string through `FormText`. A saved copy stores only the blocks that differ from the default, under `users/{uid}/formCopies/{copyId}`, owner-only by Firestore rules. The editor screen lists the blocks as fields beside a debounced `PdfPreview`, and a `GoRoute.onExit` guard asks before leaving with unsaved edits.

**Tech Stack:** Flutter 3.44, Riverpod 2.6.1 (pinned), go_router 17.5.0 (pinned), `pdf` + `printing` 5.15 (already dependencies), Cloud Firestore + `fake_cloud_firestore` for tests, Firestore rules tested with `@firebase/rules-unit-testing` on the emulator.

**Spec:** `docs/superpowers/specs/2026-09-24-editable-forms-and-my-files-design.md` (this plan covers §11 step 1 only).

## Global Constraints

- **Commit only the files your task names.** The working tree has unrelated uncommitted changes (`MainActivity.kt`, `lib/app.dart`, `lib/core/widgets/app_shell.dart`, `lib/core/theme/app_theme.dart`, `lib/features/dashboard/progress_rail.dart`, `lib/features/defence/consolidated_defence_screen.dart`, `lib/core/platform/native_back.dart`, `test/core/platform/`, the deleted `double_back_to_exit` files, `macos/…`, `android/build/`). Never `git add -A`, `git add .`, or `git commit -a`. Stage by explicit path and check `git status` before every commit.
- **No new dependencies.** `pdf`, `printing`, `flutter_riverpod`, `go_router`, `cloud_firestore`, `fake_cloud_firestore`, `firebase_auth_mocks` are already in `pubspec.yaml`. Do not bump any pinned package.
- **The official filled Form 1 is untouched.** `lib/features/forms/form1_pdf.dart` and `form1_data.dart` are not modified, and `test/features/forms/form1_pdf_test.dart` / `form1_data_test.dart` must still pass unchanged.
- Every generated PDF uses `pw.Document(compress: false, theme: await formTheme())`. Uncompressed output is what `test/features/forms/pdf_text.dart` (`extractPdfText`) reads.
- Saved copies live at `users/{uid}/formCopies/{copyId}` with exactly the fields `formId`, `name`, `overrides`, `folderId`, `createdAt`, `updatedAt`. Rules limits: `name` 1–100 characters, `overrides` at most 300 keys, `formId` one of `form1 form3 form4a form4b form5a form5b form5c form7 form8`, `folderId` null or a string of at most 128 characters, `updatedAt == request.time`, `createdAt == request.time` on create and unchanged on update, `formId` unchanged on update. Only the owner (verified, active) may read, write or delete. Not the Dean, not a Coordinator.
- A copy stores **only overrides**: blocks whose text differs from the template default.
- User-facing wording in this plan is final copy. Use it verbatim.
- Every commit message ends with the trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Test commands: `flutter test <path>` from the repo root; rules tests with `cd rules-test && npm test` (needs the Firebase emulator, which `npm test` starts).

## Rulings made while planning (the spec is amended in Task 0)

- **R1: Form 1's official PDF is not rewritten.** Form 1 has no blank template today, on purpose: its filled version is built from live nominations with a variable number of researchers and e-signature status lines (see the `_Form1Card` doc comment in `forms_screen.dart`). The editable copy therefore gets a **new blank Form 1 layout** (`form1_template.dart`) with fixed slots: 5 researchers, 1 adviser, 3 panel members, Coordinator, Dean. Spec §4.3's "rewrite each builder, output unchanged" applies to the Phase 3 forms, which already have blank templates.
- **R2: The letterhead lines stay fixed.** These are *Republic of the Philippines*, the university name, *Research and Development* and the address line. Everything below them is editable, including the form code and the form title. The letterhead is the institution's identity; an edited letterhead would make an unofficial document.
- **R3: Blanks inside sentences are underscores in editable text**, e.g. `nominate Prof./Inst. ______ to be…`. That way the whole sentence stays one editable block. Standalone lines (date, each name over a signature line) are `blank` blocks that print a ruled line until filled.
- **R4: The electronic-completion notice is left off the editable Form 1.** *"Electronically completed in eThesisHub…"* would be false on a hand-edited copy.
- **R5: The unsaved-edits guard is a `GoRoute.onExit`**, not a `PopScope`. In go_router 17.5.0 `onExit` runs on `pop()` (the top-bar back arrow and the Android back handler both call it), on the router's `popRoute()` (browser back), and when a `go()` replaces the route (sidebar). A `PopScope` in this shell misses most of those.
- **R6: On narrow screens the Edit / Preview switch is a `SegmentedButton`,** not a `TabBar`/`TabBarView`. A `TabBarView` needs a bounded height, which the scrolling `PageShell` does not give.
- **R7:** Phase 1 shows **New copy / My copies on the Form 1 card only** (the only template). The rules already accept all nine form ids, so Phase 3 needs no rules change.

## File structure

| File | Responsibility |
|---|---|
| `lib/features/forms/editable/form_template.dart` (new) | `BlockKind`, `FormBlock`, `FormTemplate`, `FormText`: the editable-text model, no I/O |
| `lib/features/forms/editable/form_pdf.dart` (new) | `buildFormPdf(template, overrides)` and the `blankOr` layout helper |
| `lib/features/forms/editable/form1_template.dart` (new) | Form 1's blocks and blank layout (R1–R4) |
| `lib/features/forms/editable/form_templates.dart` (new) | `formTemplates` registry and `templateFor(formId)` |
| `lib/data/models/form_copy.dart` (new) | `FormCopy` model |
| `lib/data/repositories/form_copy_repository.dart` (new) | Firestore reads/writes for copies |
| `lib/providers/form_copy_providers.dart` (new) | repository + stream providers |
| `firestore.rules` (modify) | `match /formCopies/{copyId}` inside `match /users/{uid}` |
| `rules-test/rules.test.js` (modify) | emulator tests for the new rules |
| `lib/features/forms/editable/editor_services.dart` (new) | unsaved-edits flag, PDF sharer, preview builder, `confirmLeaveFormEditor` |
| `lib/features/forms/editable/form_copy_editor_screen.dart` (new) | the editor screen |
| `lib/core/routing/app_router.dart` (modify) | editor route with `onExit` |
| `lib/core/widgets/app_shell_host.dart` (modify) | top-bar title for the editor |
| `lib/features/forms/editable/name_dialog.dart` (new) | name prompt used by create and rename |
| `lib/features/forms/editable/form_copies_section.dart` (new) | New copy button + My copies list for one form |
| `lib/features/forms/forms_screen.dart` (modify) | `_FormCard.footer`, Form 1 card wiring |

---

### Task 0: Amend the spec with the planning rulings

**Files:**
- Modify: `docs/superpowers/specs/2026-09-24-editable-forms-and-my-files-design.md`
- Create: `docs/superpowers/plans/2026-09-24-editable-forms-phase1.md` (this file, already written)

**Interfaces:** none.

- [ ] **Step 1: Add decision E10 to the §2 table.** After the row that starts `| E9 |`, insert:

```markdown
| E10 | The letterhead lines (Republic of the Philippines, the university name, Research and Development, the address line) stay fixed; everything below them is editable, including the form code and title. | The letterhead is the institution's identity; an edited one would make an unofficial document. |
```

- [ ] **Step 2: Add a Form 1 note at the end of §4.3.** After the paragraph that starts `**Guarantee:**`, append:

```markdown
**Form 1 is the exception.** It has no blank template today, on purpose: its
filled PDF (`buildForm1Pdf`) is built from live nominations, with a variable
number of researchers and e-signature status lines. That builder is left
untouched. The editable copy gets its own blank Form 1 layout
(`form1_template.dart`) with fixed slots: 5 researchers, the adviser, 3 panel
members, the Coordinator and the Dean. Blanks inside sentences are underscores
in the editable text. The "Electronically completed in eThesisHub" notice is
left off, since it would be false on a hand-edited copy.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-09-24-editable-forms-and-my-files-design.md docs/superpowers/plans/2026-09-24-editable-forms-phase1.md
git status --short   # only those two paths may be staged
git commit -m "docs(plan): editable forms phase 1, and the rulings it made

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: The editable-text model and the generic PDF builder

**Files:**
- Create: `lib/features/forms/editable/form_template.dart`
- Create: `lib/features/forms/editable/form_pdf.dart`
- Test: `test/features/forms/editable/form_text_test.dart`
- Test: `test/features/forms/editable/form_pdf_test.dart`

**Interfaces:**
- Produces:
  - `enum BlockKind { text, blank }`
  - `class FormBlock { const FormBlock({required String id, required String label, String defaultText = '', BlockKind kind = BlockKind.text, bool multiline = false}); }`
  - `class FormTemplate { const FormTemplate({required String formId, required String title, required List<FormBlock> blocks, required List<pw.Widget> Function(FormText text) layout}); FormBlock? block(String id); Map<String, String> overridesFrom(Map<String, String> values); }`
  - `class FormText { FormText(FormTemplate template, [Map<String, String> overrides = const {}]); final Set<String> read; String of(String id); bool isBlank(String id); }`
  - `Future<Uint8List> buildFormPdf(FormTemplate template, Map<String, String> overrides)`
  - `pw.Widget blankOr(FormText text, String id, {double width = 160, pw.TextStyle? style})`

- [ ] **Step 1: Write the failing model test** at `test/features/forms/editable/form_text_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_template.dart';

final tpl = FormTemplate(
  formId: 'test',
  title: 'Test form',
  blocks: const [
    FormBlock(id: 'greeting', label: 'Greeting', defaultText: 'Sir/Madam:'),
    FormBlock(id: 'date', label: 'Date', kind: BlockKind.blank),
    FormBlock(
        id: 'body', label: 'Body', defaultText: 'Hello.', multiline: true),
  ],
  layout: (t) => [pw.Text(t.of('greeting'))],
);

void main() {
  group('FormText', () {
    test('a block with no override reads its default', () {
      expect(FormText(tpl).of('greeting'), 'Sir/Madam:');
    });

    test('an override replaces the default', () {
      expect(FormText(tpl, {'greeting': 'Dear Dean:'}).of('greeting'),
          'Dear Dean:');
    });

    test('an emptied text block reads as empty, not as its default', () {
      expect(FormText(tpl, {'greeting': ''}).of('greeting'), '');
    });

    test('a blank with no text is blank; typed text is not', () {
      expect(FormText(tpl).isBlank('date'), isTrue);
      final filled = FormText(tpl, {'date': '1 May 2026'});
      expect(filled.isBlank('date'), isFalse);
      expect(filled.of('date'), '1 May 2026');
    });

    test('a blank holding only spaces still prints as a blank line', () {
      expect(FormText(tpl, {'date': '   '}).isBlank('date'), isTrue);
    });

    test('a text block is never blank, even when emptied', () {
      expect(FormText(tpl, {'greeting': ''}).isBlank('greeting'), isFalse);
    });

    test('an override for a block the template no longer has is ignored', () {
      expect(FormText(tpl, {'gone': 'x'}).of('greeting'), 'Sir/Madam:');
    });

    test('asking for a block the template does not have is a bug', () {
      expect(() => FormText(tpl).of('nope'), throwsArgumentError);
    });

    test('records every block the layout asked for', () {
      final t = FormText(tpl);
      t.of('greeting');
      t.isBlank('date');
      expect(t.read, {'greeting', 'date'});
    });
  });

  group('overridesFrom', () {
    test('keeps only blocks whose text differs from the default', () {
      expect(
        tpl.overridesFrom(
            {'greeting': 'Sir/Madam:', 'date': '1 May', 'body': 'Changed.'}),
        {'date': '1 May', 'body': 'Changed.'},
      );
    });

    test('drops ids the template does not have', () {
      expect(tpl.overridesFrom({'gone': 'x'}), isEmpty);
    });

    test('keeps an emptied text block, since empty is not the default', () {
      expect(tpl.overridesFrom({'greeting': ''}), {'greeting': ''});
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/forms/editable/form_text_test.dart`
Expected: FAIL: `Target of URI doesn't exist: 'package:ethesishub/features/forms/editable/form_template.dart'`.

- [ ] **Step 3: Write the model** at `lib/features/forms/editable/form_template.dart`:

```dart
import 'package:pdf/widgets.dart' as pw;

/// Whether a block is ordinary wording or a line left for someone to fill.
enum BlockKind {
  /// Printed as its text. Emptied, it prints nothing.
  text,

  /// Printed as a ruled line while empty, and as its text once filled.
  blank,
}

/// One editable piece of a form's text.
class FormBlock {
  const FormBlock({
    required this.id,
    required this.label,
    this.defaultText = '',
    this.kind = BlockKind.text,
    this.multiline = false,
  });

  /// Stable once shipped: saved copies refer to blocks by this id.
  final String id;

  /// What the editor shows above the field.
  final String label;

  /// The form's own wording; empty for a blank.
  final String defaultText;
  final BlockKind kind;

  /// A paragraph rather than a single line.
  final bool multiline;
}

/// A form's editable text, in page order, and the layout that prints it.
class FormTemplate {
  const FormTemplate({
    required this.formId,
    required this.title,
    required this.blocks,
    required this.layout,
  });

  /// Also the `formId` stored on a saved copy, e.g. 'form1'.
  final String formId;

  /// The form's name as the app shows it.
  final String title;
  final List<FormBlock> blocks;

  /// The page content. Every string must come through [FormText]. Returned as
  /// a flat list so a long form can continue onto a second sheet.
  final List<pw.Widget> Function(FormText text) layout;

  FormBlock? block(String id) {
    for (final b in blocks) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// What a copy stores for [values]: only known blocks whose text differs
  /// from the default, so an untouched block keeps following the template.
  Map<String, String> overridesFrom(Map<String, String> values) => {
        for (final b in blocks)
          if (values.containsKey(b.id) && values[b.id] != b.defaultText)
            b.id: values[b.id]!,
      };
}

/// A template's text with one copy's overrides applied.
class FormText {
  FormText(this.template, [Map<String, String> overrides = const {}])
      : _overrides = overrides;

  final FormTemplate template;
  final Map<String, String> _overrides;

  /// Every block id the layout asked for, so a test can prove each block
  /// actually reaches the page.
  final Set<String> read = {};

  /// The block's text: the copy's override if it has one, else the default.
  /// An override for a block the template no longer has is simply never
  /// looked up. Asking for a block the template does not have is a bug in
  /// the layout and throws.
  String of(String id) {
    final block = template.block(id);
    if (block == null) {
      throw ArgumentError.value(
          id, 'id', 'no such block in ${template.formId}');
    }
    read.add(id);
    return _overrides[id] ?? block.defaultText;
  }

  /// True for a blank block with nothing typed in it (spaces count as
  /// nothing), which prints as a ruled line.
  bool isBlank(String id) =>
      template.block(id)?.kind == BlockKind.blank && of(id).trim().isEmpty;
}
```

- [ ] **Step 4: Run the model test and watch it pass**

Run: `flutter test test/features/forms/editable/form_text_test.dart`
Expected: PASS (12 tests).

- [ ] **Step 5: Write the failing PDF test** at `test/features/forms/editable/form_pdf_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';

import '../pdf_text.dart';

final tpl = FormTemplate(
  formId: 'test',
  title: 'Test form',
  blocks: const [
    FormBlock(id: 'greeting', label: 'Greeting', defaultText: 'Sir/Madam:'),
    FormBlock(id: 'signer', label: 'Signer', kind: BlockKind.blank),
  ],
  layout: (t) => [pw.Text(t.of('greeting')), blankOr(t, 'signer')],
);

void main() {
  // The forms embed Source Serif 4 via rootBundle, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prints the form wording when nothing is edited', () async {
    final text = extractPdfText(await buildFormPdf(tpl, const {}));
    expect(text, contains('Sir/Madam:'));
  });

  test('prints an edited block instead of its default', () async {
    final text = extractPdfText(
        await buildFormPdf(tpl, const {'greeting': 'Dear Dean Reyes:'}));
    expect(text, contains('Dear Dean Reyes:'));
    expect(text, isNot(contains('Sir/Madam:')));
  });

  test('a filled blank prints its text', () async {
    final text = extractPdfText(
        await buildFormPdf(tpl, const {'signer': 'MARIA SANTOS'}));
    expect(text, contains('MARIA SANTOS'));
  });
}
```

- [ ] **Step 6: Run it and watch it fail**

Run: `flutter test test/features/forms/editable/form_pdf_test.dart`
Expected: FAIL: `Target of URI doesn't exist: 'package:ethesishub/features/forms/editable/form_pdf.dart'`.

- [ ] **Step 7: Write the builder** at `lib/features/forms/editable/form_pdf.dart`:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// Renders [template] with a copy's [overrides] as a PDF: same page size,
/// margins, embedded font and uncompressed streams as every other form, so
/// `extractPdfText` can read it and it prints alongside them.
///
/// MultiPage, not Page: a `pw.Page` silently clips whatever does not fit,
/// and text a person has typed can run longer than the form's own wording.
Future<Uint8List> buildFormPdf(
  FormTemplate template,
  Map<String, String> overrides,
) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  final text = FormText(template, overrides);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (_) => template.layout(text),
    ),
  );
  return doc.save();
}

/// A block's text, or a ruled line while it is an empty blank.
pw.Widget blankOr(
  FormText text,
  String id, {
  double width = 160,
  pw.TextStyle? style,
}) {
  if (text.isBlank(id)) return ruledLine(width: width);
  return pw.Text(text.of(id), style: style);
}
```

- [ ] **Step 8: Run both tests and watch them pass**

Run: `flutter test test/features/forms/editable/`
Expected: PASS (15 tests). If a phrase assertion fails only because `extractPdfText` split it differently, open `test/features/forms/form3_pdf_test.dart` to see how its phrase assertions are written and match that style. Do not weaken what is being checked.

- [ ] **Step 9: Commit**

```bash
git add lib/features/forms/editable/form_template.dart lib/features/forms/editable/form_pdf.dart test/features/forms/editable/form_text_test.dart test/features/forms/editable/form_pdf_test.dart
git status --short   # confirm nothing else is staged
git commit -m "feat(forms): an editable-text model for forms, and a PDF builder for it

A form becomes a template of labelled text blocks with the form's own
wording as defaults; FormText applies a copy's overrides, and blank
blocks print a ruled line until filled. A copy stores only what differs
from the default.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The Form 1 template and the template registry

**Files:**
- Create: `lib/features/forms/editable/form1_template.dart`
- Create: `lib/features/forms/editable/form_templates.dart`
- Test: `test/features/forms/editable/form1_template_test.dart`

**Interfaces:**
- Consumes (Task 1): `FormBlock`, `BlockKind`, `FormTemplate`, `FormText`, `buildFormPdf`, `blankOr`. From `form_chrome.dart`: `formChrome({required String rdCode, required String formTitle, String? reference})`, `ruledLine({double width, double height})`.
- Produces:
  - `const int kForm1ResearcherSlots = 5;` and `const int kForm1PanelSlots = 3;`
  - `final FormTemplate form1Template` (formId `'form1'`, title `'Form 1 — Nomination of Thesis Adviser and Panel Members'`)
  - `final Map<String, FormTemplate> formTemplates` and `FormTemplate? templateFor(String formId)`

- [ ] **Step 1: Write the failing test** at `test/features/forms/editable/form1_template_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/forms/editable/form1_template.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/editable/form_templates.dart';

import '../pdf_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every block id is unique', () {
    final ids = form1Template.blocks.map((b) => b.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  // A block the layout never reads is a field the editor offers that
  // changes nothing on the page.
  test('every block reaches the page', () {
    final text = FormText(form1Template);
    form1Template.layout(text);
    expect(text.read, form1Template.blocks.map((b) => b.id).toSet());
  });

  test('offers five researcher lines and three panel lines', () {
    final ids = form1Template.blocks.map((b) => b.id).toSet();
    for (var i = 1; i <= kForm1ResearcherSlots; i++) {
      expect(ids, contains('researcher.$i'));
    }
    for (var i = 1; i <= kForm1PanelSlots; i++) {
      expect(ids, contains('conforme.panel.$i'));
    }
    expect(kForm1ResearcherSlots, 5);
    expect(kForm1PanelSlots, 3);
  });

  test('an unedited copy prints the form\'s own wording', () async {
    final text = extractPdfText(await buildFormPdf(form1Template, const {}));
    for (final phrase in [
      'Sir/Madam:',
      'Very truly yours,',
      'Conforme:',
      'Recommending Approval:',
      'Approved:',
      'RD-30-06/24-04',
    ]) {
      expect(text, contains(phrase), reason: phrase);
    }
  });

  test('leaves off the electronic-completion notice (ruling R4)', () async {
    final text = extractPdfText(await buildFormPdf(form1Template, const {}));
    expect(text, isNot(contains('Electronically completed')));
  });

  test('prints edited text in place of the wording it replaces', () async {
    final text = extractPdfText(await buildFormPdf(form1Template, const {
      'salutation': 'Dear Dean Reyes:',
      'researcher.1': 'MARIA SANTOS',
      'conforme.adviser': 'DR. JUAN CRUZ',
    }));
    expect(text, contains('Dear Dean Reyes:'));
    expect(text, contains('MARIA SANTOS'));
    expect(text, contains('DR. JUAN CRUZ'));
    expect(text, isNot(contains('Sir/Madam:')));
  });

  test('the registry finds Form 1 and nothing it does not have', () {
    expect(templateFor('form1'), same(form1Template));
    expect(templateFor('form99'), isNull);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/forms/editable/form1_template_test.dart`
Expected: FAIL: `Target of URI doesn't exist: …form1_template.dart`.

- [ ] **Step 3: Write the Form 1 template** at `lib/features/forms/editable/form1_template.dart`:

```dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// How many researcher signature lines the blank Form 1 offers.
const int kForm1ResearcherSlots = 5;

/// How many panel member Conforme lines the blank Form 1 offers.
const int kForm1PanelSlots = 3;

const _body = pw.TextStyle(fontSize: 11);
const _name = pw.TextStyle(fontSize: 11.5);
const _heading = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);
const _role = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);

/// Form 1 as a blank anyone can fill in and reword in the app.
///
/// Not the official filled Form 1 (`form1_pdf.dart`), which is built from a
/// thesis's live nominations and stays as it is. This one has fixed slots,
/// underscores where a sentence has a blank in it, and no
/// "Electronically completed" notice, since a hand-edited copy is not.
/// The letterhead lines are fixed; everything below them is editable.
final FormTemplate form1Template = FormTemplate(
  formId: 'form1',
  title: 'Form 1 — Nomination of Thesis Adviser and Panel Members',
  blocks: [
    const FormBlock(
        id: 'rdCode', label: 'Form code', defaultText: 'RD-30-06/24-04'),
    const FormBlock(
      id: 'formTitle',
      label: 'Form title',
      defaultText: 'Form 1. Nomination of Thesis Adviser and Panel Members',
    ),
    const FormBlock(id: 'date', label: 'Date', kind: BlockKind.blank),
    const FormBlock(
        id: 'dateLabel', label: 'Label under the date', defaultText: 'Date'),
    const FormBlock(
        id: 'addressee', label: 'Addressed to', defaultText: 'The Dean'),
    const FormBlock(
      id: 'addressCollege',
      label: 'Address: college',
      defaultText: 'College of ______________________',
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
    const FormBlock(
      id: 'adviserParagraph',
      label: 'Adviser paragraph',
      multiline: true,
      defaultText:
          'I/We have the honor to nominate Prof./Inst. '
          '______________________ to be my/our Undergraduate Thesis Adviser '
          'this __________ semester, Academic Year ______________.',
    ),
    const FormBlock(
      id: 'panelParagraph',
      label: 'Panel paragraph',
      multiline: true,
      defaultText:
          'Furthermore, I am/we are nominating Prof./Inst. '
          '______________________, ______________________ and '
          '______________________ to be my/our panel members.',
    ),
    const FormBlock(
      id: 'closing',
      label: 'Closing line',
      defaultText: 'Your approval on this matter is highly appreciated.',
    ),
    const FormBlock(
        id: 'valediction', label: 'Sign-off', defaultText: 'Very truly yours,'),
    for (var i = 1; i <= kForm1ResearcherSlots; i++) ...[
      FormBlock(
          id: 'researcher.$i',
          label: 'Researcher $i: name',
          kind: BlockKind.blank),
      FormBlock(
        id: 'researcher.$i.role',
        label: 'Researcher $i: role',
        defaultText: i == 1 ? 'Researcher · Group Leader' : 'Researcher',
      ),
    ],
    const FormBlock(
        id: 'conformeHeading',
        label: 'Conforme heading',
        defaultText: 'Conforme:'),
    const FormBlock(
        id: 'conforme.adviser',
        label: 'Thesis adviser: name',
        kind: BlockKind.blank),
    const FormBlock(
        id: 'conforme.adviser.role',
        label: 'Thesis adviser: role',
        defaultText: 'Thesis Adviser'),
    for (var i = 1; i <= kForm1PanelSlots; i++) ...[
      FormBlock(
          id: 'conforme.panel.$i',
          label: 'Panel member $i: name',
          kind: BlockKind.blank),
      FormBlock(
          id: 'conforme.panel.$i.role',
          label: 'Panel member $i: role',
          defaultText: 'Panel Member'),
    ],
    const FormBlock(
        id: 'recommendingHeading',
        label: 'Recommending heading',
        defaultText: 'Recommending Approval:'),
    const FormBlock(
        id: 'coordinator',
        label: 'Research Coordinator: name',
        kind: BlockKind.blank),
    const FormBlock(
        id: 'coordinator.role',
        label: 'Research Coordinator: title',
        defaultText: 'College Research Coordinator'),
    const FormBlock(
        id: 'approvedHeading',
        label: 'Approval heading',
        defaultText: 'Approved:'),
    const FormBlock(id: 'dean', label: 'Dean: name', kind: BlockKind.blank),
    const FormBlock(
        id: 'dean.role',
        label: 'Dean: title',
        defaultText: 'Dean, College of ______________'),
    const FormBlock(
      id: 'coreValues',
      label: 'Footer',
      defaultText:
          'Integrity  ·  Social Justice  ·  Discipline  ·  Academic Excellence',
    ),
  ],
  layout: _layout,
);

List<pw.Widget> _layout(FormText t) => [
      formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
      pw.SizedBox(height: 12),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: blankOr(t, 'date', width: 140, style: _body),
      ),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t.of('dateLabel'),
            style: const pw.TextStyle(fontSize: 8)),
      ),
      pw.SizedBox(height: 10),
      pw.Text(t.of('addressee'), style: _body),
      pw.Text(t.of('addressCollege'), style: _body),
      pw.Text(t.of('addressUniversity'), style: _body),
      pw.Text(t.of('addressCity'), style: _body),
      pw.SizedBox(height: 10),
      pw.Text(t.of('salutation'), style: _body),
      pw.SizedBox(height: 6),
      _indented(t.of('adviserParagraph')),
      pw.SizedBox(height: 6),
      _indented(t.of('panelParagraph')),
      pw.SizedBox(height: 6),
      _indented(t.of('closing')),
      pw.SizedBox(height: 12),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t.of('valediction'), style: _body),
      ),
      for (var i = 1; i <= kForm1ResearcherSlots; i++)
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.SizedBox(height: 18),
              blankOr(t, 'researcher.$i', width: 200, style: _name),
              pw.Text(t.of('researcher.$i.role'), style: _role),
            ],
          ),
        ),
      pw.SizedBox(height: 14),
      pw.Text(t.of('conformeHeading'), style: _heading),
      _signatureSlot(t, 'conforme.adviser'),
      for (var i = 1; i <= kForm1PanelSlots; i++)
        _signatureSlot(t, 'conforme.panel.$i'),
      pw.Text(t.of('recommendingHeading'), style: _heading),
      _signatureSlot(t, 'coordinator'),
      pw.Text(t.of('approvedHeading'), style: _heading),
      _signatureSlot(t, 'dean'),
      pw.SizedBox(height: 8),
      pw.Text(
        t.of('coreValues'),
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    ];

pw.Widget _indented(String paragraph) => pw.Padding(
      padding: const pw.EdgeInsets.only(left: 30),
      child: pw.Text(paragraph,
          style: _body, textAlign: pw.TextAlign.justify),
    );

/// A name over its role: a ruled line where the name goes until one is
/// typed. The role is the block `'$id.role'`.
pw.Widget _signatureSlot(FormText t, String id) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 22),
          blankOr(t, id, width: 220, style: _name),
          pw.Text(t.of('$id.role'), style: _role),
        ],
      ),
    );
```

- [ ] **Step 4: Write the registry** at `lib/features/forms/editable/form_templates.dart`:

```dart
import 'package:ethesishub/features/forms/editable/form1_template.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';

/// Every form that can be edited in the app, by id. Phase 1 has Form 1 only;
/// the other eight join as their builders are converted (spec §11, Phase 3).
final Map<String, FormTemplate> formTemplates = {
  form1Template.formId: form1Template,
};

/// The template for [formId], or null for a form that cannot be edited
/// (never shipped, or removed in an update).
FormTemplate? templateFor(String formId) => formTemplates[formId];
```

- [ ] **Step 5: Run the new test and the untouched official Form 1 tests**

Run: `flutter test test/features/forms/editable/form1_template_test.dart test/features/forms/form1_pdf_test.dart test/features/forms/form1_data_test.dart`
Expected: all PASS. The two `form1_*` suites pass because nothing they cover was touched.

- [ ] **Step 6: Commit**

```bash
git add lib/features/forms/editable/form1_template.dart lib/features/forms/editable/form_templates.dart test/features/forms/editable/form1_template_test.dart
git status --short
git commit -m "feat(forms): a blank, editable Form 1

Fixed slots for five researchers, the adviser, three panel members, the
Coordinator and the Dean; underscores where a sentence has a blank; the
letterhead fixed and everything below it editable. The official filled
Form 1 is untouched.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The saved-copy model, repository and providers

**Files:**
- Create: `lib/data/models/form_copy.dart`
- Create: `lib/data/repositories/form_copy_repository.dart`
- Create: `lib/providers/form_copy_providers.dart`
- Test: `test/data/repositories/form_copy_repository_test.dart`

**Interfaces:**
- Consumes: `firestoreProvider`, `authStateProvider` from `lib/providers/auth_providers.dart`.
- Produces:
  - `class FormCopy { final String id, formId, name; final Map<String, String> overrides; final String? folderId; final DateTime? createdAt, updatedAt; factory FormCopy.fromMap(String id, Map<String, dynamic> m); }`
  - `const int kFormCopyNameMax = 100;`
  - `class FormCopyRepository { FormCopyRepository(FirebaseFirestore db); Stream<List<FormCopy>> watchCopies(String uid, {required String formId}); Stream<FormCopy?> watchCopy(String uid, String copyId); Future<String> create({required String uid, required String formId, required String name}); Future<void> saveOverrides({required String uid, required String copyId, required Map<String, String> overrides}); Future<void> rename({required String uid, required String copyId, required String name}); Future<void> delete({required String uid, required String copyId}); }`
  - `final formCopyRepositoryProvider = Provider<FormCopyRepository>`
  - `final myFormCopiesProvider = StreamProvider.family<List<FormCopy>, String>` (arg: formId)
  - `final formCopyProvider = StreamProvider.family<FormCopy?, String>` (arg: copyId)

- [ ] **Step 1: Write the failing test** at `test/data/repositories/form_copy_repository_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/data/repositories/form_copy_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FormCopyRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FormCopyRepository(db);
  });

  Future<void> seed(String uid, String id, String formId, DateTime updated) =>
      db.doc('users/$uid/formCopies/$id').set({
        'formId': formId,
        'name': id,
        'overrides': <String, String>{},
        'folderId': null,
        'createdAt': Timestamp.fromDate(updated),
        'updatedAt': Timestamp.fromDate(updated),
      });

  test('create writes an unedited copy under the user and returns its id',
      () async {
    final id = await repo.create(
        uid: 'u1', formId: 'form1', name: '  Group 3 – Santos  ');
    final data = (await db.doc('users/u1/formCopies/$id').get()).data()!;
    expect(data['formId'], 'form1');
    expect(data['name'], 'Group 3 – Santos', reason: 'the name is trimmed');
    expect(data['overrides'], isEmpty);
    expect(data['folderId'], isNull);
    expect(data['createdAt'], isA<Timestamp>());
    expect(data['updatedAt'], isA<Timestamp>());
    expect(data.keys.toSet(), {
      'formId', 'name', 'overrides', 'folderId', 'createdAt', 'updatedAt'
    }, reason: 'exactly the fields the rules allow');
  });

  test('a name must be 1 to $kFormCopyNameMax characters', () async {
    expect(() => repo.create(uid: 'u1', formId: 'form1', name: '   '),
        throwsArgumentError);
    expect(
        () => repo.create(
            uid: 'u1', formId: 'form1', name: 'x' * (kFormCopyNameMax + 1)),
        throwsArgumentError);
  });

  test('watchCopies lists only this form\'s copies, newest first', () async {
    await seed('u1', 'old', 'form1', DateTime(2026, 9, 1));
    await seed('u1', 'new', 'form1', DateTime(2026, 9, 3));
    await seed('u1', 'other-form', 'form3', DateTime(2026, 9, 4));
    await seed('u2', 'someone-else', 'form1', DateTime(2026, 9, 5));

    final copies = await repo.watchCopies('u1', formId: 'form1').first;
    expect(copies.map((c) => c.id), ['new', 'old']);
  });

  test('watchCopy reads one copy, and null once it is gone', () async {
    await seed('u1', 'c1', 'form1', DateTime(2026, 9, 1));
    expect((await repo.watchCopy('u1', 'c1').first)!.name, 'c1');
    await repo.delete(uid: 'u1', copyId: 'c1');
    expect(await repo.watchCopy('u1', 'c1').first, isNull);
  });

  test('saveOverrides replaces the stored edits', () async {
    await seed('u1', 'c1', 'form1', DateTime(2026, 9, 1));
    await repo.saveOverrides(
        uid: 'u1', copyId: 'c1', overrides: {'salutation': 'Dear Dean:'});
    await repo.saveOverrides(
        uid: 'u1', copyId: 'c1', overrides: {'closing': 'Thank you.'});
    final data = (await db.doc('users/u1/formCopies/c1').get()).data()!;
    expect(data['overrides'], {'closing': 'Thank you.'});
  });

  test('rename trims the new name and refuses an empty one', () async {
    await seed('u1', 'c1', 'form1', DateTime(2026, 9, 1));
    await repo.rename(uid: 'u1', copyId: 'c1', name: ' Renamed ');
    expect((await db.doc('users/u1/formCopies/c1').get()).data()!['name'],
        'Renamed');
    expect(() => repo.rename(uid: 'u1', copyId: 'c1', name: ''),
        throwsArgumentError);
  });

  test('fromMap ignores an override that is not text', () {
    final copy = FormCopy.fromMap('c1', {
      'formId': 'form1',
      'name': 'n',
      'overrides': {'salutation': 'Dear Dean:', 'bad': 3},
      'folderId': null,
    });
    expect(copy.overrides, {'salutation': 'Dear Dean:'});
    expect(copy.updatedAt, isNull);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/repositories/form_copy_repository_test.dart`
Expected: FAIL: `Target of URI doesn't exist: …form_copy.dart`.

- [ ] **Step 3: Write the model** at `lib/data/models/form_copy.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// One person's saved copy of a form: which form, what they called it, and
/// the text they changed. Stored at `users/{uid}/formCopies/{id}`, readable
/// only by that person (see `firestore.rules`).
class FormCopy {
  const FormCopy({
    required this.id,
    required this.formId,
    required this.name,
    required this.overrides,
    this.folderId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String formId;
  final String name;

  /// Only the blocks whose text differs from the form's own wording.
  final Map<String, String> overrides;

  /// The My files folder this copy sits in (spec Phase 2). Always null until
  /// that phase ships.
  final String? folderId;

  /// Null only in the moment between a local write and the server stamping
  /// its time.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory FormCopy.fromMap(String id, Map<String, dynamic> m) {
    final raw = (m['overrides'] as Map?) ?? const {};
    return FormCopy(
      id: id,
      formId: m['formId'] as String? ?? '',
      name: m['name'] as String? ?? '',
      overrides: {
        for (final e in raw.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      },
      folderId: m['folderId'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
```

- [ ] **Step 4: Write the repository** at `lib/data/repositories/form_copy_repository.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/form_copy.dart';

/// The longest copy name `firestore.rules` accepts.
const int kFormCopyNameMax = 100;

/// A person's saved form copies, at `users/{uid}/formCopies`.
class FormCopyRepository {
  FormCopyRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _copies(String uid) =>
      _db.collection('users').doc(uid).collection('formCopies');

  /// This person's copies of [formId], most recently edited first.
  ///
  /// Filtered and sorted here rather than in the query: one person holds a
  /// handful of copies, and a `where` + `orderBy` pair would need a
  /// composite index deployed before the screen could load at all.
  Stream<List<FormCopy>> watchCopies(String uid, {required String formId}) {
    return _copies(uid).snapshots().map((s) {
      final copies = [
        for (final d in s.docs) FormCopy.fromMap(d.id, d.data()),
      ].where((c) => c.formId == formId).toList();
      copies.sort((a, b) {
        final at = a.updatedAt;
        final bt = b.updatedAt;
        // Not yet stamped means written a moment ago: newest.
        if (at == null && bt == null) return 0;
        if (at == null) return -1;
        if (bt == null) return 1;
        return bt.compareTo(at);
      });
      return copies;
    });
  }

  /// One copy, or null once it has been deleted.
  Stream<FormCopy?> watchCopy(String uid, String copyId) =>
      _copies(uid).doc(copyId).snapshots().map(
            (d) => d.exists ? FormCopy.fromMap(d.id, d.data()!) : null,
          );

  /// Creates an unedited copy and returns its id.
  Future<String> create({
    required String uid,
    required String formId,
    required String name,
  }) async {
    final ref = _copies(uid).doc();
    await ref.set({
      'formId': formId,
      'name': _checkedName(name),
      'overrides': <String, String>{},
      'folderId': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Replaces the copy's stored edits with [overrides].
  Future<void> saveOverrides({
    required String uid,
    required String copyId,
    required Map<String, String> overrides,
  }) =>
      _copies(uid).doc(copyId).update({
        'overrides': overrides,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> rename({
    required String uid,
    required String copyId,
    required String name,
  }) =>
      _copies(uid).doc(copyId).update({
        'name': _checkedName(name),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> delete({required String uid, required String copyId}) =>
      _copies(uid).doc(copyId).delete();

  static String _checkedName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > kFormCopyNameMax) {
      throw ArgumentError.value(
          name, 'name', 'must be 1 to $kFormCopyNameMax characters');
    }
    return trimmed;
  }
}
```

- [ ] **Step 5: Write the providers** at `lib/providers/form_copy_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/data/repositories/form_copy_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final formCopyRepositoryProvider = Provider<FormCopyRepository>(
  (ref) => FormCopyRepository(ref.watch(firestoreProvider)),
);

/// The signed-in person's copies of one form (the family argument is the
/// form id), newest first.
///
/// Awaits the auth state rather than reading its current value: while auth
/// is still settling that value is null, which would read as "no copies"
/// and flash an empty list, the same race `currentUserProvider` avoids.
final myFormCopiesProvider =
    StreamProvider.family<List<FormCopy>, String>((ref, formId) async* {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref
      .watch(formCopyRepositoryProvider)
      .watchCopies(user.uid, formId: formId);
});

/// One of the signed-in person's copies (the family argument is the copy
/// id); null once deleted. Awaits auth for the same reason as above: a
/// copy that merely has not loaded yet must not read as "no longer exists".
final formCopyProvider =
    StreamProvider.family<FormCopy?, String>((ref, copyId) async* {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    yield null;
    return;
  }
  yield* ref.watch(formCopyRepositoryProvider).watchCopy(user.uid, copyId);
});
```

- [ ] **Step 6: Run the test and watch it pass**

Run: `flutter test test/data/repositories/form_copy_repository_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/data/models/form_copy.dart lib/data/repositories/form_copy_repository.dart lib/providers/form_copy_providers.dart test/data/repositories/form_copy_repository_test.dart
git status --short
git commit -m "feat(forms): save, list, rename and delete personal form copies

Copies live at users/{uid}/formCopies with only the edited blocks
stored; the providers await auth so a loading copy never reads as a
missing one.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Firestore rules for form copies

**Files:**
- Modify: `firestore.rules` (inside `match /users/{uid} { … }`, just before its closing brace)
- Test: `rules-test/rules.test.js` (new tests just before `test.after(`)

**Interfaces:**
- Consumes: rules helper `verified()` (already defined near the top of `firestore.rules`); JS helpers `env`, `asDefenceUser(uid, email)` (memoised: use it for **every** authenticated context in these tests, because a second non-memoised context in one test throws "Firestore has already been started"), `seedUser(uid, role, email)`, and the Firestore functions already imported at the top of `rules.test.js` (`doc`, `getDoc`, `getDocs`, `collection`, `setDoc`, `updateDoc`, `deleteDoc`, `serverTimestamp`, `Timestamp`).
- Produces: the security boundary for `users/{uid}/formCopies/{copyId}` described in Global Constraints.

- [ ] **Step 1: Write the failing rules tests.** In `rules-test/rules.test.js`, insert immediately before the line `test.after(async () => {`:

```js
// --- Personal form copies (editable forms, Phase 1) --------------------------
//
// users/{uid}/formCopies/{copyId}: one person's working copies. Owner-only:
// not the Dean, not a Coordinator. asDefenceUser (memoised) for every
// context; a second fresh context in one test throws "Firestore has already
// been started".

const FC_OWNER = ["fc-owner", "fcowner@isufst.edu.ph"];
const FC_OTHER = ["fc-other", "fcother@isufst.edu.ph"];

function formCopy(overrides = {}) {
  return {
    formId: "form1",
    name: "Group 3 – Santos",
    overrides: {},
    folderId: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

async function seedFormCopy(uid, copyId, data = {}) {
  const at = Timestamp.fromDate(new Date("2026-09-01T00:00:00Z"));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${uid}/formCopies/${copyId}`), {
      formId: "form1", name: "Seeded", overrides: {}, folderId: null,
      createdAt: at, updatedAt: at,
      ...data,
    });
  });
}

test("the owner may create a valid form copy", async () => {
  const owner = asDefenceUser(...FC_OWNER);
  await assertSucceeds(
    setDoc(doc(owner, "users/fc-owner/formCopies/c-create"), formCopy()));
});

test("the owner may read and list their own form copies", async () => {
  await seedFormCopy("fc-owner", "c-read");
  const owner = asDefenceUser(...FC_OWNER);
  await assertSucceeds(getDoc(doc(owner, "users/fc-owner/formCopies/c-read")));
  await assertSucceeds(getDocs(collection(owner, "users/fc-owner/formCopies")));
});

test("nobody else may read a form copy, not even a coordinator or dean",
    async () => {
  await seedFormCopy("fc-owner", "c-private");
  await seedUser("fc-coord", "coordinator", "fccoord@isufst.edu.ph");
  await seedUser("fc-dean", "dean", "fcdean@isufst.edu.ph");
  for (const [uid, email] of [
    FC_OTHER,
    ["fc-coord", "fccoord@isufst.edu.ph"],
    ["fc-dean", "fcdean@isufst.edu.ph"],
  ]) {
    const db = asDefenceUser(uid, email);
    await assertFails(getDoc(doc(db, "users/fc-owner/formCopies/c-private")));
    await assertFails(getDocs(collection(db, "users/fc-owner/formCopies")));
  }
});

test("nobody may create a form copy in someone else's account", async () => {
  const other = asDefenceUser(...FC_OTHER);
  await assertFails(
    setDoc(doc(other, "users/fc-owner/formCopies/c-planted"), formCopy()));
});

test("a form copy must name one of the nine forms", async () => {
  const owner = asDefenceUser(...FC_OWNER);
  await assertFails(setDoc(doc(owner, "users/fc-owner/formCopies/c-bad-form"),
    formCopy({ formId: "form99" })));
  await assertSucceeds(setDoc(doc(owner, "users/fc-owner/formCopies/c-form8"),
    formCopy({ formId: "form8" })));
});

test("a form copy may carry no extra fields and must carry all six",
    async () => {
  const owner = asDefenceUser(...FC_OWNER);
  await assertFails(setDoc(doc(owner, "users/fc-owner/formCopies/c-extra"),
    formCopy({ sharedWith: ["fc-other"] })));
  const missing = formCopy();
  delete missing.folderId;
  await assertFails(
    setDoc(doc(owner, "users/fc-owner/formCopies/c-missing"), missing));
});

test("a form copy's name must be 1 to 100 characters", async () => {
  const owner = asDefenceUser(...FC_OWNER);
  await assertFails(setDoc(doc(owner, "users/fc-owner/formCopies/c-n0"),
    formCopy({ name: "" })));
  await assertFails(setDoc(doc(owner, "users/fc-owner/formCopies/c-n101"),
    formCopy({ name: "x".repeat(101) })));
  await assertSucceeds(setDoc(doc(owner, "users/fc-owner/formCopies/c-n100"),
    formCopy({ name: "x".repeat(100) })));
});

test("a form copy holds at most 300 edited blocks", async () => {
  const owner = asDefenceUser(...FC_OWNER);
  const blocks = (n) =>
    Object.fromEntries(Array.from({ length: n }, (_, i) => [`b${i}`, "x"]));
  await assertFails(setDoc(doc(owner, "users/fc-owner/formCopies/c-301"),
    formCopy({ overrides: blocks(301) })));
  await assertSucceeds(setDoc(doc(owner, "users/fc-owner/formCopies/c-300"),
    formCopy({ overrides: blocks(300) })));
});

test("a form copy's times must be the server's", async () => {
  const owner = asDefenceUser(...FC_OWNER);
  const past = Timestamp.fromDate(new Date("2020-01-01T00:00:00Z"));
  await assertFails(setDoc(doc(owner, "users/fc-owner/formCopies/c-t1"),
    formCopy({ updatedAt: past })));
  await assertFails(setDoc(doc(owner, "users/fc-owner/formCopies/c-t2"),
    formCopy({ createdAt: past })));
});

test("the owner may save edits but not rewrite createdAt or formId",
    async () => {
  await seedFormCopy("fc-owner", "c-upd");
  const owner = asDefenceUser(...FC_OWNER);
  const ref = doc(owner, "users/fc-owner/formCopies/c-upd");
  await assertSucceeds(updateDoc(ref, {
    overrides: { salutation: "Dear Dean:" }, updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(ref, {
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(ref, {
    formId: "form3", updatedAt: serverTimestamp(),
  }));
});

test("nobody else may change or delete a form copy; the owner may delete",
    async () => {
  await seedFormCopy("fc-owner", "c-del");
  const other = asDefenceUser(...FC_OTHER);
  await assertFails(
    updateDoc(doc(other, "users/fc-owner/formCopies/c-del"), {
      name: "Hijacked", updatedAt: serverTimestamp(),
    }));
  await assertFails(deleteDoc(doc(other, "users/fc-owner/formCopies/c-del")));
  const owner = asDefenceUser(...FC_OWNER);
  await assertSucceeds(
    deleteDoc(doc(owner, "users/fc-owner/formCopies/c-del")));
});
```

- [ ] **Step 2: Run the rules tests and watch the new ones fail**

Run: `cd rules-test && npm test`
Expected: the owner-allowed tests FAIL (no rule grants anything under `formCopies`); the deny-only tests pass. That pattern is correct: with no rule, everything is denied.

- [ ] **Step 3: Add the rule.** In `firestore.rules`, find this unique text inside `match /users/{uid}`:

```
                                    'nominableAsAdviser', 'nominableAsPanelist']);

      allow delete: if false;
    }

    match /facultyInvites/{email} {
```

and replace it with:

```
                                    'nominableAsAdviser', 'nominableAsPanelist']);

      allow delete: if false;

      // Personal form copies (editable forms, spec 2026-09-24). One person's
      // working copies: readable and writable by that person alone. Not the
      // Dean, not a Coordinator; these are not thesis records. Outside the
      // theses block, so none of this counts against its expression budget.
      match /formCopies/{copyId} {
        function mine() {
          return verified() && request.auth.uid == uid;
        }

        function validCopy(d) {
          return d.keys().hasOnly(['formId', 'name', 'overrides', 'folderId',
                                   'createdAt', 'updatedAt'])
              && d.keys().hasAll(['formId', 'name', 'overrides', 'folderId',
                                  'createdAt', 'updatedAt'])
              && d.formId in ['form1', 'form3', 'form4a', 'form4b', 'form5a',
                              'form5b', 'form5c', 'form7', 'form8']
              && d.name is string && d.name.size() >= 1 && d.name.size() <= 100
              && d.overrides is map && d.overrides.size() <= 300
              && (d.folderId == null
                  || (d.folderId is string && d.folderId.size() <= 128))
              && d.updatedAt == request.time;
        }

        allow read: if mine();
        allow create: if mine()
                      && validCopy(request.resource.data)
                      && request.resource.data.createdAt == request.time;
        allow update: if mine()
                      && validCopy(request.resource.data)
                      && request.resource.data.createdAt == resource.data.createdAt
                      && request.resource.data.formId == resource.data.formId;
        allow delete: if mine();
      }
    }

    match /facultyInvites/{email} {
```

- [ ] **Step 4: Run the rules tests and watch them all pass**

Run: `cd rules-test && npm test`
Expected: every test passes, the existing ones included (the file had 283 passing before this task; now 283 + 11).

- [ ] **Step 5: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git status --short
git commit -m "feat(rules): owner-only personal form copies

users/{uid}/formCopies: the owner alone reads and writes; exact field
set, one of the nine form ids, name 1-100, at most 300 edited blocks,
server-set times, createdAt and formId fixed after create.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

> **Deploy reminder for the person running the app:** `firebase deploy --only firestore:rules` before testing copies on a device. Without it every save is refused with `permission-denied`.

---

### Task 5: The editor screen, its route and the leave guard

**Files:**
- Create: `lib/features/forms/editable/editor_services.dart`
- Create: `lib/features/forms/editable/form_copy_editor_screen.dart`
- Modify: `lib/core/routing/app_router.dart` (one route after `GoRoute(path: '/forms', …)`, plus imports)
- Modify: `lib/core/widgets/app_shell_host.dart` (`shellTitleFor`)
- Test: `test/features/forms/editable/form_copy_editor_screen_test.dart`
- Test: `test/core/widgets/app_shell_host_test.dart` (one test in the `shellTitleFor` group)

**Interfaces:**
- Consumes: Task 1 (`FormBlock`, `BlockKind`, `FormTemplate`, `FormText`, `buildFormPdf`), Task 2 (`templateFor`), Task 3 (`FormCopy`, `formCopyRepositoryProvider`, `formCopyProvider`); `signedInUidProvider` (`lib/providers/auth_providers.dart`); `confirmAction(BuildContext, {required String title, required String message, required String confirmLabel, String cancelLabel = 'Cancel', Key? confirmKey})` (`lib/core/widgets/confirm.dart`); `PageShell({required List<Widget> children, String? kicker, String? title, String? subtitle, List<Widget> actions, double maxWidth})` and `Gap` (`lib/core/widgets/page_shell.dart`); `EmptyState`, `ErrorState`, `LoadingState.page` (`lib/core/widgets/states.dart`); `FormRow({required String label, required Widget child, String? hint})` (`lib/core/components/document.dart`); `AppTokens` (`lib/core/theme/app_tokens.dart`).
- Produces:
  - `final unsavedFormEditsProvider = StateProvider<bool>`
  - `typedef PdfSharer = Future<void> Function(Uint8List bytes, String filename);` and `final pdfSharerProvider = Provider<PdfSharer>`
  - `typedef FormPreviewBuilder = Widget Function(Key key, Future<Uint8List> Function() build);` and `final formPreviewBuilderProvider = Provider<FormPreviewBuilder>`
  - `Future<bool> confirmLeaveFormEditor(BuildContext context, GoRouterState state)`
  - `class FormCopyEditorScreen extends ConsumerStatefulWidget { const FormCopyEditorScreen({Key? key, required String formId, required String copyId}); }`
  - `const double kEditorSideBySideFrom = 860;`, `const Duration kPreviewDebounce = Duration(milliseconds: 400);`
  - Route `/forms/:formId/copies/:copyId`; top-bar title `Edit form`.
  - Widget keys used by tests: `field-<blockId>`, `resetField-<blockId>`, `saveCopy`, `downloadCopy`, `resetAllCopy`, `confirmResetAll`, `confirmLeaveEditor`, `editorFields`, `editorPaneSwitch`, `formUnavailable`, `copyMissing`, `saveError`, `previewError`.

- [ ] **Step 1: Write the failing editor test** at `test/features/forms/editable/form_copy_editor_screen_test.dart`:

```dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/features/forms/editable/editor_services.dart';
import 'package:ethesishub/features/forms/editable/form_copy_editor_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

import '../pdf_text.dart';

class Shared {
  Uint8List? bytes;
  String? filename;
}

Future<FakeFirebaseFirestore> seedCopy({
  Map<String, String> overrides = const {},
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('u1').set({
    'fullName': 'Test User',
    'email': 't@isufst.edu.ph',
    'role': 'faculty',
    'active': true,
  });
  final at = Timestamp.fromDate(DateTime(2026, 9, 1));
  await db.doc('users/u1/formCopies/c1').set({
    'formId': 'form1',
    'name': 'Group 3 – Santos',
    'overrides': overrides,
    'folderId': null,
    'createdAt': at,
    'updatedAt': at,
  });
  return db;
}

/// Starts on '/forms' and pushes the editor, so leaving it is a real pop,
/// the way the top-bar arrow and the Android back both leave it.
Future<(GoRouter, Set<Key>, Shared)> pumpEditor(
  WidgetTester tester,
  FakeFirebaseFirestore db, {
  String location = '/forms/form1/copies/c1',
  Size size = const Size(1400, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final previews = <Key>{};
  final shared = Shared();
  final router = GoRouter(
    initialLocation: '/forms',
    routes: [
      GoRoute(
        path: '/forms',
        builder: (_, _) =>
            const Scaffold(body: Text('forms home', key: Key('formsHome'))),
      ),
      GoRoute(
        path: '/forms/:formId/copies/:copyId',
        onExit: confirmLeaveFormEditor,
        builder: (_, s) => Scaffold(
          body: FormCopyEditorScreen(
            formId: s.pathParameters['formId']!,
            copyId: s.pathParameters['copyId']!,
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'u1', email: 't@isufst.edu.ph', isEmailVerified: true),
      )),
      // Rasterising a PDF needs the platform; record each preview instead.
      formPreviewBuilderProvider.overrideWithValue((key, build) {
        previews.add(key);
        return KeyedSubtree(
          key: key,
          child: const Text('preview stub', key: Key('previewStub')),
        );
      }),
      pdfSharerProvider.overrideWithValue((bytes, filename) async {
        shared
          ..bytes = bytes
          ..filename = filename;
      }),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  router.push(location);
  await tester.pumpAndSettle();
  return (router, previews, shared);
}

String fieldText(WidgetTester tester, String blockId) => tester
    .widget<TextField>(find.byKey(Key('field-$blockId')))
    .controller!
    .text;

/// Fake Firestore writes and PDF font loading finish on the real event
/// loop, not the test's fake clock. With [done], polls until it holds (up
/// to 5 s); without it, gives the loop a short real-time turn.
Future<void> settleReal(WidgetTester tester, [bool Function()? done]) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 50; i++) {
      if (done == null ? i >= 3 : done()) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens a copy with its saved edits in the fields',
      (tester) async {
    final db = await seedCopy(overrides: {'salutation': 'Dear Dean Reyes:'});
    await pumpEditor(tester, db);

    expect(fieldText(tester, 'salutation'), 'Dear Dean Reyes:');
    expect(fieldText(tester, 'addressee'), 'The Dean',
        reason: 'an unedited block shows the form\'s own wording');
    expect(find.text('Group 3 – Santos'), findsOneWidget);
    expect(find.text('All changes saved'), findsOneWidget);
  });

  testWidgets('Save stays off until something changes', (tester) async {
    await pumpEditor(tester, await seedCopy());
    final save = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('saveCopy')));
    expect(save.onPressed, isNull);
  });

  testWidgets('saving stores only the blocks that were changed',
      (tester) async {
    final db = await seedCopy();
    await pumpEditor(tester, db);

    await tester.enterText(
        find.byKey(const Key('field-salutation')), 'Dear Dean:');
    await tester.pump();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.byKey(const Key('saveCopy')));
    await settleReal(tester);

    final data = (await db.doc('users/u1/formCopies/c1').get()).data()!;
    expect(data['overrides'], {'salutation': 'Dear Dean:'});
    expect(find.text('All changes saved'), findsOneWidget);
  });

  testWidgets('resetting a field puts back the form\'s wording, and saving '
      'then stores nothing for it', (tester) async {
    final db = await seedCopy(overrides: {'salutation': 'Dear Dean:'});
    await pumpEditor(tester, db);

    await tester.tap(find.byKey(const Key('resetField-salutation')));
    await tester.pump();
    expect(fieldText(tester, 'salutation'), 'Sir/Madam:');

    await tester.tap(find.byKey(const Key('saveCopy')));
    await settleReal(tester);
    final data = (await db.doc('users/u1/formCopies/c1').get()).data()!;
    expect(data['overrides'], isEmpty);
  });

  testWidgets('Reset all asks first, then puts every field back',
      (tester) async {
    await pumpEditor(tester,
        await seedCopy(overrides: {'salutation': 'Dear Dean:', 'closing': 'x'}));

    await tester.tap(find.byKey(const Key('resetAllCopy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmResetAll')));
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'salutation'), 'Sir/Madam:');
    expect(fieldText(tester, 'closing'),
        'Your approval on this matter is highly appreciated.');
  });

  testWidgets('the preview is rebuilt only once typing pauses',
      (tester) async {
    final (_, previews, _) = await pumpEditor(tester, await seedCopy());
    expect(previews, hasLength(1));

    await tester.enterText(find.byKey(const Key('field-salutation')), 'D');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('field-salutation')), 'De');
    await tester.pump(const Duration(milliseconds: 100));
    expect(previews, hasLength(1), reason: 'still typing');

    await tester.pump(kPreviewDebounce + const Duration(milliseconds: 50));
    expect(previews, hasLength(2), reason: 'one rebuild after the pause');
  });

  testWidgets('Download PDF shares the form as it is on screen, unsaved '
      'edits included', (tester) async {
    final (_, _, shared) = await pumpEditor(tester, await seedCopy());

    await tester.enterText(
        find.byKey(const Key('field-researcher.1')), 'MARIA SANTOS');
    await tester.pump();
    await tester.tap(find.byKey(const Key('downloadCopy')));
    await settleReal(tester, () => shared.bytes != null);

    expect(shared.filename, 'Group 3 _ Santos.pdf');
    expect(extractPdfText(shared.bytes!), contains('MARIA SANTOS'));
  });

  testWidgets('leaving with unsaved edits asks first', (tester) async {
    final (router, _, _) = await pumpEditor(tester, await seedCopy());
    await tester.enterText(
        find.byKey(const Key('field-salutation')), 'Dear Dean:');
    await tester.pump();

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirmLeaveEditor')), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('field-salutation')), findsOneWidget,
        reason: 'Keep editing stays on the copy');

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmLeaveEditor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('formsHome')), findsOneWidget);
  });

  testWidgets('going to another page with unsaved edits asks too',
      (tester) async {
    final (router, _, _) = await pumpEditor(tester, await seedCopy());
    await tester.enterText(
        find.byKey(const Key('field-salutation')), 'Dear Dean:');
    await tester.pump();

    router.go('/forms');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirmLeaveEditor')), findsOneWidget);
  });

  testWidgets('leaving with nothing unsaved does not ask', (tester) async {
    final (router, _, _) = await pumpEditor(tester, await seedCopy());
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirmLeaveEditor')), findsNothing);
    expect(find.byKey(const Key('formsHome')), findsOneWidget);
  });

  testWidgets('a wide screen shows the fields and the preview side by side',
      (tester) async {
    await pumpEditor(tester, await seedCopy());
    expect(find.byKey(const Key('editorFields')), findsOneWidget);
    expect(find.byKey(const Key('previewStub')), findsOneWidget);
    expect(find.byKey(const Key('editorPaneSwitch')), findsNothing);
  });

  testWidgets('a phone switches between Edit and Preview', (tester) async {
    await pumpEditor(tester, await seedCopy(), size: const Size(400, 2400));
    expect(find.byKey(const Key('editorPaneSwitch')), findsOneWidget);
    expect(find.byKey(const Key('editorFields')), findsOneWidget);
    expect(find.byKey(const Key('previewStub')), findsNothing);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('previewStub')), findsOneWidget);
    expect(find.byKey(const Key('editorFields')), findsNothing);
  });

  testWidgets('a form that cannot be edited says so instead of crashing',
      (tester) async {
    await pumpEditor(tester, await seedCopy(),
        location: '/forms/form99/copies/c1');
    expect(find.byKey(const Key('formUnavailable')), findsOneWidget);
  });

  testWidgets('a deleted copy says so', (tester) async {
    await pumpEditor(tester, await seedCopy(),
        location: '/forms/form1/copies/gone');
    expect(find.byKey(const Key('copyMissing')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/forms/editable/form_copy_editor_screen_test.dart`
Expected: FAIL: `Target of URI doesn't exist: …editor_services.dart`.

- [ ] **Step 3: Write the editor services** at `lib/features/forms/editable/editor_services.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:ethesishub/core/widgets/confirm.dart';

/// True while the open form editor holds edits that are not saved. Set by
/// the editor; read by [confirmLeaveFormEditor] when its route is left.
final unsavedFormEditsProvider = StateProvider<bool>((ref) => false);

typedef PdfSharer = Future<void> Function(Uint8List bytes, String filename);

/// Hands a finished PDF to the platform: the share sheet on a phone, a
/// download on the web. A provider so a test can capture the bytes instead.
final pdfSharerProvider = Provider<PdfSharer>(
  (ref) => (bytes, filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  },
);

typedef FormPreviewBuilder = Widget Function(
    Key key, Future<Uint8List> Function() build);

/// The live preview of the printed form. Rasterising a PDF needs the
/// platform, so widget tests replace this with a stand-in.
final formPreviewBuilderProvider = Provider<FormPreviewBuilder>(
  (ref) => (key, build) => PdfPreview(
        key: key,
        build: (_) => build(),
        useActions: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        onError: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'The preview could not be drawn: $error',
              key: const Key('previewError'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
);

/// The editor route's `onExit`. It runs however the route is left: the
/// top-bar arrow and the Android back (both `pop()`), browser back, or a
/// sidebar `go()`. With unsaved edits it asks first; otherwise it lets the
/// reader go.
Future<bool> confirmLeaveFormEditor(
    BuildContext context, GoRouterState state) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (!container.read(unsavedFormEditsProvider)) return true;
  final leave = await confirmAction(
    context,
    title: 'Leave without saving?',
    message: 'Your edits to this copy have not been saved.',
    confirmLabel: 'Leave',
    cancelLabel: 'Keep editing',
    confirmKey: const Key('confirmLeaveEditor'),
  );
  if (leave) container.read(unsavedFormEditsProvider.notifier).state = false;
  return leave;
}
```

- [ ] **Step 4: Write the editor screen** at `lib/features/forms/editable/form_copy_editor_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/confirm.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/features/forms/editable/editor_services.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/editable/form_templates.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/form_copy_providers.dart';

/// At and above this width the fields and the preview sit side by side;
/// below it an Edit / Preview switch shows one at a time. The same point
/// `SplitColumns` stops stacking at.
const double kEditorSideBySideFrom = 860;

/// How long typing must pause before the preview is rebuilt: rendering a
/// PDF on every keystroke would stutter on a phone.
const Duration kPreviewDebounce = Duration(milliseconds: 400);

enum _Pane { edit, preview }

/// Edits one saved copy of a form: every block of its text as a field,
/// beside a live preview of the printed form.
class FormCopyEditorScreen extends ConsumerStatefulWidget {
  const FormCopyEditorScreen({
    super.key,
    required this.formId,
    required this.copyId,
  });

  final String formId;
  final String copyId;

  @override
  ConsumerState<FormCopyEditorScreen> createState() =>
      _FormCopyEditorScreenState();
}

class _FormCopyEditorScreenState extends ConsumerState<FormCopyEditorScreen> {
  final _controllers = <String, TextEditingController>{};
  final _lastTexts = <String, String>{};
  String? _loadedCopyId;
  bool _dirty = false;
  bool _saving = false;
  Object? _error;
  Map<String, String> _previewOverrides = const {};
  int _previewVersion = 0;
  Timer? _debounce;
  _Pane _pane = _Pane.edit;

  @override
  void initState() {
    super.initState();
    // A flag left over from an editor torn down without leaving through its
    // route (a sign-out, say) must not make this one ask on the way out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_dirty) {
        ref.read(unsavedFormEditsProvider.notifier).state = false;
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _values() =>
      {for (final e in _controllers.entries) e.key: e.value.text};

  /// Fills the fields once per copy. Later snapshots of the same copy (its
  /// own save coming back) must not overwrite what is being typed.
  void _load(FormTemplate template, FormCopy copy) {
    if (_loadedCopyId == copy.id) return;
    _loadedCopyId = copy.id;
    final text = FormText(template, copy.overrides);
    for (final b in template.blocks) {
      final c = TextEditingController(text: text.of(b.id));
      _lastTexts[b.id] = c.text;
      c.addListener(() => _onChanged(template, b.id, c));
      _controllers[b.id] = c;
    }
    _previewOverrides = template.overridesFrom(_values());
  }

  void _onChanged(
      FormTemplate template, String id, TextEditingController c) {
    // A controller also notifies on cursor and selection moves; only a
    // change of text is an edit.
    if (c.text == _lastTexts[id]) return;
    _lastTexts[id] = c.text;
    if (!_dirty) {
      setState(() => _dirty = true);
      ref.read(unsavedFormEditsProvider.notifier).state = true;
    }
    _debounce?.cancel();
    _debounce = Timer(kPreviewDebounce, () {
      if (!mounted) return;
      setState(() {
        _previewOverrides = template.overridesFrom(_values());
        _previewVersion++;
      });
    });
  }

  Future<void> _save(FormTemplate template, String uid) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(formCopyRepositoryProvider).saveOverrides(
            uid: uid,
            copyId: widget.copyId,
            overrides: template.overridesFrom(_values()),
          );
      if (!mounted) return;
      setState(() => _dirty = false);
      ref.read(unsavedFormEditsProvider.notifier).state = false;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _download(FormTemplate template, FormCopy copy) async {
    try {
      final bytes =
          await buildFormPdf(template, template.overridesFrom(_values()));
      await ref.read(pdfSharerProvider)(bytes, '${_fileSafe(copy.name)}.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not make the PDF: $e')));
    }
  }

  /// A file name any platform accepts: letters, digits, spaces, `_`, `-`.
  static String _fileSafe(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '_').trim();

  Future<void> _resetAll(FormTemplate template) async {
    final reset = await confirmAction(
      context,
      title: 'Reset every field?',
      message: 'All your edits in this copy go back to the form\'s original '
          'wording. Nothing is saved until you press Save.',
      confirmLabel: 'Reset',
      confirmKey: const Key('confirmResetAll'),
    );
    if (!reset) return;
    for (final b in template.blocks) {
      _controllers[b.id]!.text = b.defaultText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = templateFor(widget.formId);
    if (template == null) {
      return const PageShell(children: [
        EmptyState(
          key: Key('formUnavailable'),
          icon: Icons.description_outlined,
          title: 'This form is no longer available',
          message: 'It may have been removed in an update.',
        ),
      ]);
    }

    final uid = ref.watch(signedInUidProvider);
    return ref.watch(formCopyProvider(widget.copyId)).when(
          loading: () => const PageShell(
            children: [LoadingState.page(label: 'Opening your copy…')],
          ),
          error: (e, _) => PageShell(children: [
            ErrorState(error: e, message: 'Could not open this copy.'),
          ]),
          data: (copy) {
            if (copy == null || copy.formId != widget.formId) {
              return const PageShell(children: [
                EmptyState(
                  key: Key('copyMissing'),
                  icon: Icons.description_outlined,
                  title: 'This copy no longer exists',
                  message: 'It may have been deleted.',
                ),
              ]);
            }
            _load(template, copy);
            return _editor(template, copy, uid);
          },
        );
  }

  Widget _editor(FormTemplate template, FormCopy copy, String? uid) {
    final fields = Column(
      key: const Key('editorFields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in template.blocks)
          _BlockField(
            block: b,
            controller: _controllers[b.id]!,
            onReset: () => _controllers[b.id]!.text = b.defaultText,
          ),
      ],
    );

    // Captured, so the preview renders exactly the text it was keyed for.
    final overrides = _previewOverrides;
    final preview = SizedBox(
      height: 760,
      child: ref.watch(formPreviewBuilderProvider)(
        ValueKey(_previewVersion),
        () => buildFormPdf(template, overrides),
      ),
    );

    return PageShell(
      maxWidth: AppTokens.measureWide,
      kicker: template.title,
      title: copy.name,
      subtitle: _dirty ? 'Unsaved changes' : 'All changes saved',
      actions: [
        FilledButton.icon(
          key: const Key('saveCopy'),
          onPressed: (!_dirty || _saving || uid == null)
              ? null
              : () => _save(template, uid),
          icon: const Icon(Icons.save_outlined, size: 18),
          label: Text(_saving ? 'Saving…' : 'Save'),
        ),
        OutlinedButton.icon(
          key: const Key('downloadCopy'),
          onPressed: () => _download(template, copy),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download PDF'),
        ),
        TextButton(
          key: const Key('resetAllCopy'),
          onPressed: () => _resetAll(template),
          child: const Text('Reset all'),
        ),
      ],
      children: [
        if (_error != null) ...[
          ErrorState(
            key: const Key('saveError'),
            error: _error,
            message: 'Could not save this copy. Your edits are still here.',
          ),
          const Gap.md(),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= kEditorSideBySideFrom) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: fields),
                  const SizedBox(width: AppTokens.lg),
                  Expanded(child: preview),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_Pane>(
                  key: const Key('editorPaneSwitch'),
                  segments: const [
                    ButtonSegment(
                      value: _Pane.edit,
                      label: Text('Edit'),
                      icon: Icon(Icons.edit_outlined),
                    ),
                    ButtonSegment(
                      value: _Pane.preview,
                      label: Text('Preview'),
                      icon: Icon(Icons.visibility_outlined),
                    ),
                  ],
                  selected: {_pane},
                  onSelectionChanged: (s) => setState(() => _pane = s.first),
                ),
                const Gap.md(),
                if (_pane == _Pane.edit) fields else preview,
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One block of the form's text: its label, its field, and a button that
/// puts back the form's own wording.
class _BlockField extends StatelessWidget {
  const _BlockField({
    required this.block,
    required this.controller,
    required this.onReset,
  });

  final FormBlock block;
  final TextEditingController controller;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return FormRow(
      label: block.label,
      hint: block.kind == BlockKind.blank
          ? 'Leave empty to print a blank line.'
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: Key('field-${block.id}'),
              controller: controller,
              minLines: block.multiline ? 3 : 1,
              maxLines: block.multiline ? 8 : 1,
            ),
          ),
          IconButton(
            key: Key('resetField-${block.id}'),
            tooltip: 'Back to the form\'s wording',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run the editor test and watch it pass**

Run: `flutter test test/features/forms/editable/form_copy_editor_screen_test.dart`
Expected: PASS (14 tests).
If `leaving with unsaved edits asks first` or `going to another page with unsaved edits asks too` fails because no dialog appears, `onExit` is not firing on that path in this go_router build. Confirm the route is registered with `onExit: confirmLeaveFormEditor` in the test's router before changing anything. Do not replace the guard with a `PopScope` (ruling R5).

- [ ] **Step 6: Register the route.** In `lib/core/routing/app_router.dart`, add the imports next to the existing `forms_screen.dart` import:

```dart
import 'package:ethesishub/features/forms/editable/editor_services.dart';
import 'package:ethesishub/features/forms/editable/form_copy_editor_screen.dart';
```

and replace the line

```dart
      GoRoute(path: '/forms', builder: (_, _) => const FormsScreen()),
```

with

```dart
      GoRoute(path: '/forms', builder: (_, _) => const FormsScreen()),
      // One saved copy of a form, in the editor. Open to every role: a copy
      // belongs to whoever made it, and the rules keep it theirs. Below the
      // Forms destination, so the shell draws a back control; `onExit` asks
      // before leaving with unsaved edits, however the reader leaves.
      GoRoute(
        path: '/forms/:formId/copies/:copyId',
        onExit: confirmLeaveFormEditor,
        builder: (context, state) => FormCopyEditorScreen(
          formId: state.pathParameters['formId']!,
          copyId: state.pathParameters['copyId']!,
        ),
      ),
```

- [ ] **Step 7: Title the editor in the top bar.** In `lib/core/widgets/app_shell_host.dart`, inside `shellTitleFor`, immediately before `return _staticTitles[location] ?? 'eThesisHub';`, add:

```dart
  // A saved form copy, '/forms/<formId>/copies/<copyId>'. The copy's own
  // name is on the page; the bar says what kind of page this is.
  if (location.startsWith('/forms/')) return 'Edit form';

```

and in `test/core/widgets/app_shell_host_test.dart`, inside `group('shellTitleFor', () { … })`, after the existing `/overview` test, add:

```dart
    test('a form copy in the editor reads "Edit form"', () {
      expect(
          shellTitleFor('/forms/form1/copies/c1', const {}, UserRole.student),
          'Edit form');
      expect(shellTitleFor('/forms', const {}, UserRole.student), 'Forms',
          reason: 'the Forms destination itself keeps its own title');
    });
```

- [ ] **Step 8: Run the affected suites**

Run: `flutter test test/features/forms/ test/core/`
Expected: all PASS. If a test that lists every registered route or path fails because of the new route (for example in `test/core/navigation/` or `test/core/routing/`), add `/forms/:formId/copies/:copyId` to that test's expected list, the same way `/audit` was added there.

- [ ] **Step 9: Commit**

```bash
git add lib/features/forms/editable/editor_services.dart lib/features/forms/editable/form_copy_editor_screen.dart lib/core/routing/app_router.dart lib/core/widgets/app_shell_host.dart test/features/forms/editable/form_copy_editor_screen_test.dart test/core/widgets/app_shell_host_test.dart
# plus any route-list test Step 8 required you to update, by explicit path
git status --short
git commit -m "feat(forms): edit a saved form copy with a live preview

Every block of the form as a field beside a debounced preview of the
printed page (an Edit / Preview switch on a phone). Save stores only
what changed; Download PDF shares what is on screen; the route's
onExit asks before leaving with unsaved edits, however it is left.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: New copy and My copies on the Forms screen

**Files:**
- Create: `lib/features/forms/editable/name_dialog.dart`
- Create: `lib/features/forms/editable/form_copies_section.dart`
- Modify: `lib/features/forms/forms_screen.dart` (`_FormCard` gains `footer`; `_Form1Card` uses it)
- Test: `test/features/forms/editable/form_copies_section_test.dart`
- Test: `test/features/forms/forms_screen_test.dart` (one added test)

**Interfaces:**
- Consumes: Task 3 (`FormCopy`, `kFormCopyNameMax`, `formCopyRepositoryProvider`, `myFormCopiesProvider`); `signedInUidProvider`; `confirmAction`; `Dates.relative(DateTime)` (`lib/core/design/layout.dart`); `AppTokens`. The editor route `/forms/:formId/copies/:copyId` from Task 5.
- Produces:
  - `Future<String?> promptForName(BuildContext context, {required String title, required String initial, required String confirmLabel})`: the trimmed name, or null if cancelled
  - `class FormCopiesSection extends ConsumerWidget { const FormCopiesSection({Key? key, required String formId, required String defaultName}); }`
  - Keys: `<formId>NewCopy`, `<formId>MyCopies`, `copyNameField`, `copyNameConfirm`, `openCopy-<id>`, `renameCopy-<id>`, `deleteCopy-<id>`, `confirmDeleteCopy`.

- [ ] **Step 1: Write the failing section test** at `test/features/forms/editable/form_copies_section_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/features/forms/editable/form_copies_section.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('u1').set({
    'fullName': 'Test User',
    'email': 't@isufst.edu.ph',
    'role': 'faculty',
    'active': true,
  });
  return db;
}

Future<void> seedCopy(FakeFirebaseFirestore db, String uid, String id,
    String formId, String name, DateTime updated) {
  final at = Timestamp.fromDate(updated);
  return db.doc('users/$uid/formCopies/$id').set({
    'formId': formId,
    'name': name,
    'overrides': <String, String>{},
    'folderId': null,
    'createdAt': at,
    'updatedAt': at,
  });
}

Future<GoRouter> pumpSection(
    WidgetTester tester, FakeFirebaseFirestore db) async {
  final router = GoRouter(
    initialLocation: '/forms',
    routes: [
      GoRoute(
        path: '/forms',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(
            child: FormCopiesSection(
                formId: 'form1', defaultName: 'Form 1 copy'),
          ),
        ),
      ),
      GoRoute(
        path: '/forms/:formId/copies/:copyId',
        builder: (_, s) => Scaffold(
          body: Text('editor ${s.pathParameters['copyId']}',
              key: const Key('editorStub')),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'u1', email: 't@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

Future<void> settleReal(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('New copy asks for a name, creates the copy and opens it',
      (tester) async {
    final db = await seeded();
    final router = await pumpSection(tester, db);

    await tester.tap(find.byKey(const Key('form1NewCopy')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copyNameField')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('copyNameField')), 'Group 3 – Santos');
    await tester.pump();
    await tester.tap(find.byKey(const Key('copyNameConfirm')));
    await settleReal(tester);

    final copies = await db.collection('users/u1/formCopies').get();
    expect(copies.docs, hasLength(1));
    final copy = copies.docs.single;
    expect(copy.data()['name'], 'Group 3 – Santos');
    expect(copy.data()['formId'], 'form1');
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/forms/form1/copies/${copy.id}');
    expect(find.byKey(const Key('editorStub')), findsOneWidget);
  });

  testWidgets('cancelling New copy creates nothing', (tester) async {
    final db = await seeded();
    await pumpSection(tester, db);

    await tester.tap(find.byKey(const Key('form1NewCopy')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect((await db.collection('users/u1/formCopies').get()).docs, isEmpty);
  });

  testWidgets('an empty name cannot be confirmed', (tester) async {
    await pumpSection(tester, await seeded());
    await tester.tap(find.byKey(const Key('form1NewCopy')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('copyNameField')), '   ');
    await tester.pump();
    final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('copyNameConfirm')));
    expect(confirm.onPressed, isNull);
  });

  testWidgets('My copies lists only this person\'s copies of this form',
      (tester) async {
    final db = await seeded();
    await seedCopy(db, 'u1', 'a', 'form1', 'Group 3', DateTime(2026, 9, 1));
    await seedCopy(db, 'u1', 'b', 'form1', 'Group 5', DateTime(2026, 9, 2));
    await seedCopy(db, 'u1', 'c', 'form3', 'A Form 3', DateTime(2026, 9, 3));
    await seedCopy(db, 'u2', 'd', 'form1', 'Not mine', DateTime(2026, 9, 4));
    await pumpSection(tester, db);

    expect(find.text('My copies (2)'), findsOneWidget);
    expect(find.text('Group 3'), findsOneWidget);
    expect(find.text('Group 5'), findsOneWidget);
    expect(find.text('A Form 3'), findsNothing);
    expect(find.text('Not mine'), findsNothing);
  });

  testWidgets('with no copies there is no My copies list', (tester) async {
    await pumpSection(tester, await seeded());
    expect(find.byKey(const Key('form1MyCopies')), findsNothing);
    expect(find.byKey(const Key('form1NewCopy')), findsOneWidget);
  });

  testWidgets('Open goes to the editor for that copy', (tester) async {
    final db = await seeded();
    await seedCopy(db, 'u1', 'a', 'form1', 'Group 3', DateTime(2026, 9, 1));
    await pumpSection(tester, db);

    await tester.tap(find.byKey(const Key('openCopy-a')));
    await tester.pumpAndSettle();
    expect(find.text('editor a'), findsOneWidget);
  });

  testWidgets('Rename changes the name', (tester) async {
    final db = await seeded();
    await seedCopy(db, 'u1', 'a', 'form1', 'Group 3', DateTime(2026, 9, 1));
    await pumpSection(tester, db);

    await tester.tap(find.byKey(const Key('renameCopy-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('copyNameField')), 'Renamed');
    await tester.pump();
    await tester.tap(find.byKey(const Key('copyNameConfirm')));
    await settleReal(tester);

    expect((await db.doc('users/u1/formCopies/a').get()).data()!['name'],
        'Renamed');
    expect(find.text('Renamed'), findsOneWidget);
  });

  testWidgets('Delete asks first, then deletes', (tester) async {
    final db = await seeded();
    await seedCopy(db, 'u1', 'a', 'form1', 'Group 3', DateTime(2026, 9, 1));
    await pumpSection(tester, db);

    await tester.tap(find.byKey(const Key('deleteCopy-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirmDeleteCopy')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeleteCopy')));
    await settleReal(tester);

    expect((await db.doc('users/u1/formCopies/a').get()).exists, isFalse);
    expect(find.text('Group 3'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/forms/editable/form_copies_section_test.dart`
Expected: FAIL: `Target of URI doesn't exist: …form_copies_section.dart`.

- [ ] **Step 3: Write the name prompt** at `lib/features/forms/editable/name_dialog.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:ethesishub/data/repositories/form_copy_repository.dart';

/// Asks for a copy's name. Returns it trimmed, or null when cancelled.
Future<String?> promptForName(
  BuildContext context, {
  required String title,
  required String initial,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: title,
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid {
    final name = _controller.text.trim();
    return name.isNotEmpty && name.length <= kFormCopyNameMax;
  }

  void _submit() {
    if (_valid) Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('copyNameField'),
        controller: _controller,
        autofocus: true,
        maxLength: kFormCopyNameMax,
        decoration: const InputDecoration(labelText: 'Name'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('copyNameConfirm'),
          onPressed: _valid ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Write the section** at `lib/features/forms/editable/form_copies_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/confirm.dart';
import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/features/forms/editable/name_dialog.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/form_copy_providers.dart';

/// A form card's own copies: a New copy button, and the person's saved
/// copies of this form with Open, Rename and Delete.
class FormCopiesSection extends ConsumerWidget {
  const FormCopiesSection({
    super.key,
    required this.formId,
    required this.defaultName,
  });

  final String formId;

  /// What the name prompt suggests for a new copy.
  final String defaultName;

  void _open(BuildContext context, String copyId) =>
      context.push('/forms/$formId/copies/$copyId');

  void _report(BuildContext context, String what, Object error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not $what: $error')));
  }

  Future<void> _newCopy(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(signedInUidProvider);
    if (uid == null) return;
    final name = await promptForName(
      context,
      title: 'Name this copy',
      initial: defaultName,
      confirmLabel: 'Create',
    );
    if (name == null) return;
    try {
      final id = await ref
          .read(formCopyRepositoryProvider)
          .create(uid: uid, formId: formId, name: name);
      if (context.mounted) _open(context, id);
    } catch (e) {
      if (context.mounted) _report(context, 'create the copy', e);
    }
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, FormCopy copy) async {
    final uid = ref.read(signedInUidProvider);
    if (uid == null) return;
    final name = await promptForName(
      context,
      title: 'Rename this copy',
      initial: copy.name,
      confirmLabel: 'Rename',
    );
    if (name == null || name == copy.name) return;
    try {
      await ref
          .read(formCopyRepositoryProvider)
          .rename(uid: uid, copyId: copy.id, name: name);
    } catch (e) {
      if (context.mounted) _report(context, 'rename the copy', e);
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, FormCopy copy) async {
    final uid = ref.read(signedInUidProvider);
    if (uid == null) return;
    final confirmed = await confirmAction(
      context,
      title: 'Delete this copy?',
      message: '"${copy.name}" will be deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      confirmKey: const Key('confirmDeleteCopy'),
    );
    if (!confirmed) return;
    try {
      await ref
          .read(formCopyRepositoryProvider)
          .delete(uid: uid, copyId: copy.id);
    } catch (e) {
      if (context.mounted) _report(context, 'delete the copy', e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copies =
        ref.watch(myFormCopiesProvider(formId)).valueOrNull ?? const [];
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          key: Key('${formId}NewCopy'),
          onPressed: () => _newCopy(context, ref),
          icon: const Icon(Icons.edit_note_rounded, size: 18),
          label: const Text('New copy'),
        ),
        if (copies.isNotEmpty) ...[
          const SizedBox(height: AppTokens.md - 4),
          Text(
            'My copies (${copies.length})',
            key: Key('${formId}MyCopies'),
            style: text.labelLarge,
          ),
          for (final copy in copies)
            _CopyRow(
              copy: copy,
              onOpen: () => _open(context, copy.id),
              onRename: () => _rename(context, ref, copy),
              onDelete: () => _delete(context, ref, copy),
            ),
        ],
      ],
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.copy,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final FormCopy copy;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final edited = copy.updatedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.xs),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 18),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge,
                ),
                Text(
                  edited == null
                      ? 'Just now'
                      : 'Last edited: ${Dates.relative(edited)}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            key: Key('openCopy-${copy.id}'),
            onPressed: onOpen,
            child: const Text('Open'),
          ),
          IconButton(
            key: Key('renameCopy-${copy.id}'),
            tooltip: 'Rename',
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: onRename,
          ),
          IconButton(
            key: Key('deleteCopy-${copy.id}'),
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run the section test and watch it pass**

Run: `flutter test test/features/forms/editable/form_copies_section_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 6: Put the section on the Form 1 card.** In `lib/features/forms/forms_screen.dart`:

(a) Add the import next to the other `features/forms` imports:

```dart
import 'package:ethesishub/features/forms/editable/form_copies_section.dart';
```

(b) In `class _FormCard`, add an optional `footer`. Change the constructor and fields from

```dart
  const _FormCard({
    required this.cardKey,
    required this.name,
    required this.purpose,
    required this.actions,
  });

  final Key cardKey;
  final String name;
  final String purpose;
  final List<Widget> actions;
```

to

```dart
  const _FormCard({
    required this.cardKey,
    required this.name,
    required this.purpose,
    required this.actions,
    this.footer,
  });

  final Key cardKey;
  final String name;
  final String purpose;
  final List<Widget> actions;

  /// Drawn under the actions: the card's saved copies, where a form can be
  /// edited in the app.
  final Widget? footer;
```

and in its `build`, change

```dart
                Wrap(
                  spacing: AppTokens.sm,
                  runSpacing: AppTokens.sm,
                  children: actions,
                ),
              ],
```

to

```dart
                Wrap(
                  spacing: AppTokens.sm,
                  runSpacing: AppTokens.sm,
                  children: actions,
                ),
                if (footer != null) ...[
                  const SizedBox(height: AppTokens.md - 4),
                  footer!,
                ],
              ],
```

(c) Replace the whole `_Form1Card` class, including its doc comment, with:

```dart
/// Form 1 — Nomination of Thesis Adviser and Panel Members.
///
/// No blank template download, still deliberately: the official Form 1 is
/// generated from a thesis's own nominations, so this card links to the
/// thesis page for it. What it adds is the editable copy (spec 2026-09-24):
/// anyone can start a named copy of a blank Form 1, reword it in the app and
/// download it, from [FormCopiesSection] below the actions.
class _Form1Card extends ConsumerWidget {
  const _Form1Card();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesis = ref.watch(myThesisProvider).valueOrNull;

    return _FormCard(
      cardKey: const Key('form1Card'),
      name: 'Form 1 — Nomination of Thesis Adviser and Panel Members',
      purpose:
          'The letter that starts a thesis\'s approval chain, naming '
          'its adviser and panel.',
      actions: [
        Text(
          'The filled Form 1 is made from a thesis\'s own nominations. '
          'Open your thesis to download it, or start your own copy to '
          'edit here.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (thesis != null) ...[
          const Gap.sm(),
          OutlinedButton(
            key: const Key('form1OpenThesis'),
            onPressed: () => context.go('/thesis'),
            child: const Text('Open my thesis'),
          ),
        ],
      ],
      footer: const FormCopiesSection(
        formId: 'form1',
        defaultName: 'Form 1 copy',
      ),
    );
  }
}
```

(d) In `test/features/forms/forms_screen_test.dart`, add this test at the end of `main()`:

```dart
  testWidgets('the Form 1 card offers a copy to edit in the app',
      (tester) async {
    useTallSurface(tester);
    final db = await seedUser('s1');
    await tester.pumpWidget(app(db, 's1'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('form1Card')),
        matching: find.byKey(const Key('form1NewCopy')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('form1BlankButton')), findsNothing,
        reason: 'still no blank download for Form 1');
  });
```

- [ ] **Step 7: Run the Forms suites**

Run: `flutter test test/features/forms/`
Expected: all PASS, including the existing `Form 1 has no blank template button` and `form1OpenThesis` tests.

- [ ] **Step 8: Commit**

```bash
git add lib/features/forms/editable/name_dialog.dart lib/features/forms/editable/form_copies_section.dart lib/features/forms/forms_screen.dart test/features/forms/editable/form_copies_section_test.dart test/features/forms/forms_screen_test.dart
git status --short
git commit -m "feat(forms): start, open, rename and delete Form 1 copies

The Form 1 card gains New copy and a My copies list; a new copy is
named, created and opened in the editor. Renaming asks for the new
name, deleting asks first.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Whole-app verification

**Files:** none changed unless a check fails.

**Interfaces:** none.

- [ ] **Step 1: Static analysis**

Run: `flutter analyze`
Expected: no new issues in any file this plan created or modified. (There is one pre-existing `use_null_aware_elements` info in `lib/core/widgets/app_shell.dart`; leave it.)

- [ ] **Step 2: The full Flutter suite**

Run: `flutter test`
Expected: `All tests passed!`. The count before this plan was 1107; this plan adds roughly 60.

- [ ] **Step 3: The full rules suite**

Run: `cd rules-test && npm test`
Expected: every test passes.

- [ ] **Step 4: Report, with no commit.** List for the person running the app:
  1. `firebase deploy --only firestore:rules`: needed before copies can be saved on a real device.
  2. Rebuild the APK: `flutter build apk --release`.
  3. On a device: Forms → Form 1 → **New copy** → name it → edit a few fields → wait for the preview → **Save** → go back and reopen from **My copies** → **Download PDF**. Then edit again and press back without saving: it should ask first.
