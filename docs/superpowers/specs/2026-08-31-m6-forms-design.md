# M6 — Form generation

Objective 6 of the manuscript is pre-filled institutional forms. One of
them is built: `form1_data.dart` and `form1_pdf.dart` generate Form 1 from
a thesis's nomination record, with tests for each half, and the thesis
status screen hands the bytes to `Printing.sharePdf`.

This milestone adds two more, on the pattern Form 1 established.

## 0. Scope

The original design lists Forms 1, 3, 4a/4b, 5a, 5c, 7 and 8. **§9.3 of
that design pre-agreed a reduction under schedule pressure: Forms 1, 5c
and 8 only.** Form 1 exists, so this milestone is **Form 5c and Form 8** —
two forms, on data M4 and M5 have already frozen.

That reduction was written in advance precisely so it would not have to be
improvised under pressure. It is being spent.

## 1. What this delivers

- **`form_chrome.dart`** — the ISUFST letterhead and form-title block,
  extracted from Form 1 and shared by all three forms.
- **Form 5c**, the Evaluation Guide: one panelist's own completed sheet,
  with a Form 5b–style identifying header the printed 5c lacks.
- **Form 8**, Certification of Submission of Bound Copies, generated from
  a thesis's archive entry.

## 2. Decisions taken

Numbering continues from the M5a spec, which ended at D58.

**D59 — Form 5c is generated per panelist, for their own sheet.**
Guidelines §8a: *"The evaluators should also complete Research Form 5c"* —
one per evaluator. That is what the paper form is: an individual's
worksheet, not a summary.

It also sidesteps a problem the alternative has. A consolidated sheet
showing every panelist's scores would be a way to *read* every panelist's
scores, so it would have to respect M4's release seal — and a panelist
generating one before release would see exactly what D39 hides. Per-
panelist generation needs no new access rule at all: a panelist may
always read their own evaluation, released or not.

**D60 — The generated 5c carries a Form 5b–style header.** The printed
Form 5c has **no header fields whatsoever**. It runs from the letterhead
straight into "A. CONTENT" — no student, no title, no evaluator, no date —
and ends at Final Grade with no signature block. It is a bare rubric.

It gets away with that on paper because it is physically attached to Form
5b (Presenter and Evaluator Profile), which carries all the identifying
fields. A PDF is not stapled to anything. So the generated 5c carries 5b's
fields: presenter, title of the study, date and time of presentation,
venue, evaluator, and the evaluator's field of specialization.

This is a deliberate departure from a principle applied elsewhere in this
project — *do not improve on the institution's form* — which in M4 meant
**not** adding comment boxes to Section B. The distinction: there, adding
would have invented content the form omits on purpose; here, omitting
would ship a page of numbers with nothing saying whose thesis it scores.

**D61 — Academic Rank and the presenter's Degree print as blank ruled
lines.** The app holds neither. `facultyDirectory` carries a role and a
specialization but no academic rank, and nothing anywhere records a
student's degree. A ruled line is exactly what the paper form has, so
these are completed by hand as they are today. Printing an empty string
would look like a rendering failure; a rule looks like a form.

**D62 — "Average Rating" prints as a labelled blank line.** M4's D46
dropped the field, because Form 5c shows it twice alongside Final Grade
without ever defining how the three relate.

The generated form keeps the label and rules a blank line beside it. A
blank line says *this form has a field the system does not compute*;
deleting the row silently alters the office's form. It also keeps D46's
omission visible on the artifact rather than only in a design document.

**D63 — Title prints at 5%, not the 50% the paper form shows.** M4's D35
established this as a typo: 50 would make Section A sum to 95 against its
own stated 50%, and the whole form to 145.

The PDF must print what the score was measured against. A mark out of 5
beside a printed "50%" is incoherent on the page. The generated form will
therefore visibly differ from the paper one on a number, and someone will
notice. **No footnote explains it** — a document handed to the university
should not annotate that university's own typo. See §7.

**D64 — Form 8 is generated from the archive entry, and only once
archived.** §10b has the Research and Development Office issue Form 8
*"when they are ready to submit their bound copies"*, and the role table
gives the coordinator both "manage the archive" and "issue Form 8
certification" — the same person asserting the same fact at the same
moment.

M5's D51 made archiving the coordinator's assertion that Form 8 was issued
and three bound copies reached the Dean, the Library and R&D. Form 8
certifies precisely that. Generating from the entry means the certificate
cannot claim something the system has not recorded, and it inherits its
data already frozen (D49).

The rejected alternative — generate any time after the final defence
passes — allows a certificate asserting a deposit while the record shows
nothing archived. The two would contradict each other on the one artifact
that exists to prove the deposit happened.

**D65 — One Form 8 names every group member.** The printed form reads
*"certify that ______ has submitted bound copies of **his/her**
undergraduate thesis"* — singular, but a thesis here belongs to a group.
The archive entry holds every member name, and the deposit was joint, so
one certificate lists them all. One certificate per member would be more
machinery and more paper for the same fact.

**D66 — The signature line stays blank.** Form 8 ends with a ruled line
labelled "Research Coordinator/Chair". That wants a wet signature, so
`archivedBy` is never resolved to a name. The system records who archived;
the paper records who signed.

**D67 — Generated PDFs are ephemeral.** Form 1 already established this:
built on demand, handed to `Printing.sharePdf`, never written to Firestore
or Supabase. The `generatedForms` collection named in the original design
stays unbuilt.

Recording it as **settled rather than pending**: a stored PDF would be a
second copy of data that can already be regenerated, would need its own
rules and its own storage path, and would go stale the moment a
coordinator corrected a title.

**D68 — The chrome is extracted before either new form is written.** The
letterhead lives as literal strings inside `form1_pdf.dart`. At three
forms that is triplicated, and every form in the Guidelines carries it
identically.

