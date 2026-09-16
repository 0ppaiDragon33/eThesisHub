# UI Overhaul — Foundation and Entry Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the document-direction component primitives, then restyle the five entry screens onto them, without changing a single behaviour.

**Architecture:** Two new files of primitives (`lib/core/components/document.dart`, `lib/core/components/brand.dart`) composed from the existing `AppTokens`. `PageShell` gains one optional parameter. The five entry screens swap their hand-rolled `Scaffold` + `Center` + `ConstrainedBox` + `SingleChildScrollView` for a shared `AuthScaffold`, keeping every key, validator, provider and error path exactly as it is.

**Tech Stack:** Flutter, Material 3, `AppTokens` (existing design tokens), `flutter_test` widget tests.

**Spec:** `docs/superpowers/specs/2026-09-17-ui-overhaul-design.md`

## Global Constraints

- **Tokens are not touched.** No new colours, no changed colours. `test/core/design_system_test.dart` must pass unchanged at every commit (D79).
- **`PageShell` and `states.dart` are extended, never replaced** (D80). `PageShell` gains exactly one optional `kicker` parameter; 26 screens already use it and must keep working.
- **The emblem is drawn in code, in seal blue** — `Icons.school` in a rounded square. Never a shipped image, never the reference purple (D81).
- **The brand band lives INSIDE the scroll view, and `resizeToAvoidBottomInset` is left at its Flutter default of `true`.** Nothing reads `MediaQuery.viewInsets` to collapse or animate anything (D83).
- **Presentation only.** Every existing auth-screen behavioural test must keep passing. A red behavioural test means the restyle broke something it had no business touching.
- **The brand sentence is a placeholder held in ONE constant** (`AuthScaffold.brandSentence`) so replacing it later is a one-line change, not five (spec §5).
- Existing spacing comes from `AppTokens.sm` (8), `.md` (16), `.lg` (24), and the `Gap.sm()/.md()/.lg()/.xl()` widgets in `page_shell.dart`. Do not introduce new magic numbers for spacing.

---

### Task 1: `BrandEmblem`

**Files:**
- Create: `lib/core/components/brand.dart`
- Test: `test/core/components/brand_emblem_test.dart`

**Interfaces:**
- Consumes: `AppTokens.seal`, `AppTokens.sealDark` (existing).
- Produces: `class BrandEmblem extends StatelessWidget` with `BrandEmblem({Key? key, double size = 44, Color? foreground, Color? background})`. Used by Task 5 (`AuthScaffold`) and, in a later phase, the app bar.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/components/brand_emblem_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/components/brand.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child,
      {Brightness brightness = Brightness.light}) {
    return tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    ));
  }

  testWidgets('draws a mortarboard, not an image asset', (tester) async {
    await pump(tester, const BrandEmblem());
    // Drawn in code (D81): there is a glyph and no Image to ship or lose.
    expect(find.byIcon(Icons.school), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('defaults to seal, and to the dark seal in dark mode', (tester) async {
    await pump(tester, const BrandEmblem());
    final light = tester.widget<Container>(find.byType(Container));
    expect((light.decoration as BoxDecoration).color, AppTokens.seal);

    await pump(tester, const BrandEmblem(), brightness: Brightness.dark);
    final dark = tester.widget<Container>(find.byType(Container));
    expect((dark.decoration as BoxDecoration).color, AppTokens.sealDark);
  });

  testWidgets('honours an explicit background, and scales with size', (tester) async {
    await pump(tester, const BrandEmblem(size: 26, background: Color(0xFF123456)));
    final box = tester.widget<Container>(find.byType(Container));
    expect((box.decoration as BoxDecoration).color, const Color(0xFF123456));
    // The mark appears at 56/40/26 across the app; the glyph must scale with it
    // rather than sit at a fixed size inside a shrinking square.
    expect(tester.widget<Icon>(find.byIcon(Icons.school)).size, lessThan(26));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/components/brand_emblem_test.dart`
Expected: FAIL — `brand.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/components/brand.dart
import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';

/// The app's mark: a mortarboard inside a rounded square.
///
/// Drawn in code rather than shipped as an image (D81) so it stays sharp at
/// every size it appears — 56px on the entry brand pane, 40px on the card,
/// 26px in the app bar — and so it can take the dark-mode seal without a
/// second asset.
///
/// Seal blue, not the purple of the reference image: every primary button,
/// link and active destination in this app keys off `seal`, and a mark in a
/// colour used nowhere else reads as borrowed rather than designed.
class BrandEmblem extends StatelessWidget {
  const BrandEmblem({
    super.key,
    this.size = 44,
    this.foreground,
    this.background,
  });

  final double size;
  final Color? foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? (dark ? AppTokens.sealDark : AppTokens.seal),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        Icons.school,
        size: size * 0.52,
        color: foreground ?? Colors.white,
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/components/brand_emblem_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/components/brand.dart test/core/components/brand_emblem_test.dart
git commit -m "feat(ui): add BrandEmblem, drawn in code in seal blue"
```

---

### Task 2: `SectionRule` and `RecordRow`

**Files:**
- Create: `lib/core/components/document.dart`
- Test: `test/core/components/document_test.dart`

**Interfaces:**
- Consumes: `AppTokens.sm/.md`, `AppTokens.rule`, `AppTokens.ink`, `AppTokens.inkDark` (existing).
- Produces: `class SectionRule extends StatelessWidget` — `SectionRule(String label, {Key? key, Widget? trailing})`; `class RecordRow extends StatelessWidget` — `RecordRow({Key? key, required String title, String? subtitle, Widget? leading, Widget? trailing, VoidCallback? onTap})`. Phase 2 replaces twelve screens' `Card`+`ListTile` with `RecordRow`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/components/document_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/components/document.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [child])),
    ));
  }

  group('SectionRule', () {
    testWidgets('renders its label and its trailing slot', (tester) async {
      await pump(tester, const SectionRule('Waiting on you',
          trailing: Text('3')));

      expect(find.text('Waiting on you'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('renders without a trailing slot', (tester) async {
      await pump(tester, const SectionRule('Decided'));

      expect(find.text('Decided'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('RecordRow', () {
    testWidgets('renders title, subtitle, leading and trailing', (tester) async {
      await pump(tester, const RecordRow(
        title: 'Coastal Fisheries Yield',
        subtitle: 'BSIT · First · 2026-2027',
        leading: Icon(Icons.circle, size: 10),
        trailing: Text('Approve'),
      ));

      expect(find.text('Coastal Fisheries Yield'), findsOneWidget);
      expect(find.text('BSIT · First · 2026-2027'), findsOneWidget);
      expect(find.byIcon(Icons.circle), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
    });

    testWidgets('a row with no subtitle still renders', (tester) async {
      await pump(tester, const RecordRow(title: 'Only a title'));

      expect(find.text('Only a title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is tappable only when given onTap', (tester) async {
      var taps = 0;
      await pump(tester, RecordRow(title: 'Tap me', onTap: () => taps++));
      await tester.tap(find.text('Tap me'));
      expect(taps, 1);

      await pump(tester, const RecordRow(title: 'Not tappable'));
      // No InkWell means nothing to tap: a row that looks interactive but
      // does nothing is worse than one that plainly is not.
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/components/document_test.dart`
Expected: FAIL — `document.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/components/document.dart
import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';

/// The shared presentation primitives for the document direction (D78).
///
/// Content sits on ruled rows under a hard section rule rather than inside
/// nested bordered panels: the tokens are already a paper-and-ink set, and
/// the app shell is itself a panel, so panels inside it become boxes within
/// boxes. Screens compose these instead of hand-rolling a Card with a
/// ListTile, which is the direct cause of every list in the app looking
/// slightly different from every other.

/// Opens a band: an overline label, an optional trailing count or control,
/// and the hard rule that separates this band from the one above it.
class SectionRule extends StatelessWidget {
  const SectionRule(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.lg, bottom: AppTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: dark
                            ? AppTokens.inkMutedDark
                            : AppTokens.inkMuted,
                      ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 5),
          Container(
            height: 1.5,
            color: dark ? AppTokens.inkDark : AppTokens.ink,
          ),
        ],
      ),
    );
  }
}

/// One record in a list: the ruled row that replaces Card-wrapping-ListTile.
///
/// The hairline is on the BOTTOM only, so consecutive rows read as a register
/// rather than as a stack of separate objects, and the last row sits flush
/// against whatever follows it.
class RecordRow extends StatelessWidget {
  const RecordRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  /// When null the row renders as plain content with no ink response — a row
  /// that looks interactive but does nothing is worse than one that plainly
  /// is not.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: dark ? AppTokens.ruleDark : AppTokens.rule,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppTokens.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: text.bodySmall?.copyWith(
                      color: dark
                          ? AppTokens.inkMutedDark
                          : AppTokens.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppTokens.sm),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
```

`AppTokens.ruleDark` exists (`app_tokens.dart:110`) — verified while writing this
plan, so use it directly. If you find yourself wanting a token that is *not*
there, stop: Global Constraints forbid adding one (D79).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/components/document_test.dart`
Expected: PASS

- [ ] **Step 5: Confirm the palette is untouched**

Run: `flutter test test/core/design_system_test.dart`
Expected: PASS, unchanged. This runs at every task because D79 makes it the
canary for accidental palette edits.

- [ ] **Step 6: Commit**

```bash
git add lib/core/components/document.dart test/core/components/document_test.dart
git commit -m "feat(ui): add SectionRule and RecordRow document primitives"
```

---

### Task 3: `FormRow` and `KeyFacts`

**Files:**
- Modify: `lib/core/components/document.dart` (append)
- Modify: `test/core/components/document_test.dart` (append two groups)

**Interfaces:**
- Consumes: the same tokens as Task 2.
- Produces: `class FormRow extends StatelessWidget` — `FormRow({Key? key, required String label, required Widget child})`; `class KeyFacts extends StatelessWidget` — `KeyFacts(List<({String label, String value})> facts, {Key? key})`. Task 6 and Task 7 use `FormRow` for every entry-screen field.

- [ ] **Step 1: Write the failing tests**

Append to `test/core/components/document_test.dart`, inside `main()`:

```dart
  group('FormRow', () {
    testWidgets('labels its field and renders the field itself', (tester) async {
      await pump(tester, const FormRow(
        label: 'Institutional email',
        child: TextField(key: Key('email')),
      ));

      expect(find.text('INSTITUTIONAL EMAIL'), findsOneWidget);
      expect(find.byKey(const Key('email')), findsOneWidget);
    });

    testWidgets('the label is not a TextField label', (tester) async {
      // The overline sits ABOVE the input rather than floating inside it —
      // that is the whole point of the treatment, and a labelText would
      // silently reintroduce the old look.
      await pump(tester, const FormRow(
        label: 'Password',
        child: TextField(key: Key('pw')),
      ));

      final field = tester.widget<TextField>(find.byKey(const Key('pw')));
      expect(field.decoration?.labelText, isNull);
    });
  });

  group('KeyFacts', () {
    testWidgets('renders each label and value in order', (tester) async {
      await pump(tester, const KeyFacts([
        (label: 'Program', value: 'BSIT'),
        (label: 'Academic year', value: '2026-2027'),
      ]));

      expect(find.text('Program'), findsOneWidget);
      expect(find.text('BSIT'), findsOneWidget);
      expect(find.text('Academic year'), findsOneWidget);
      expect(find.text('2026-2027'), findsOneWidget);
    });

    testWidgets('an empty list renders nothing rather than throwing',
        (tester) async {
      await pump(tester, const KeyFacts([]));
      expect(tester.takeException(), isNull);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/components/document_test.dart`
Expected: FAIL — `FormRow` and `KeyFacts` are not defined.

- [ ] **Step 3: Write the implementation**

Append to `lib/core/components/document.dart`:

```dart
/// A labelled field: an overline label above the input, not floating inside
/// it.
///
/// Screens previously passed their own `InputDecoration(labelText: ...)` per
/// field, which is why no two forms in this app look alike. The label moves
/// out of the decoration and into the layout, so every form shares one
/// rhythm and the field itself is free to be a TextField, a dropdown or a
/// date picker without the label treatment changing.
class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  color: dark ? AppTokens.inkMutedDark : AppTokens.inkMuted,
                ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// Label-and-value pairs for stating facts about a record.
///
/// Takes an ordered list rather than a Map: these are read in a deliberate
/// order (program before academic year), and a Map's iteration order is an
/// implementation detail to rely on by accident.
class KeyFacts extends StatelessWidget {
  const KeyFacts(this.facts, {super.key});

  final List<({String label, String value})> facts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final fact in facts)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    fact.label,
                    style: text.bodySmall?.copyWith(
                      color:
                          dark ? AppTokens.inkMutedDark : AppTokens.inkMuted,
                    ),
                  ),
                ),
                Expanded(child: Text(fact.value, style: text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/components/document_test.dart`
Expected: PASS (all four groups)

- [ ] **Step 5: Commit**

```bash
git add lib/core/components/document.dart test/core/components/document_test.dart
git commit -m "feat(ui): add FormRow and KeyFacts document primitives"
```

---

### Task 4: `PageShell` gains a kicker

**Files:**
- Modify: `lib/core/widgets/page_shell.dart`
- Test: `test/core/widgets/page_shell_test.dart` (existing file — append)

**Interfaces:**
- Consumes: nothing new.
- Produces: `PageShell({Key? key, required List<Widget> children, String? kicker, String? title, String? subtitle, bool scrollable = true, double maxWidth = AppTokens.measure})` — `kicker` is new and optional; every existing call site keeps compiling.

- [ ] **Step 1: Write the failing test**

Append to `test/core/widgets/page_shell_test.dart`, inside `main()`:

```dart
  testWidgets('renders an optional kicker above the title', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PageShell(
          kicker: 'Dean',
          title: 'Approvals',
          children: [Text('body')],
        ),
      ),
    ));

    expect(find.text('DEAN'), findsOneWidget);
    expect(find.text('Approvals'), findsOneWidget);
  });

  testWidgets('omitting the kicker changes nothing', (tester) async {
    // 26 screens already call PageShell without one; this pins that the new
    // parameter is genuinely optional rather than quietly required.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PageShell(title: 'Approvals', children: [Text('body')]),
      ),
    ));

    expect(find.text('Approvals'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 2: Run tests to verify the first fails**

Run: `flutter test test/core/widgets/page_shell_test.dart`
Expected: FAIL — `PageShell` has no `kicker` parameter.

- [ ] **Step 3: Write the implementation**

In `lib/core/widgets/page_shell.dart`, add the field to the constructor and the
class, then render it. Add `this.kicker,` to the constructor parameter list, and:

```dart
  /// A short overline above the title naming the context you are reading in —
  /// the role whose queue this is, or the record this page belongs to. The app
  /// bar says where you are in the app; the title says what the page asks of
  /// you; the kicker says on whose behalf.
  final String? kicker;
```

Then, inside `build`, replace the `if (title != null) ...[` block's opening so the
kicker renders first:

```dart
        if (kicker != null) ...[
          Text(
            kicker!.toUpperCase(),
            style: text.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
        ],
        if (title != null) ...[
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/widgets/page_shell_test.dart`
Expected: PASS

- [ ] **Step 5: Verify the 26 existing consumers still work**

Run: `flutter test`
Expected: PASS, whole suite. `PageShell` is used by 26 screens; a change to it
is the one change in this plan that can break screens nobody is looking at.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/page_shell.dart test/core/widgets/page_shell_test.dart
git commit -m "feat(ui): let PageShell carry an optional kicker overline"
```

---

### Task 5: `AuthScaffold`

**Files:**
- Modify: `lib/core/components/brand.dart` (append)
- Test: `test/core/components/auth_scaffold_test.dart`

**Interfaces:**
- Consumes: `BrandEmblem` (Task 1).
- Produces: `class AuthScaffold extends StatelessWidget` — `AuthScaffold({Key? key, required String title, String? subtitle, required List<Widget> children})`, plus `static const String brandSentence` and `static const double wideBreakpoint = 840`. Tasks 6–8 build every entry screen on it.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/components/auth_scaffold_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/components/brand.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: AuthScaffold(
        title: 'Sign in',
        subtitle: 'Use your ISUFST account.',
        children: [Text('form body')],
      ),
    ));
  }

  testWidgets('wide: brand pane beside the card', (tester) async {
    await pumpAt(tester, const Size(1200, 900));

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('form body'), findsOneWidget);
    // The sentence only appears where the pane has room for it.
    expect(find.text(AuthScaffold.brandSentence), findsOneWidget);
  });

  testWidgets('narrow: band above the card, no sentence', (tester) async {
    await pumpAt(tester, const Size(400, 900));

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('form body'), findsOneWidget);
    // A phone band is a band, not a billboard: the emblem and wordmark only.
    expect(find.text(AuthScaffold.brandSentence), findsNothing);
  });

  testWidgets('the emblem appears at both widths', (tester) async {
    await pumpAt(tester, const Size(1200, 900));
    expect(find.byType(BrandEmblem), findsOneWidget);

    await pumpAt(tester, const Size(400, 900));
    expect(find.byType(BrandEmblem), findsOneWidget);
  });

  // D83. The band is inside the scroll view and the Scaffold keeps Flutter's
  // default resize behaviour, so a keyboard shrinks the viewport and the band
  // scrolls away rather than eating the space the form needs. This pins the
  // structure that makes that true.
  testWidgets('the whole narrow layout scrolls, band included', (tester) async {
    await pumpAt(tester, const Size(400, 900));

    final scrollable = find.byType(Scrollable);
    expect(scrollable, findsWidgets);
    // The emblem must be INSIDE a scroll view, not pinned above one.
    expect(
      find.ancestor(of: find.byType(BrandEmblem), matching: scrollable),
      findsWidgets,
    );
  });

  testWidgets('keeps the default resizeToAvoidBottomInset', (tester) async {
    await pumpAt(tester, const Size(400, 900));
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    // Null means "use Flutter's default (true)". Setting it false is the bug
    // this pins against: it is what puts a focused field under the keyboard.
    expect(scaffold.resizeToAvoidBottomInset, anyOf(isNull, isTrue));
  });

  testWidgets('survives a keyboard-sized bottom inset', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: AuthScaffold(
        title: 'Create account',
        children: [
          _FieldStub(), _FieldStub(), _FieldStub(),
          _FieldStub(), _FieldStub(),
        ],
      ),
    ));

    // Five fields, a shrunken viewport and no overflow: the layout gives way
    // by scrolling rather than by painting outside itself.
    expect(tester.takeException(), isNull);
  });
}

/// A field-sized block, so the inset test exercises real height rather than
/// a one-line Text.
class _FieldStub extends StatelessWidget {
  const _FieldStub({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(height: 72);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/components/auth_scaffold_test.dart`
Expected: FAIL — `AuthScaffold` is not defined.

- [ ] **Step 3: Write the implementation**

Append to `lib/core/components/brand.dart`:

```dart
/// The shared layout for every entry screen: login, register, verify-email,
/// no-profile and deactivated (D82).
///
/// Wide surfaces get the seal brand pane beside the form; narrow ones get a
/// band above it. The form sits in a card at both widths so it reads as one
/// object rather than as fields floating on a page.
///
/// The keyboard is never detected (D83). The band lives INSIDE the scroll
/// view and `resizeToAvoidBottomInset` keeps its default, so `Scaffold`
/// shrinks the viewport and a focused field's own `Scrollable.ensureVisible`
/// brings it into view. The band simply scrolls away once typing starts,
/// which is what gives register's five fields the full height without any
/// inset arithmetic.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// PLACEHOLDER, awaiting the owner's wording (spec §5).
  ///
  /// This is the first line a defence panel reads on a projector, so it is
  /// theirs to write. It lives here as a single constant precisely so that
  /// replacing it is a one-line change rather than an edit to five screens.
  static const String brandSentence =
      'Nomination, defence and the thesis record — '
      'in one place, for the whole college.';

  /// Above this width the brand pane sits beside the form; below it, above.
  static const double wideBreakpoint = 840;

  @override
  Widget build(BuildContext context) {
    // resizeToAvoidBottomInset is deliberately not set: Flutter's default
    // (true) is the behaviour this design depends on.
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= wideBreakpoint;
          return wide ? _wide(context) : _narrow(context);
        },
      ),
    );
  }

  Widget _wide(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 42, child: _pane(context)),
        Expanded(
          flex: 58,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.lg),
            child: Center(child: _card(context)),
          ),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context) {
    // The band is a child of the scroll view, not a sibling above it (D83).
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _band(context),
          Padding(
            padding: const EdgeInsets.all(AppTokens.md),
            child: _card(context),
          ),
        ],
      ),
    );
  }

  Widget _pane(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? AppTokens.sealDark : AppTokens.seal,
      padding: const EdgeInsets.all(AppTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const BrandEmblem(size: 56, background: Colors.white24),
          const Gap.md(),
          Text(
            'eThesisHub',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const Gap.sm(),
          Text(
            brandSentence,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _band(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? AppTokens.sealDark : AppTokens.seal,
      padding: const EdgeInsets.all(AppTokens.md),
      child: Row(
        children: [
          const BrandEmblem(size: 28, background: Colors.white24),
          const SizedBox(width: AppTokens.sm),
          Text(
            'eThesisHub',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.lg),
        decoration: BoxDecoration(
          color: dark ? AppTokens.surfaceDark : AppTokens.paper,
          borderRadius: BorderRadius.circular(AppTokens.radius),
          border: Border.all(color: dark ? AppTokens.ruleDark : AppTokens.rule),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: text.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: text.bodySmall?.copyWith(
                  color: dark ? AppTokens.inkMutedDark : AppTokens.inkMuted,
                ),
              ),
            ],
            const Gap.md(),
            ...children,
          ],
        ),
      ),
    );
  }
}
```

Add to the imports at the top of `brand.dart`:

```dart
import 'package:ethesishub/core/widgets/page_shell.dart' show Gap;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/components/auth_scaffold_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/components/brand.dart test/core/components/auth_scaffold_test.dart
git commit -m "feat(ui): add AuthScaffold, the shared entry-screen layout"
```

---

### Task 6: Login onto `AuthScaffold`

**Files:**
- Modify: `lib/features/auth/login_screen.dart`
- Test: `test/features/auth/login_screen_test.dart` (existing, if present — otherwise the existing auth tests elsewhere)

**Interfaces:**
- Consumes: `AuthScaffold` (Task 5), `FormRow` (Task 3).
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Record the behavioural baseline**

Run: `flutter test test/features/auth/`
Expected: PASS. Write the passing count into your report. **This is presentation-only
work: the same tests must pass afterwards with no edits to their assertions.** If
you find yourself changing an assertion, stop and report it — that means the
restyle changed behaviour it should not have.

- [ ] **Step 2: Replace the scaffold**

In `lib/features/auth/login_screen.dart`, replace the `return Scaffold(...)` block
that currently reads:

```dart
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
```

with:

```dart
    return AuthScaffold(
      title: 'Sign in',
      subtitle: 'Use your ISUFST account.',
      children: [
```

and close it with `],\n    );` where the old `Scaffold` closed. The app bar goes:
`AuthScaffold` carries the wordmark, and a screen that says "Sign in" twice — once
in a bar and once on the card — is the duplication this direction removes.

Add the imports:

```dart
import 'package:ethesishub/core/components/brand.dart';
import 'package:ethesishub/core/components/document.dart';
```

- [ ] **Step 3: Move each field's label into a `FormRow`**

Replace the email field:

```dart
                TextField(
                  key: const Key('email'),
                  decoration: const InputDecoration(labelText: 'Email'),
```

with:

```dart
                FormRow(
                  label: 'Email',
                  child: TextField(
                    key: const Key('email'),
                    decoration: const InputDecoration(
                      border: UnderlineInputBorder(),
                      isDense: true,
                    ),
```

and close the `FormRow` after the `TextField`'s closing paren. Do the same for the
password field, label `'Password'`. **Keep every `key:`, `controller:`,
`obscureText:`, `onSubmitted:` and validator exactly as they are** — those are what
the existing tests find and drive.

- [ ] **Step 4: Run the behavioural tests, unchanged**

Run: `flutter test test/features/auth/`
Expected: PASS, the same count as Step 1, with no assertion edited.

- [ ] **Step 5: Add the two-width render test**

Create or append to `test/features/auth/login_screen_test.dart`:

```dart
  testWidgets('renders at a phone width and at a desktop width',
      (tester) async {
    for (final size in [const Size(400, 900), const Size(1200, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(/* the file's existing pump helper for LoginScreen */);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('email')), findsOneWidget);
      expect(find.byKey(const Key('password')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
```

Use the file's own existing helper for building `LoginScreen` with its providers —
read the top of the file and reuse it rather than writing a second one.

- [ ] **Step 6: Run the full suite and analyze**

Run: `flutter test` then `flutter analyze`
Expected: PASS; analyze clean apart from the two pre-existing
`use_super_parameters` infos in `verify_email_screen_test.dart`.

- [ ] **Step 7: Commit**

```bash
git add lib/features/auth/login_screen.dart test/features/auth/login_screen_test.dart
git commit -m "feat(ui): restyle the login screen onto AuthScaffold"
```

---

### Task 7: Register onto `AuthScaffold`

**Files:**
- Modify: `lib/features/auth/register_screen.dart`
- Test: `test/features/auth/register_screen_test.dart` (existing, if present)

**Interfaces:**
- Consumes: `AuthScaffold` (Task 5), `FormRow` (Task 3).
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Record the behavioural baseline**

Run: `flutter test test/features/auth/`
Expected: PASS. Note the count. As in Task 6, the same tests must pass afterwards
with no assertion edited.

- [ ] **Step 2: Replace the scaffold**

In `lib/features/auth/register_screen.dart`, replace the `Scaffold` + `Center` +
`ConstrainedBox` + `SingleChildScrollView` + `Column` wrapper with:

```dart
    return AuthScaffold(
      title: 'Create account',
      subtitle: 'Use your @isufst.edu.ph address.',
      children: [
```

closing with `],\n    );`. Add the same two imports as Task 6.

- [ ] **Step 3: Move all five labels into `FormRow`s**

The five fields and their labels, in the order they appear:

| Field | `FormRow` label |
|---|---|
| Full name | `'Full name'` |
| Institutional email | `'Institutional email'` |
| Program (optional) | `'Program (optional)'` |
| Password | `'Password'` |
| Confirm password | `'Confirm password'` |

For each, wrap the existing field in `FormRow(label: ..., child: ...)` and change
its decoration from `InputDecoration(labelText: '...')` to:

```dart
                    decoration: const InputDecoration(
                      border: UnderlineInputBorder(),
                      isDense: true,
                    ),
```

**Keep `PasswordStrengthMeter` and `InstitutionalDomainNotice` exactly where they
are in the child order** — they are existing widgets with their own tests, and
this task restyles the frame around them, not them.

- [ ] **Step 4: Run the behavioural tests, unchanged**

Run: `flutter test test/features/auth/`
Expected: PASS, same count as Step 1.

- [ ] **Step 5: Add the five-field inset test**

Append to `test/features/auth/register_screen_test.dart`:

```dart
  testWidgets('five fields survive a keyboard-sized inset', (tester) async {
    // Register is the screen most likely to break the shared scaffold: five
    // fields, a phone width and a keyboard up. It must scroll, not overflow.
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(/* the file's existing pump helper for RegisterScreen */);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 6: Run the full suite and analyze**

Run: `flutter test` then `flutter analyze`
Expected: PASS; analyze clean apart from the two pre-existing infos.

- [ ] **Step 7: Commit**

```bash
git add lib/features/auth/register_screen.dart test/features/auth/register_screen_test.dart
git commit -m "feat(ui): restyle the register screen onto AuthScaffold"
```

---

### Task 8: The three short entry screens

**Files:**
- Modify: `lib/features/auth/verify_email_screen.dart`
- Modify: `lib/features/auth/no_profile_screen.dart`
- Modify: `lib/features/auth/deactivated_screen.dart`
- Test: their existing test files

**Interfaces:**
- Consumes: `AuthScaffold` (Task 5).
- Produces: nothing.

These three are batched into one task deliberately: each is a sentence, a button
and no form fields, the change is identical in all three, and a reviewer would
judge them together rather than one at a time.

- [ ] **Step 1: Record the behavioural baseline**

Run: `flutter test test/features/auth/`
Expected: PASS. Note the count.

- [ ] **Step 2: Replace each screen's scaffold**

For each of the three, replace its outer `Scaffold`/`Center`/`Padding` wrapper with
`AuthScaffold`, keeping every child widget, key and callback as-is:

```dart
// verify_email_screen.dart
    return AuthScaffold(
      title: 'Verify your email',
      subtitle: 'We sent a link to your institutional address.',
      children: [ /* existing children, unchanged */ ],
    );

// no_profile_screen.dart
    return AuthScaffold(
      title: 'Profile unavailable',
      subtitle: 'Your account exists, but its profile could not be read.',
      children: [ /* existing children, unchanged */ ],
    );

// deactivated_screen.dart
    return AuthScaffold(
      title: 'Account deactivated',
      subtitle: 'This account has been deactivated by the college.',
      children: [ /* existing children, unchanged */ ],
    );
```

Add `import 'package:ethesishub/core/components/brand.dart';` to each.

**`no_profile_screen.dart` and `deactivated_screen.dart` must keep their sign-out
button reachable.** It is the only control those screens have, and on
`/no-profile` it is the only way out of the app — the shell deliberately gives
that route no back control and no destinations.

- [ ] **Step 3: Run the behavioural tests, unchanged**

Run: `flutter test test/features/auth/`
Expected: PASS, same count as Step 1, no assertion edited.

- [ ] **Step 4: Add a two-width render test to each**

For each of the three test files, append (adapting the widget name and the file's
own pump helper):

```dart
  testWidgets('renders at a phone width and at a desktop width',
      (tester) async {
    for (final size in [const Size(400, 900), const Size(1200, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(/* the file's existing pump helper */);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    }
  });
```

- [ ] **Step 5: Run the full suite and analyze**

Run: `flutter test` then `flutter analyze`
Expected: PASS; analyze clean apart from the two pre-existing infos.

- [ ] **Step 6: Confirm the palette never moved**

Run: `flutter test test/core/design_system_test.dart`
Expected: PASS, unchanged since before Task 1. This is the D79 canary and this is
its last check for the phase.

- [ ] **Step 7: Commit**

```bash
git add lib/features/auth/ test/features/auth/
git commit -m "feat(ui): restyle verify-email, no-profile and deactivated onto AuthScaffold"
```

---

## Manual verification (after Task 8)

Run the app and look at all five entry screens at two widths:

```bash
flutter run -d chrome    # desktop: brand pane beside the card
```

Then narrow the browser below 840px and confirm the pane becomes a band above the
card. On Android (or a narrow window), tap into a field on **register** and confirm
the band scrolls away rather than squeezing the form — that is D83 working, and it
is the one thing a widget test approximates rather than proves.

## Known open item

`AuthScaffold.brandSentence` ships as a placeholder (spec §5). Phase 1 is not
"done" in the owner's eyes until that sentence is theirs. It is one constant in
one file; changing it requires no screen edits.