Form 1 moves onto the shared chrome first, so `form1_pdf_test` — which
already exists and passes — verifies the extraction changed no rendering
before either new form depends on it. That is the only way to know the
shared piece is right rather than merely compiling.

## 3. Structure

```
lib/features/forms/
  form_chrome.dart      letterhead + form-title block          (new)
  form1_data.dart       unchanged
  form1_pdf.dart        switched onto form_chrome              (modified)
  form5c_data.dart      Form5cData.assemble(...)               (new)
  form5c_pdf.dart       buildForm5cPdf(data)                   (new)
  form8_data.dart       Form8Data.assemble(...)                (new)
  form8_pdf.dart        buildForm8Pdf(data)                    (new)
```

Each form keeps Form 1's split: a **pure data class** with an `assemble`
factory, testable without Firestore, and a **renderer** taking that class
and returning bytes. Nothing else in the app changes shape.

A generic data-driven renderer was considered and rejected. The three
layouts have nothing in common — Form 1 is a table of nominees, 5c is a
scoring rubric with prompts, 8 is three sentences and a signature line — so
a generic renderer would be a configuration language expressing three
things once each.

### 3.1 `Form5cData`

**One sheet per panelist per DEFENCE, not per thesis.** M4 applies Form 5c
to both the pre-oral and the final (D36), so one panelist can hold two
completed 5c sheets for the same thesis. The evaluation lives on the
defence, and the generating screen is `/defence/room/:defenceId/evaluate`,
so the defence is never ambiguous — but the sheets must be
distinguishable on the page, which is why `defenceType` is printed. Two
sheets differing only by a date would be a filing hazard.

```
presenterNames   List<String>    thesis.memberNames
title            String          the approved title's text
defenceType      DefenceType     'Pre-oral defence' / 'Final defence'
presentedOn      DateTime?       defence.scheduledAt
venue            String          defence.venue
evaluatorName    String          evaluation.evaluatorName — denormalized
                                 in M5, so no directory lookup is needed
evaluatorField   String          facultyDirectory.specialization — fetched
                                 by the SCREEN and passed in, so the data
                                 class stays free of repositories and
                                 testable without Firestore, exactly as
                                 Form 1 passes `directoryNames` in
scores           Map<String,int>
comments         Map<String,String>
sectionATotal  sectionBTotal  finalGrade   int
rating           PassFail?
```

### 3.2 `Form8Data`

```
studentNames  List<String>   entry.memberNames
title         String         entry.title
issuedOn      DateTime?      entry.archivedAt
```

Read from the **archive entry**, not the thesis (D64). Everything it needs
is already frozen there.

## 4. Access

**No new rules.** Both forms read data their generator can already read:

- **Form 5c** is generated by a panelist from their own evaluation, which
  M4's read rule grants them unconditionally. Nothing here can reach
  another panelist's sheet, so M4's seal is untouched.
- **Form 8** is generated by a coordinator from an archive entry, which
  M5's read rule grants to any signed-in user, and the entry is a
  published record besides.

**Not in scope:** the adviser or coordinator generating a *panelist's*
Form 5c after release. M4's rules would permit it — they may read every
evaluation once released — but it is a second entry point, and this
milestone is scoped to a fortnight.

## 5. Screens

**Form 5c** — a download control on the evaluation screen
(`/defence/room/:defenceId/evaluate`), shown to the panelist whose sheet it
is, once they have submitted. Nothing to generate before that.

**Form 8** — a download control on the archive entry screen
(`/archive/:thesisId`), shown to a coordinator only. §11a then has the
student obtain it from them, which stays out-of-band exactly as on paper.

Both call `Printing.sharePdf(bytes:, filename:)`, as Form 1 does.

## 6. Error handling

**Refuse rather than render a false document.** Form 8 refuses when the
thesis is not archived; Form 5c refuses when there is no evaluation. A
certificate with a blank name is worse than no certificate, because it
looks official.

A failure while assembling or rendering surfaces a message rather than a
silent no-op — a download button that does nothing is indistinguishable
from a slow one.

## 7. Documentation debt — and one item that now has teeth

**The Guidelines contain two incompatible form-numbering schemes.**

| | Body text and printed form headers | The list on p. 24 |
|---|---|---|
| Evaluation Guide | Form **5c** | Form **6c** |
| Certificate of Review | Form **7** | Form **8** |
| Submission of Bound Copies | Form **8** | Form **9** |

§10b and §11a also both cite "Appendix 11" for Form 8, but Appendix 11 is
the Sample Cover Page; Form 8 is on page 31.

**This milestone prints what the form headers print — 5c and 8** — on the
grounds that the header on the form itself is the strongest evidence of
what the office uses. But this is no longer only a documentation
inconsistency: it decides the label at the top of a generated PDF, and if
the Research Office expects "Form 9", that is an argument at a desk.

**To raise with the Research Coordinator**, now three items:

1. The two numbering schemes above, and which one the office uses.
2. Form 5c prints Title at 50%, contradicting its own section total (D35,
   D63). The generated form prints 5%.
3. Form 5c shows "Average Rating" twice alongside "Final Grade" with no
   stated relationship (D46, D62). The generated form rules a blank line.

Carried forward and still open from M5a: **Scope and Limitations needs
D58** — archived manuscripts are effectively public.

## 8. Out of scope

- **Forms 3, 4a/4b, 5a and 7**, per §9.3's reduction.
- **Form 5b**, whose fields the 5c header borrows. Generating it would be
  a fourth form.
- **Storing generated PDFs** (D67).
- **An adviser or coordinator generating a panelist's 5c** (§4).
- **Notifications** — the other half of the original M5 line item, still
  unspecced, and the most cuttable remaining work.
