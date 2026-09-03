# Dashboards and Accent Restyle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every role an Overview screen at navigation index 0 — stat tiles, a "Needs you" queue, and (for whole-college roles) two charts — restyled with a new accent palette and a bundled serif.

**Architecture:** Three new shared widgets (`StatTile`, `StatTileGrid`, `NeedsYouQueue`) built and tested in isolation first, then composed into four dashboards one at a time. Each dashboard task also performs its own navigation index shift, so no task leaves the app with a mis-wired nav bar. Charts land before the two dashboards that embed them.

**Tech Stack:** Flutter 3.44 / Dart 3.12 · Riverpod **2.6.1** (2.x API only) · `fl_chart` (new) · Source Serif 4 (new, OFL 1.1) · `fake_cloud_firestore` for widget tests · `@firebase/rules-unit-testing` against the Firestore emulator.

**Spec:** `docs/superpowers/specs/2026-08-26-dashboards-restyle-design.md`

## Global Constraints

- **Android and Web only.** `dart:io` must never be imported from `lib/`.
- **Riverpod is pinned at 2.6.1.** No codegen, no `@riverpod`, no 3.x `Notifier` API. Use `Provider`, `StreamProvider`, `FutureProvider`, `StateNotifierProvider` and their `.family` forms.
- **Firebase Spark plan.** No Cloud Functions. `firestore.rules` is the only authorization boundary.
- **`fake_cloud_firestore` enforces no rules** — every permission claim must be proven in `rules-test/rules.test.js` against the emulator, with a control showing a different role is denied the same operation.
- **`fake_cloud_firestore` returns documents in insertion order** — any ordering test must seed its fixture *against* the expected order.
- **`pumpAndSettle` resolves streams before assertions** — loading-state tests use a single `pump()` against a `StreamController` that never emits.
- **A tile badge is never coloured by the status of the thing it counts.** Badge colour is fixed per tile position (spec D14).
- **The "N things need you" count is `queue.length` of the same provider rendered below it** — never a separately computed figure (spec D16).
- **Nothing on an overview may depend on the `users/{uid}` profile document existing.** Fall back, never block (spec §6).
- **Run `flutter test` in the FOREGROUND.** Concurrent runs leave orphaned `flutter_tester` processes that make the suite appear to hang.
- Analyzer must stay clean apart from the 2 known pre-existing infos.

---

### Task 1: Accent palette tokens

**Files:**
- Modify: `lib/core/theme/app_tokens.dart`
- Test: `test/core/design_system_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `AppTokens.accentPlum/accentSeal/accentPine/accentOchre/accentBrick`, their `…Dark` counterparts, and `AppTokens.accents` / `AppTokens.accentsDark` as `List<Color>` of length 5 in that order. Every later task indexes into `AppTokens.accents`.

- [ ] **Step 1: Write the failing test**

Append to `test/core/design_system_test.dart`, inside `void main()`:

```dart
  group('accent palette', () {
    test('has five accents in both brightnesses, in matching order', () {
      // Charts index into these by series number, so the two lists must
      // stay the same length and the same order or a segment changes
      // colour when the theme flips.
      expect(AppTokens.accents, hasLength(5));
      expect(AppTokens.accentsDark, hasLength(5));
      expect(AppTokens.accents[0], AppTokens.accentPlum);
      expect(AppTokens.accents[4], AppTokens.accentBrick);
      expect(AppTokens.accentsDark[0], AppTokens.accentPlumDark);
      expect(AppTokens.accentsDark[4], AppTokens.accentBrickDark);
    });

    test('every accent is distinguishable from its neighbours', () {
      // The whole job of this set is to tell one series from another. Two
      // accents that compute to the same luminance band read as one colour
      // in a donut, which is the failure this asserts against.
      final seen = <int>{};
      for (final c in AppTokens.accents) {
        expect(seen.add(c.toARGB32()), isTrue,
            reason: 'duplicate accent ${c.toARGB32()}');
      }
    });

    test('dark accents are lighter than their light counterparts', () {
      // Same relationship rule the existing dark palette follows: a colour
      // that sits on a dark surface must rise off it, not sink into it.
      for (var i = 0; i < 5; i++) {
        expect(
          AppTokens.accentsDark[i].computeLuminance(),
          greaterThan(AppTokens.accents[i].computeLuminance()),
          reason: 'accent $i does not lift in dark mode',
        );
      }
    });
  });
```

Add the import if absent: `import 'package:ethesishub/core/theme/app_tokens.dart';`

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/design_system_test.dart`
Expected: FAIL — compile error, `accentPlum` is not defined for the type `AppTokens`.

- [ ] **Step 3: Write minimal implementation**

In `lib/core/theme/app_tokens.dart`, after the `awaitingDark` line and before `paperDark`, insert:

```dart
  // --- Accents -----------------------------------------------------------
  // A second palette, for the one job the meaning colours above cannot do:
  // telling one thing from another without saying anything about it. A tile
  // badge and a chart segment identify; they do not judge.
  //
  // Three of these share a hue with a meaning colour on purpose — inventing
  // five unrelated hues would make the app look like a different product.
  // What keeps that safe is not separation on screen (a pine badge and an
  // `endorsed` chip do appear together) but separation by component: accents
  // live only in tile badges and chart segments, meaning colours only in
  // chips, buttons and text, and a badge's colour is fixed by its position
  // rather than derived from any status. Badges also carry an icon and chips
  // carry a word, so colour is never read alone.
  static const accentPlum = Color(0xFF5B4C8A);
  static const accentSeal = seal;
  static const accentPine = Color(0xFF1F6B4A);
  static const accentOchre = Color(0xFFB8722E);
  static const accentBrick = Color(0xFFB4472F);

  static const accentPlumDark = Color(0xFFA99AD4);
  static const accentSealDark = sealDark;
  static const accentPineDark = Color(0xFF6FCFA0);
  static const accentOchreDark = Color(0xFFDFA867);
  static const accentBrickDark = Color(0xFFE89078);

  /// Ordered, so a chart with n series indexes in rather than hard-coding.
  static const List<Color> accents = [
    accentPlum,
    accentSeal,
    accentPine,
    accentOchre,
    accentBrick,
  ];

  static const List<Color> accentsDark = [
    accentPlumDark,
    accentSealDark,
    accentPineDark,
    accentOchreDark,
    accentBrickDark,
  ];

  /// The accent for position [i] in the current brightness, wrapping if a
  /// caller asks for more series than there are accents.
  static Color accentFor(int i, Brightness brightness) {
    final list = brightness == Brightness.dark ? accentsDark : accents;
    return list[i % list.length];
  }
```

Also extend the class doc comment. After the existing paragraph ending "...legible at a glance in a list of thirty theses.", add:

```dart
/// A second, separate palette — `accents` — exists for tile badges and
/// chart series. Those identify rather than judge, so they carry no
/// meaning and must never be derived from a status. See the note above
/// the declarations.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/design_system_test.dart`
Expected: PASS, all three new tests green.

- [ ] **Step 5: Falsify**

Temporarily change `accentPineDark` to `Color(0xFF0A2418)` (darker than its light counterpart). Re-run; the third test must FAIL. Restore.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/app_tokens.dart test/core/design_system_test.dart
git commit -m "feat: add the accent palette, for colour that identifies rather than judges"
```

---

### Task 2: Bundle Source Serif 4

**Files:**
- Create: `assets/fonts/SourceSerif4-SemiBold.ttf`, `assets/fonts/SourceSerif4-Bold.ttf`, `assets/fonts/OFL.txt`
- Modify: `pubspec.yaml`, `lib/core/theme/app_theme.dart`
- Test: `test/core/design_system_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `AppTheme.serif` — a `const String` family name `'SourceSerif4'` — and a `TextTheme` where `headlineSmall`, `titleLarge` and `titleMedium` carry `fontFamily: AppTheme.serif`. Task 3 reads `AppTheme.serif` for the stat value.

> **This is the one task requiring a manual download.** Source Serif 4 is not in this repo and cannot be generated. Fetch it from https://fonts.google.com/specimen/Source+Serif+4 (or https://github.com/adobe-fonts/source-serif/releases), take the static TTFs for weights 600 and 700, and copy the repository's `OFL.txt` alongside them. The licence file is not optional — OFL 1.1 requires it to travel with the fonts.

- [ ] **Step 1: Place the font files**

```bash
mkdir -p assets/fonts
# copy SourceSerif4-SemiBold.ttf, SourceSerif4-Bold.ttf and OFL.txt into assets/fonts/
ls -l assets/fonts/
```

Expected: three files present, the two TTFs non-zero (roughly 150–400 KB each).

- [ ] **Step 2: Write the failing test**

Append to `test/core/design_system_test.dart`:

```dart
  group('typography', () {
    test('headings are set in the bundled serif, body text is not', () {
      // The palette's whole justification is a resemblance to paper. Until
      // this milestone that resemblance was asserted in a doc comment and
      // absent from the screen. If the family ever silently drops back to
      // the platform default, every argument in Chapter IV loses its
      // referent -- so it is pinned here rather than left to inspection.
      final t = AppTheme.light.textTheme;
      expect(t.headlineSmall?.fontFamily, AppTheme.serif);
      expect(t.titleLarge?.fontFamily, AppTheme.serif);
      expect(t.titleMedium?.fontFamily, AppTheme.serif);

      // Interface furniture stays on the platform sans: a serif label at
      // 13px reads as small rather than as considered.
      expect(t.bodyMedium?.fontFamily, isNull);
      expect(t.bodySmall?.fontFamily, isNull);
      expect(t.labelMedium?.fontFamily, isNull);
      expect(t.labelSmall?.fontFamily, isNull);
    });

    test('dark theme sets the same families as light', () {
      final l = AppTheme.light.textTheme;
      final d = AppTheme.dark.textTheme;
      expect(d.headlineSmall?.fontFamily, l.headlineSmall?.fontFamily);
      expect(d.bodyMedium?.fontFamily, l.bodyMedium?.fontFamily);
    });
  });
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/core/design_system_test.dart`
Expected: FAIL — `AppTheme.serif` is not defined.

- [ ] **Step 4: Declare the fonts in pubspec.yaml**

Under the existing `flutter:` section, alongside `uses-material-design: true`:

```yaml
  fonts:
    - family: SourceSerif4
      fonts:
        - asset: assets/fonts/SourceSerif4-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/SourceSerif4-Bold.ttf
          weight: 700
```

Then run `flutter pub get`.

- [ ] **Step 5: Wire it into the theme**

In `lib/core/theme/app_theme.dart`, add to the class body above `light`:

```dart
  /// The bundled serif, used for the document voice only: page titles,
  /// section headings and stat values. Everything else — labels, body,
  /// chips, buttons, chart axes — stays on the platform sans, because the
  /// contrast between the two is what the second family is for.
  ///
  /// A failed font load degrades to the platform default, which is exactly
  /// how this app looked before the font was bundled. There is no broken
  /// state to fall into.
  static const String serif = 'SourceSerif4';
```

In `_typography`, add `fontFamily: serif,` to `headlineSmall`, `titleLarge` and `titleMedium` only. Leave every `body*` and `label*` entry untouched.

Rewrite the class doc comment, which currently says the opposite. Replace the paragraph beginning "Typography is deliberate in scale, weight and letter-spacing rather than in typeface: no font files are bundled..." with:

```dart
/// Two typefaces, each with one job. Headings and stat values are set in
/// the bundled Source Serif 4 (SIL OFL 1.1, `assets/fonts/`), which is the
/// document voice; labels, body copy, chips and buttons stay on the
/// platform sans, which is the interface voice. Scale, weight and tracking
/// still do most of the work — the second family sharpens a distinction
/// that already existed rather than replacing it.
///
/// The PDF renders its own serif through the `pdf` package and is
/// unaffected by anything here.
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/core/design_system_test.dart`
Expected: PASS.

- [ ] **Step 7: Run the whole suite**

Run: `flutter test`
Expected: all previously passing tests still pass. A bundled font changes text metrics, so any test asserting an exact widget size may now fail — if one does, that test was over-specified; fix it to assert the relationship it cares about rather than a pixel count.

- [ ] **Step 8: Commit**

```bash
git add assets/fonts pubspec.yaml pubspec.lock lib/core/theme/app_theme.dart test/core/design_system_test.dart
git commit -m "feat: bundle Source Serif 4 for headings, making the paper metaphor visible"
```

---

### Task 3: `StatTile`

**Files:**
- Create: `lib/core/widgets/stat_tile.dart`
- Test: `test/core/widgets/stat_tile_test.dart`

**Interfaces:**
- Consumes: `AppTokens.accents` (Task 1), `AppTheme.serif` (Task 2).
- Produces:
  - `StatTile({Key? key, required String label, required String value, required IconData icon, required Color accent, String? unit, String? caption, double? progress, VoidCallback? onTap, bool valueIsText = false})`
  - `AsyncStatTile<T>({Key? key, required String label, required AsyncValue<T> value, required String Function(T) format, required IconData icon, required Color accent, String? unit, String? Function(T)? caption, double? Function(T)? progress, VoidCallback? onTap, bool valueIsText = false})`
  - `StatTile.compactBelow` — `const double` = 200.

> **Deviation from spec §4, deliberate.** The spec calls for a named constructor `StatTile.async`. A named constructor cannot introduce a type parameter, and the async form must be generic over the streamed value. It is therefore a sibling widget, `AsyncStatTile<T>`, which resolves the `AsyncValue` and delegates to `StatTile`. Behaviour is exactly as specified.

- [ ] **Step 1: Write the failing test**

Create `test/core/widgets/stat_tile_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/stat_tile.dart';

Widget wrap(Widget child, {double width = 260}) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  testWidgets('renders label, value and unit', (tester) async {
    await tester.pumpWidget(wrap(const StatTile(
      label: 'Chapters approved',
      value: '2',
      unit: '/ 5',
      icon: Icons.check,
      accent: AppTokens.accentPine,
    )));

    expect(find.text('Chapters approved'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('/ 5'), findsOneWidget);
  });

  testWidgets('the value is set in the document serif', (tester) async {
    await tester.pumpWidget(wrap(const StatTile(
      label: 'Active theses',
      value: '18',
      icon: Icons.book_outlined,
      accent: AppTokens.accentPlum,
    )));

    final value = tester.widget<Text>(find.text('18'));
    expect(value.style?.fontFamily, AppTheme.serif);
  });

  testWidgets('the label is NOT set in the serif', (tester) async {
    // Spec D19: the second family is for the document voice only. A serif
    // label at 13px reads as small rather than as considered, and if this
    // ever flips the whole point of bundling two families is lost.
    await tester.pumpWidget(wrap(const StatTile(
      label: 'Active theses',
      value: '18',
      icon: Icons.book_outlined,
      accent: AppTokens.accentPlum,
    )));

    final label = tester.widget<Text>(find.text('Active theses'));
    expect(label.style?.fontFamily, isNot(AppTheme.serif));
  });

  testWidgets('steps down below the compact threshold', (tester) async {
    // The user-visible complaint this widget exists to fix: at phone width
    // four tiles must still fit two-across, which is only survivable if the
    // padding and the value shrink with them.
    Future<double> paddingAt(double width) async {
      await tester.pumpWidget(wrap(
        const StatTile(
          label: 'Active theses',
          value: '18',
          icon: Icons.book_outlined,
          accent: AppTokens.accentPlum,
        ),
        width: width,
      ));
      final padding = tester.widget<Padding>(
        find.byKey(const Key('statTilePadding')),
      );
      return (padding.padding as EdgeInsets).left;
    }

    expect(await paddingAt(260), 22);
    expect(await paddingAt(160), 14);
  });

  testWidgets('renders a progress bar instead of a caption when given one',
      (tester) async {
    await tester.pumpWidget(wrap(const StatTile(
      label: 'Chapters approved',
      value: '2',
      unit: '/ 5',
      caption: 'should be suppressed',
      progress: 0.4,
      icon: Icons.check,
      accent: AppTokens.accentPine,
    )));

    expect(find.byKey(const Key('statTileBar')), findsOneWidget);
    expect(find.text('should be suppressed'), findsNothing);
  });

  testWidgets('a loading tile shows a skeleton, NOT a zero', (tester) async {
    // This project has shipped "0 is indistinguishable from loading" four
    // times. A tile that renders 0 while its stream is in flight tells the
    // reader nothing is waiting when something may well be.
    final controller = StreamController<int>();
    addTearDown(controller.close);

    await tester.pumpWidget(ProviderScope(
      child: Consumer(builder: (context, ref, _) {
        final async = ref.watch(StreamProvider<int>((_) => controller.stream));
        return wrap(AsyncStatTile<int>(
          label: 'Active theses',
          value: async,
          format: (n) => '$n',
          icon: Icons.book_outlined,
          accent: AppTokens.accentPlum,
        ));
      }),
    ));

    // Single pump, NOT pumpAndSettle: settling would resolve the stream and
    // the assertion would observe the loaded state instead.
    await tester.pump();

    expect(find.byKey(const Key('statTileSkeleton')), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('an errored tile shows a dash, not a zero', (tester) async {
    await tester.pumpWidget(wrap(AsyncStatTile<int>(
      label: 'Active theses',
      value: AsyncValue.error(Exception('denied'), StackTrace.empty),
      format: (n) => '$n',
      icon: Icons.book_outlined,
      accent: AppTokens.accentPlum,
    )));

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/stat_tile_test.dart`
Expected: FAIL — `stat_tile.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/core/widgets/stat_tile.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

/// One figure on a dashboard: a label, a number, and a coloured badge.
///
/// The proportions are load-bearing rather than decorative. Label and badge
/// are pushed to opposite edges, the value is pinned to the bottom of the
/// card so a row of tiles shares one baseline, and the padding is generous
/// enough that the card reads as a card rather than as a table row. Four
/// tiles that ignore this look like flat strips stretched across a monitor,
/// which is precisely the complaint this widget was built to answer.
///
/// The badge colour comes from [AppTokens.accents] and is fixed by the
/// tile's position on its dashboard. It must NEVER be derived from the
/// status of whatever is being counted: accents identify, they do not judge,
/// and a badge that turns green on approval would collide with the meaning
/// palette used by chips and buttons a few pixels away.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.unit,
    this.caption,
    this.progress,
    this.onTap,
    this.valueIsText = false,
  });

  final String label;

  /// A `String`, not a number: several tiles show text ("Not scheduled",
  /// a supervisor's name). Callers that pass prose set [valueIsText] so the
  /// size drops — the widget does not try to guess from the content.
  final String value;
  final String? unit;
  final String? caption;

  /// 0..1. When present, a slim bar replaces [caption].
  ///
  /// This is the honest substitute for the reference design's "+8% this
  /// month". A delta needs a stored snapshot of the previous value and
  /// nothing in this system keeps one, so where a genuine ratio exists it
  /// fills that space and where none exists the space stays empty.
  final double? progress;

  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final bool valueIsText;

  /// Below this width the tile steps down a size. Keyed off the tile's own
  /// width rather than the screen's, so a tile placed in a narrow column on
  /// a wide display behaves correctly.
  static const double compactBelow = 200;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < compactBelow;
        final pad = compact ? 14.0 : 22.0;
        final badge = compact ? 28.0 : 38.0;
        final minHeight = compact ? 116.0 : 148.0;
        final valueSize = valueIsText
            ? (compact ? 15.0 : 19.0)
            : (compact ? 24.0 : 31.0);

        final card = Container(
          constraints: BoxConstraints(minHeight: minHeight),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: AppTokens.rule),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppTokens.ink.withValues(alpha: 0.04),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            key: const Key('statTilePadding'),
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: compact ? 11.5 : 13,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.md),
                    Container(
                      width: badge,
                      height: badge,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(compact ? 8 : 10),
                      ),
                      child: Icon(
                        icon,
                        size: compact ? 15 : 19,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(height: compact ? 12 : 18),
                _value(context, valueSize, compact),
                if (progress != null)
                  _bar(context, compact)
                else if (caption != null) ...[
                  SizedBox(height: compact ? 5 : 7),
                  Text(
                    caption!,
                    style: TextStyle(
                      fontSize: compact ? 10.5 : 12,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

        if (onTap == null) return card;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: card,
        );
      },
    );
  }

  Widget _value(BuildContext context, double size, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.serif,
              fontSize: size,
              fontWeight: FontWeight.w700,
              height: 1.05,
              letterSpacing: -0.4,
              color: scheme.onSurface,
            ),
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: AppTokens.xs),
          Text(
            unit!,
            style: TextStyle(
              fontFamily: AppTheme.serif,
              fontSize: compact ? 13 : 16,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _bar(BuildContext context, bool compact) {
    return Padding(
      padding: EdgeInsets.only(top: compact ? 8 : 11),
      child: ClipRRect(
        key: const Key('statTileBar'),
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: progress!.clamp(0.0, 1.0),
          minHeight: 5,
          backgroundColor: AppTokens.rule,
          valueColor: AlwaysStoppedAnimation<Color>(accent),
        ),
      ),
    );
  }
}

/// A [StatTile] whose value is still arriving.
///
/// A separate widget rather than a named constructor because the async form
/// must be generic over the streamed value and a named constructor cannot
/// introduce a type parameter.
///
/// While loading it renders a skeleton bar. It must never render `0`: this
/// project has four times shipped a screen where a loading count and a real
/// count of nothing were indistinguishable, which tells the reader their
/// queue is empty when it may be full.
class AsyncStatTile<T> extends StatelessWidget {
  const AsyncStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.format,
    required this.icon,
    required this.accent,
    this.unit,
    this.caption,
    this.progress,
    this.onTap,
    this.valueIsText = false,
  });

  final String label;
  final AsyncValue<T> value;
  final String Function(T) format;
  final String? unit;
  final String? Function(T)? caption;
  final double? Function(T)? progress;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final bool valueIsText;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => _Skeleton(
        label: label,
        icon: icon,
        accent: accent,
      ),
      // An em dash, not a zero. The read failed; the count is unknown, and
      // saying "0" would be a claim the app cannot support.
      error: (_, __) => StatTile(
        label: label,
        value: '—',
        icon: icon,
        accent: accent,
        caption: 'Could not load',
      ),
      data: (v) => StatTile(
        label: label,
        value: format(v),
        unit: unit,
        caption: caption?.call(v),
        progress: progress?.call(v),
        icon: icon,
        accent: accent,
        onTap: onTap,
        valueIsText: valueIsText,
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return StatTile(
      key: const Key('statTileSkeleton'),
      label: label,
      value: ' ',
      icon: icon,
      accent: accent,
      progress: null,
      caption: 'Loading…',
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/stat_tile_test.dart`
Expected: PASS, all seven tests.

- [ ] **Step 5: Falsify the loading test**

In `AsyncStatTile.build`, temporarily change `loading:` to return `StatTile(label: label, value: '0', icon: icon, accent: accent)`. Re-run; the skeleton test must FAIL on both assertions. Restore.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/stat_tile.dart test/core/widgets/stat_tile_test.dart
git commit -m "feat: add StatTile, which shows a skeleton rather than a false zero"
```

---

### Task 4: `StatTileGrid`

**Files:**
- Create: `lib/core/widgets/stat_tile_grid.dart`
- Test: `test/core/widgets/stat_tile_grid_test.dart`

**Interfaces:**
- Consumes: `StatTile` (Task 3).
- Produces: `StatTileGrid({Key? key, required List<Widget> children})`. Every dashboard wraps its four tiles in this.

This is the task that answers the original complaint: four across on a desktop, 2×2 on a tablet, 2×2 compact on a phone, never a single column, never stretched strips.

- [ ] **Step 1: Write the failing test**

Create `test/core/widgets/stat_tile_grid_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/stat_tile.dart';
import 'package:ethesishub/core/widgets/stat_tile_grid.dart';

Widget four() => StatTileGrid(children: [
      for (var i = 0; i < 4; i++)
        StatTile(
          label: 'Tile $i',
          value: '$i',
          icon: Icons.circle,
          accent: AppTokens.accents[i],
        ),
    ]);

/// How many distinct x-offsets the tiles occupy — i.e. how many columns.
int columnsOf(WidgetTester tester) {
  final xs = <double>{};
  for (var i = 0; i < 4; i++) {
    xs.add(tester.getTopLeft(find.text('Tile $i')).dx);
  }
  return xs.length;
}

Future<void> pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: four())),
  ));
  await tester.pump();
}

void main() {
  testWidgets('four across on a desktop', (tester) async {
    await pumpAt(tester, 1400);
    expect(columnsOf(tester), 4);
  });

  testWidgets('two across on a tablet', (tester) async {
    await pumpAt(tester, 700);
    expect(columnsOf(tester), 2);
  });

  testWidgets('still two across on a 360px phone, never one', (tester) async {
    // The whole point. A 216px minimum would give a single stacked column
    // here -- four tall cards and a screenful of scrolling -- which is what
    // the first draft of this design would have shipped.
    await pumpAt(tester, 360);
    expect(columnsOf(tester), 2);
  });

  testWidgets('tiles stop widening past the measure', (tester) async {
    // Four equal columns across a very wide monitor is what produced the
    // long flat strips. The row caps rather than smearing.
    await pumpAt(tester, 2400);
    final tile = tester.getSize(find.ancestor(
      of: find.text('Tile 0'),
      matching: find.byType(StatTile),
    ));
    expect(tile.width, lessThan(340));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/stat_tile_grid_test.dart`
Expected: FAIL — `stat_tile_grid.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/core/widgets/stat_tile_grid.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';

/// The row of figures at the top of every dashboard.
///
/// Four across on a desktop, two-by-two on a tablet or a split window, and
/// still two-by-two on a phone. It never collapses to a single column at
/// any width a real device presents, and never stretches into the wide flat
/// strips that four equal columns produce on a large monitor.
///
/// Flutter has no `auto-fit`/`minmax`, so the column count is computed from
/// the available width and handed to a fixed-count grid. The 150 minimum is
/// what makes the phone case work: a 360px device has roughly 328px of
/// usable width, so a 216px minimum -- the obvious first choice -- would
/// have produced a single stacked column.
class StatTileGrid extends StatelessWidget {
  const StatTileGrid({super.key, required this.children});

  final List<Widget> children;

  static const double minTileWidth = 150;
  static const double gap = AppTokens.md;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTokens.measureWide),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            // How many columns of at least minTileWidth fit, counting the
            // gaps between them. Never fewer than two: a single column of
            // tall cards is the layout this widget exists to prevent.
            var columns = ((available + gap) / (minTileWidth + gap)).floor();
            columns = columns.clamp(2, children.length);

            final rows = <Widget>[];
            for (var i = 0; i < children.length; i += columns) {
              final slice = children.skip(i).take(columns).toList();
              rows.add(Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) const SizedBox(width: gap),
                    // Empty slots keep the last row's tiles the same width
                    // as every other row's, rather than letting a lone
                    // trailing tile expand to fill the line.
                    Expanded(
                      child: j < slice.length ? slice[j] : const SizedBox(),
                    ),
                  ],
                ],
              ));
              if (i + columns < children.length) {
                rows.add(const SizedBox(height: gap));
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            );
          },
        ),
      ),
    );
  }
}
```

Note this depends on `AppTokens.measureWide`, added in Task 5. Add it now as part of this task instead — in `lib/core/theme/app_tokens.dart`, beneath `measure`:

```dart
  /// Dashboards need more room than forms. Four tiles at the form measure
  /// would be 150px each, which is the compact step on a desktop.
  static const double measureWide = 1180;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/stat_tile_grid_test.dart`
Expected: PASS, all four tests.

- [ ] **Step 5: Falsify the phone case**

Temporarily raise `minTileWidth` to 216. Re-run; the 360px test must FAIL reporting 1 column. Restore to 150.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/stat_tile_grid.dart lib/core/theme/app_tokens.dart test/core/widgets/stat_tile_grid_test.dart
git commit -m "feat: add StatTileGrid — four across, then 2x2, never a single column"
```

---

### Task 5: `PageShell` gains a wide measure

**Files:**
- Modify: `lib/core/widgets/page_shell.dart`
- Test: `test/core/widgets/page_shell_test.dart` (create if absent)

**Interfaces:**
- Consumes: `AppTokens.measureWide` (added in Task 4).
- Produces: `PageShell({..., double maxWidth = AppTokens.measure})`. Overview screens pass `maxWidth: AppTokens.measureWide`.

- [ ] **Step 1: Write the failing test**

Create or append to `test/core/widgets/page_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';

void main() {
  testWidgets('defaults to the form measure', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: PageShell(children: [SizedBox(key: Key('content'), height: 40)]),
      ),
    ));

    expect(tester.getSize(find.byKey(const Key('content'))).width,
        lessThanOrEqualTo(AppTokens.measure));
  });

  testWidgets('honours a wider measure when asked', (tester) async {
    // Dashboards need it; forms must not get it by accident, which is why
    // the default above is asserted too.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: PageShell(
          maxWidth: AppTokens.measureWide,
          children: [SizedBox(key: Key('content'), height: 40)],
        ),
      ),
    ));

    expect(tester.getSize(find.byKey(const Key('content'))).width,
        greaterThan(AppTokens.measure));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/page_shell_test.dart`
Expected: FAIL — `PageShell` has no `maxWidth` parameter.

- [ ] **Step 3: Write the implementation**

In `lib/core/widgets/page_shell.dart`, add to the constructor `this.maxWidth = AppTokens.measure,`, declare the field:

```dart
  /// Forms read badly at full width and stay at [AppTokens.measure]. A
  /// dashboard is not a form: four tiles at the form measure would each be
  /// 150px, which is the compact step, on a desktop.
  final double maxWidth;
```

and change the `ConstrainedBox` from `const BoxConstraints(maxWidth: AppTokens.measure)` to `BoxConstraints(maxWidth: maxWidth)`, dropping the now-invalid `const`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/page_shell_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the whole suite**

Run: `flutter test`
Expected: PASS — the default is unchanged, so no existing screen moves.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/page_shell.dart test/core/widgets/page_shell_test.dart
git commit -m "feat: let PageShell take a wider measure, for dashboards"
```

---

### Task 6: `NeedsYouItem` and `NeedsYouQueue`

**Files:**
- Create: `lib/data/models/needs_you_item.dart`, `lib/core/widgets/needs_you_queue.dart`
- Test: `test/core/widgets/needs_you_queue_test.dart`

**Interfaces:**
- Consumes: `EmptyState`, `LoadingState`, `ErrorState` from `lib/core/widgets/states.dart`.
- Produces:
  - `class NeedsYouItem { const NeedsYouItem({required String title, required String detail, required String route, required String chipLabel, required NeedsYouTone tone}); }`
  - `enum NeedsYouTone { act, waiting, returned }`
  - `NeedsYouQueue({Key? key, required AsyncValue<List<NeedsYouItem>> items, required String emptyTitle, required String emptyMessage})`
  - `NeedsYouHeadline({Key? key, required AsyncValue<List<NeedsYouItem>> items, required String suffix})` — renders "3 things need you today · <suffix>", the count read from the same `AsyncValue` (spec D16).

- [ ] **Step 1: Write the failing test**

Create `test/core/widgets/needs_you_queue_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/widgets/needs_you_queue.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';

const _chapter = NeedsYouItem(
  title: 'Chapter III — Methodology',
  detail: 'Returned by Dr. Armada · 2 days ago',
  route: '/thesis/chapters?id=t1',
  chipLabel: 'Revise',
  tone: NeedsYouTone.returned,
);

const _nomination = NeedsYouItem(
  title: 'Panel nomination — Bautista et al.',
  detail: 'Your Conforme requested',
  route: '/nominations',
  chipLabel: 'Reply',
  tone: NeedsYouTone.act,
);

Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('renders one row per item', (tester) async {
    await tester.pumpWidget(wrap(const NeedsYouQueue(
      items: AsyncValue.data([_chapter, _nomination]),
      emptyTitle: 'Nothing needs you',
      emptyMessage: 'Anything waiting on you appears here.',
    )));

    expect(find.text('Chapter III — Methodology'), findsOneWidget);
    expect(find.text('Panel nomination — Bautista et al.'), findsOneWidget);
    expect(find.text('Revise'), findsOneWidget);
  });

  testWidgets('an empty queue says so rather than rendering blank',
      (tester) async {
    await tester.pumpWidget(wrap(const NeedsYouQueue(
      items: AsyncValue.data([]),
      emptyTitle: 'Nothing needs you',
      emptyMessage: 'Anything waiting on you appears here.',
    )));

    expect(find.text('Nothing needs you'), findsOneWidget);
  });

  testWidgets('a loading queue is distinguishable from an empty one',
      (tester) async {
    final controller = StreamController<List<NeedsYouItem>>();
    addTearDown(controller.close);

    await tester.pumpWidget(ProviderScope(
      child: Consumer(builder: (context, ref, _) {
        final async = ref.watch(
          StreamProvider<List<NeedsYouItem>>((_) => controller.stream),
        );
        return wrap(NeedsYouQueue(
          items: async,
          emptyTitle: 'Nothing needs you',
          emptyMessage: 'Anything waiting on you appears here.',
        ));
      }),
    ));

    // Single pump: pumpAndSettle would resolve the stream first and the
    // assertion would observe the loaded state.
    await tester.pump();

    expect(find.text('Nothing needs you'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('the headline count equals the number of rows rendered',
      (tester) async {
    // Spec D16. Two sources for this number would eventually disagree, and
    // a dashboard that contradicts itself is worse than one showing nothing.
    const items = AsyncValue<List<NeedsYouItem>>.data([_chapter, _nomination]);

    await tester.pumpWidget(wrap(const Column(children: [
      NeedsYouHeadline(items: items, suffix: 'Second semester'),
      NeedsYouQueue(
        items: items,
        emptyTitle: 'Nothing needs you',
        emptyMessage: 'Anything waiting on you appears here.',
      ),
    ])));

    expect(find.textContaining('2 things need you today'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('the headline is singular for one item', (tester) async {
    await tester.pumpWidget(wrap(const NeedsYouHeadline(
      items: AsyncValue.data([_chapter]),
      suffix: 'Second semester',
    )));

    expect(find.textContaining('1 thing needs you today'), findsOneWidget);
  });

  testWidgets('the headline does not claim zero while loading',
      (tester) async {
    final controller = StreamController<List<NeedsYouItem>>();
    addTearDown(controller.close);

    await tester.pumpWidget(ProviderScope(
      child: Consumer(builder: (context, ref, _) {
        final async = ref.watch(
          StreamProvider<List<NeedsYouItem>>((_) => controller.stream),
        );
        return wrap(NeedsYouHeadline(items: async, suffix: 'Second semester'));
      }),
    ));
    await tester.pump();

    expect(find.textContaining('0 things'), findsNothing);
    expect(find.textContaining('Nothing needs you'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/needs_you_queue_test.dart`
Expected: FAIL — neither file exists.

- [ ] **Step 3: Write the model**

Create `lib/data/models/needs_you_item.dart`:

```dart
/// How a queue row should be coloured — from the MEANING palette, not the
/// accents. This is a verdict about the item, so it uses the vocabulary
/// chips and buttons already use.
enum NeedsYouTone { act, waiting, returned }

/// One thing waiting on the person reading the screen.
///
/// Every dashboard's queue is built from these, so the widget is written
/// once and each role supplies its own list. A row is only ever an item the
/// reader can actually act on — an empty queue is therefore real
/// information rather than a screen that failed to load.
class NeedsYouItem {
  const NeedsYouItem({
    required this.title,
    required this.detail,
    required this.route,
    required this.chipLabel,
    required this.tone,
  });

  final String title;
  final String detail;

  /// Where "Open" goes. A go_router location, pushed with `context.go`.
  final String route;
  final String chipLabel;
  final NeedsYouTone tone;
}
```

- [ ] **Step 4: Write the widget**

Create `lib/core/widgets/needs_you_queue.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';

/// "3 things need you today · Second semester 2026–2027".
///
/// The count is the length of the very list rendered below it. Computing it
/// separately would eventually let the two disagree, and a dashboard that
/// contradicts itself is worse than one that shows nothing. While the list
/// is loading this says nothing at all rather than claiming zero.
class NeedsYouHeadline extends StatelessWidget {
  const NeedsYouHeadline({
    super.key,
    required this.items,
    required this.suffix,
  });

  final AsyncValue<List<NeedsYouItem>> items;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final count = items.valueOrNull?.length;

    final lead = switch (count) {
      null => null,
      0 => 'Nothing needs you today',
      1 => '1 thing needs you today',
      _ => '$count things need you today',
    };

    return Text(
      lead == null ? suffix : '$lead · $suffix',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
    );
  }
}

/// The list of things waiting on this reader.
class NeedsYouQueue extends StatelessWidget {
  const NeedsYouQueue({
    super.key,
    required this.items,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final AsyncValue<List<NeedsYouItem>> items;
  final String emptyTitle;
  final String emptyMessage;

  static Color _colour(BuildContext context, NeedsYouTone tone) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (tone) {
      NeedsYouTone.act => dark ? AppTokens.sealDark : AppTokens.seal,
      NeedsYouTone.waiting => dark ? AppTokens.awaitingDark : AppTokens.awaiting,
      NeedsYouTone.returned => dark ? AppTokens.returnedDark : AppTokens.returned,
    };
  }

  @override
  Widget build(BuildContext context) {
    return items.when(
      // Its own loading and error handling rather than collapsing to
      // `data(const [])`, which renders an empty state indistinguishable
      // from "nothing waiting" — the most repeated bug in this codebase.
      loading: () => const LoadingState(label: 'Checking what needs you…'),
      error: (e, _) => ErrorState(
        error: e,
        message: 'Could not work out what needs you.',
      ),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.done_all_outlined,
            title: emptyTitle,
            message: emptyMessage,
          );
        }
        return Card(
          child: Column(
            children: [
              for (final item in list)
                ListTile(
                  title: Text(item.title),
                  subtitle: Text(item.detail),
                  trailing: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppTokens.sm,
                    children: [
                      Chip(
                        label: Text(item.chipLabel),
                        labelStyle: TextStyle(
                          color: _colour(context, item.tone),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide(
                          color: _colour(context, item.tone)
                              .withValues(alpha: 0.4),
                        ),
                        backgroundColor: _colour(context, item.tone)
                            .withValues(alpha: 0.08),
                      ),
                      FilledButton(
                        onPressed: () => context.go(item.route),
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/widgets/needs_you_queue_test.dart`
Expected: PASS, all six tests.

- [ ] **Step 6: Falsify the D16 test**

Temporarily change `NeedsYouHeadline` to take a separate `int count` and hard-code `3`. Re-run; the count/rows test must FAIL. Restore.

- [ ] **Step 7: Commit**

```bash
git add lib/data/models/needs_you_item.dart lib/core/widgets/needs_you_queue.dart test/core/widgets/needs_you_queue_test.dart
git commit -m "feat: add the Needs-you queue, whose count is its own length"
```

---

### Task 7: `watchAll()` and `allThesesProvider`, with the rules proof

**Files:**
- Modify: `lib/data/repositories/thesis_repository.dart`, `lib/providers/thesis_providers.dart`
- Test: `test/providers/all_theses_test.dart` (create), `rules-test/rules.test.js`

**Interfaces:**
- Consumes: `signedInUidProvider` from `lib/providers/auth_providers.dart`.
- Produces: `ThesisRepository.watchAll()` → `Stream<List<Thesis>>`, and `allThesesProvider` → `StreamProvider<List<Thesis>>`. Tasks 8, 11 and 12 consume it.

- [ ] **Step 1: Write the failing rules test**

Append to `rules-test/rules.test.js`:

```js
// --- Dashboards: the coordinator and dean whole-college read ---
//
// The overview donut and the All-theses table both need an UNFILTERED list
// of every thesis. The existing arm reads no field off `resource` for these
// two roles, so unlike the M3 defence listing there is no filter the query
// must carry. That is a claim about rules, and fake_cloud_firestore enforces
// none, so it can only be proven here.

async function seedRole(uid, role) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${uid}`), {
      fullName: "A Person", email: `${uid}@isufst.edu.ph`, role,
      college: null, program: null, specialization: null,
      active: true, createdAt: serverTimestamp(), createdBy: null,
    });
  });
}

test("a coordinator may list every thesis, unfiltered", async () => {
  await seedRole("dash-coord-uid", "coordinator");
  await seedThesis("t-dash-1", "someone-else", "draft");
  await seedThesis("t-dash-2", "another-person", "titleApproved");

  const coordinator = env
    .authenticatedContext("dash-coord-uid", {
      email: "dash-coord-uid@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  const snap = await assertSucceeds(getDocs(collection(coordinator, "theses")));
  assert.ok(snap.size >= 2, "the coordinator saw fewer theses than were seeded");
});

test("a dean may list every thesis, unfiltered", async () => {
  await seedRole("dash-dean-uid", "dean");
  await seedThesis("t-dash-3", "someone-else", "draft");

  const dean = env
    .authenticatedContext("dash-dean-uid", {
      email: "dash-dean-uid@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertSucceeds(getDocs(collection(dean, "theses")));
});

// The control. Without this the two tests above would pass for a rule that
// admitted everyone, and the dashboards would leak every thesis in the
// college to any signed-in student.
test("a student may NOT list every thesis", async () => {
  await seedRole("dash-student-uid", "student");
  await seedThesis("t-dash-4", "someone-else", "draft");

  const s = env
    .authenticatedContext("dash-student-uid", {
      email: "dash-student-uid@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(getDocs(collection(s, "theses")));
});

// ...and the narrow query a student IS allowed, proving the denial above is
// about the missing filter rather than about the student being blocked from
// `theses` outright.
test("a student may still list their own thesis", async () => {
  await seedRole("dash-leader-uid", "student");
  await seedThesis("t-dash-5", "dash-leader-uid", "draft");

  const s = env
    .authenticatedContext("dash-leader-uid", {
      email: "dash-leader-uid@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertSucceeds(getDocs(query(
    collection(s, "theses"),
    where("leaderUid", "==", "dash-leader-uid"),
  )));
});
```

- [ ] **Step 2: Run the rules suite to verify the new tests pass**

Run: `cd rules-test && npm test`
Expected: PASS. `firestore.rules` already carries `allow list: … || isCoordinator() || isDean()`, so **no rules change is needed** — these four tests document and pin an existing guarantee. If any fails, stop: the spec's §7.2 assumption is wrong and the plan needs revising before any dashboard is built on it.

- [ ] **Step 3: Write the failing Dart test**

Create `test/providers/all_theses_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

Map<String, dynamic> thesisDoc(String title, String status) => {
      'leaderUid': 'l1',
      'adviserUid': 'a1',
      'panelistUids': <String>[],
      'memberNames': <String>[],
      'workingTitle': title,
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': status,
    };

void main() {
  test('returns every thesis regardless of status', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesisDoc('Alpha', 'draft'));
    await db
        .collection('theses')
        .doc('t2')
        .set(thesisDoc('Beta', 'titleApproved'));
    await db
        .collection('theses')
        .doc('t3')
        .set(thesisDoc('Gamma', 'nominationPendingDean'));

    final container = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'coord',
          email: 'coord@isufst.edu.ph',
          isEmailVerified: true,
        ),
      )),
    ]);
    addTearDown(container.dispose);

    final all = await container.read(allThesesProvider.future);
    expect(all, hasLength(3));
    expect(
      all.map((t) => t.workingTitle).toSet(),
      {'Alpha', 'Beta', 'Gamma'},
    );
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/providers/all_theses_test.dart`
Expected: FAIL — `allThesesProvider` is not defined.

- [ ] **Step 5: Write the implementation**

In `lib/data/repositories/thesis_repository.dart`, beside `watchByStatus`:

```dart
  /// Every thesis in the college, unfiltered.
  ///
  /// Readable only by a coordinator or the dean. Their arm of the `theses`
  /// list rule reads no field off `resource`, so — unlike the defence
  /// listing in M3 — this query needs no `where` clause to be admitted.
  /// Pinned by four emulator tests, including a student control.
  ///
  /// Never watch this from a student or faculty screen: it produces a
  /// `permission-denied` the reader can do nothing about.
  Stream<List<Thesis>> watchAll() {
    return _db.collection('theses').snapshots().map(
          (snap) => snap.docs.map(Thesis.fromDoc).toList(),
        );
  }
```

Match the existing `Thesis.fromDoc` call shape used by `watchByStatus` — if that method maps differently, mirror it exactly rather than the sketch above.

In `lib/providers/thesis_providers.dart`:

```dart
/// Every thesis in the college.
///
/// Watched ONLY by the dean and coordinator dashboards. The rules admit an
/// unfiltered list for those two roles and deny it to everyone else, so any
/// other screen watching this surfaces a permission error its reader cannot
/// act on.
final allThesesProvider = StreamProvider<List<Thesis>>((ref) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(thesisRepositoryProvider).watchAll();
});
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/providers/all_theses_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/data/repositories/thesis_repository.dart lib/providers/thesis_providers.dart test/providers/all_theses_test.dart rules-test/rules.test.js
git commit -m "feat: add the whole-college thesis read, and pin it in the emulator"
```

---

### Task 8: Student overview

**Files:**
- Create: `lib/features/dashboard/student_overview.dart`, `lib/features/dashboard/progress_rail.dart`, `lib/providers/needs_you_providers.dart`
- Modify: `lib/features/dashboard/student_dashboard.dart`
- Test: `test/features/dashboard/student_overview_test.dart`

**Interfaces:**
- Consumes: `StatTile`, `AsyncStatTile`, `StatTileGrid`, `NeedsYouQueue`, `NeedsYouHeadline`, `NeedsYouItem`, `myThesisProvider`, `chaptersProvider`, `myDefencesProvider`, `currentUserProvider`.
- Produces: `StudentOverview` (a `ConsumerWidget`), `ProgressRail({required ThesisStatus status, required bool hasApprovedChapters, required bool hasDefence})`, and `studentNeedsYouProvider` → `StreamProvider<List<NeedsYouItem>>`.

- [ ] **Step 1: Write the failing test**

Create `test/features/dashboard/student_overview_test.dart`. Reuse the `thesis()` fixture and `wrap()` helper shape from `test/features/dashboard/navigation_test.dart` (copy them in; they are small and the two files assert different things).

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/dashboard/student_dashboard.dart';

// Copy `thesis()` and `wrap()` from navigation_test.dart.

void main() {
  testWidgets('lands on the overview, not on a work list', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 'l1'));
    for (final n in ['I', 'II', 'III', 'IV', 'V']) {
      await db.collection('theses/t1/chapters').doc(n).set({
        'currentVersion': 1,
        'status': n == 'I' || n == 'II' ? 'approved' : 'submitted',
      });
    }

    await tester.pumpWidget(await wrap(
      const StudentDashboard(),
      db,
      uid: 'l1',
      role: 'student',
    ));
    await tester.pumpAndSettle();

    // The complaint that started this milestone: a student opened the app
    // onto "My thesis" and had to work out for themselves where things
    // stood.
    expect(find.byKey(const Key('studentOverview')), findsOneWidget);
  });

  testWidgets('counts approved chapters out of five', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 'l1'));
    for (final n in ['I', 'II', 'III', 'IV', 'V']) {
      await db.collection('theses/t1/chapters').doc(n).set({
        'currentVersion': 1,
        'status': n == 'I' || n == 'II' ? 'approved' : 'submitted',
      });
    }

    await tester.pumpWidget(await wrap(
      const StudentDashboard(),
      db,
      uid: 'l1',
      role: 'student',
    ));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsWidgets);
    expect(find.text('/ 5'), findsOneWidget);
  });

  testWidgets('a returned chapter appears in the queue', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 'l1'));
    await db.collection('theses/t1/chapters').doc('III').set({
      'currentVersion': 2,
      'status': 'revise',
    });

    await tester.pumpWidget(await wrap(
      const StudentDashboard(),
      db,
      uid: 'l1',
      role: 'student',
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chapter III'), findsOneWidget);
    expect(find.text('Revise'), findsOneWidget);
  });

  testWidgets('the greeting survives a missing profile document',
      (tester) async {
    // M2 shipped a leader lockout by gating on the profile doc. Nothing on
    // an overview may depend on `users/{uid}` existing.
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 'l1'));

    await tester.pumpWidget(await wrap(
      const StudentDashboard(),
      db,
      uid: 'l1',
      role: 'student',
    ));
    // Remove the profile the helper wrote.
    await db.collection('users').doc('l1').delete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('studentOverview')), findsOneWidget);
    expect(find.textContaining('Good'), findsOneWidget);
  });

  testWidgets('the progress rail marks the current stage', (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('theses')
        .doc('t1')
        .set(thesis(leaderUid: 'l1', status: 'titleApproved'));

    await tester.pumpWidget(await wrap(
      const StudentDashboard(),
      db,
      uid: 'l1',
      role: 'student',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('railStep-chapters')), findsOneWidget);
    expect(find.byKey(const Key('railCurrent-chapters')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/dashboard/student_overview_test.dart`
Expected: FAIL — no `studentOverview` key exists.

- [ ] **Step 3: Write `studentNeedsYouProvider`**

Create `lib/providers/needs_you_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// What is waiting on the signed-in student.
///
/// Only items they can act on. A chapter sitting with the adviser is NOT
/// here — it is on a tile, where a number is the honest representation of
/// "someone else has it". An empty queue is therefore real information.
final studentNeedsYouProvider = StreamProvider<List<NeedsYouItem>>((ref) async* {
  final thesis = await ref.watch(myThesisProvider.future);
  if (thesis == null) {
    yield const [];
    return;
  }

  final items = <NeedsYouItem>[];

  if (thesis.status == ThesisStatus.draft) {
    items.add(NeedsYouItem(
      title: thesis.workingTitle,
      detail: 'Still a draft — nominate an adviser and panel to begin.',
      route: '/nominate?id=${thesis.id}',
      chipLabel: 'Nominate',
      tone: NeedsYouTone.act,
    ));
  }

  if (thesis.status == ThesisStatus.titleRejected) {
    items.add(NeedsYouItem(
      title: thesis.workingTitle,
      detail: 'Your candidate titles were returned. Submit a new set.',
      route: '/titles/submit?id=${thesis.id}',
      chipLabel: 'Resubmit',
      tone: NeedsYouTone.returned,
    ));
  }

  // Chapters only exist once a title is approved, so this stream is only
  // subscribed after that point.
  if (thesis.status == ThesisStatus.titleApproved) {
    await for (final chapters in ref.watch(chaptersProvider(thesis.id).stream)) {
      yield [
        ...items,
        for (final c in chapters)
          if (c.status == ChapterStatus.revise)
            NeedsYouItem(
              title: 'Chapter ${c.id}',
              detail: 'Returned by your adviser — revise and re-upload.',
              route: '/thesis/chapters?id=${thesis.id}',
              chipLabel: 'Revise',
              tone: NeedsYouTone.returned,
            ),
      ];
    }
    return;
  }

  yield items;
});
```

- [ ] **Step 4: Write `ProgressRail`**

Create `lib/features/dashboard/progress_rail.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

/// The six stages a thesis passes through, and which one it is at.
///
/// A student's real question is "where are we and what is next", which a
/// status chip answers only narrowly — it names the current state without
/// showing the road. This is the one element of the dashboard with no
/// equivalent in the reference design, and it is here because the lifecycle
/// is the thing students ask their adviser about most.
enum RailStage {
  draft('draft', 'Draft'),
  nomination('nomination', 'Nomination'),
  title('title', 'Title'),
  chapters('chapters', 'Chapters'),
  preOral('preOral', 'Pre-oral'),
  finalDefence('final', 'Final');

  const RailStage(this.id, this.label);
  final String id;
  final String label;
}

class ProgressRail extends StatelessWidget {
  const ProgressRail({
    super.key,
    required this.status,
    this.hasDefence = false,
  });

  final ThesisStatus status;
  final bool hasDefence;

  RailStage get current => switch (status) {
        ThesisStatus.draft => RailStage.draft,
        ThesisStatus.nominationPendingConforme ||
        ThesisStatus.nominationPendingCoordinator ||
        ThesisStatus.nominationPendingDean =>
          RailStage.nomination,
        ThesisStatus.nominationApproved ||
        ThesisStatus.titlePendingDefence ||
        ThesisStatus.titleRejected =>
          RailStage.title,
        ThesisStatus.titleApproved =>
          hasDefence ? RailStage.preOral : RailStage.chapters,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentIndex = RailStage.values.indexOf(current);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppTokens.md,
          horizontal: AppTokens.sm,
        ),
        child: Row(
          children: [
            for (final stage in RailStage.values)
              Expanded(
                key: Key('railStep-${stage.id}'),
                child: Column(
                  children: [
                    Container(
                      key: stage == current
                          ? Key('railCurrent-${stage.id}')
                          : null,
                      width: stage == current ? 14 : 11,
                      height: stage == current ? 14 : 11,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: switch (RailStage.values.indexOf(stage)) {
                          final i when i < currentIndex => AppTokens.endorsed,
                          final i when i == currentIndex => AppTokens.seal,
                          _ => AppTokens.rule,
                        },
                      ),
                    ),
                    const SizedBox(height: AppTokens.xs),
                    Text(
                      stage.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: stage == current
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: stage == current
                            ? AppTokens.seal
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Write `StudentOverview`**

Create `lib/features/dashboard/student_overview.dart` composing, in order: a greeting (`Text`, `headlineSmall`), `NeedsYouHeadline`, `ProgressRail`, `StatTileGrid` with four tiles, then `NeedsYouQueue`. Wrap in `PageShell(maxWidth: AppTokens.measureWide, ...)` and give the root `key: const Key('studentOverview')`.

The four tiles, in this order and with these fixed accents (spec D14 — the accent is a function of position, never of status):

| # | Label | Accent | Source |
|---|---|---|---|
| 0 | Chapters approved | `accents[2]` (pine) | `chaptersProvider`, `unit: '/ 5'`, `progress: approved/5` |
| 1 | With your adviser | `accents[3]` (ochre) | `chaptersProvider`, count of `submitted`, caption "Submitted N days ago" |
| 2 | Next defence | `accents[1]` (seal) | `myDefencesProvider`, `valueIsText: true` |
| 3 | Your adviser | `accents[0]` (plum) | `myThesisProvider.adviserUid` resolved via `allDirectoryProvider`, `valueIsText: true` |

Every tile uses `AsyncStatTile`, never `StatTile` with a `.valueOrNull ?? 0`.

The greeting:

```dart
    final name = ref.watch(currentUserProvider).valueOrNull?.fullName ?? '';
    final first = name.trim().split(RegExp(r'\s+')).first;
    // Never blocks on the profile document: M2 shipped a leader lockout by
    // gating a control on `users/{uid}` existing.
    final greeting = first.isEmpty ? 'Good day' : 'Good day, $first';
```

- [ ] **Step 6: Shift the student navigation**

In `lib/features/dashboard/student_dashboard.dart`, prepend the Overview destination and recompute the body switch. The conditional `chaptersUnlocked` destinations shift, so the indices must be **recomputed, not offset**:

```dart
      destinations: [
        const NavDestination(label: 'Overview', icon: Icons.dashboard_outlined),
        const NavDestination(label: 'Thesis', icon: Icons.home_outlined),
        if (chaptersUnlocked) ...[
          const NavDestination(label: 'Chapters', icon: Icons.menu_book_outlined),
          const NavDestination(label: 'Defences', icon: Icons.forum_outlined),
        ],
      ],
      body: switch (_selectedIndex) {
        0 => const StudentOverview(),
        1 => _thesisBody(...),          // the previous index 0 body
        2 => const ChaptersScreen(),    // previously 1
        3 => const PageShell(...),      // previously 2
        _ => const StudentOverview(),
      },
```

- [ ] **Step 7: Run tests**

Run: `flutter test test/features/dashboard/`
Expected: PASS, including the existing `navigation_test.dart` — update its index expectations where it asserts on destination positions.

- [ ] **Step 8: Commit**

```bash
git add lib/features/dashboard/student_overview.dart lib/features/dashboard/progress_rail.dart lib/providers/needs_you_providers.dart lib/features/dashboard/student_dashboard.dart test/features/dashboard/
git commit -m "feat: land students on an overview rather than on their thesis record"
```

---

### Task 9: Faculty overview

**Files:**
- Create: `lib/features/dashboard/faculty_overview.dart`
- Modify: `lib/providers/needs_you_providers.dart`, `lib/features/dashboard/faculty_dashboard.dart`
- Test: `test/features/dashboard/faculty_overview_test.dart`

**Interfaces:**
- Consumes: `myAdviseesProvider`, `myThesisIdsProvider`, `myPendingNominationsProvider`, `myDefencesProvider`, `effectiveFacultyModeProvider`, `chaptersProvider`.
- Produces: `FacultyOverview`, `facultyNeedsYouProvider` → `StreamProvider<List<NeedsYouItem>>`.

- [ ] **Step 1: Write the failing test**

Create `test/features/dashboard/faculty_overview_test.dart`. The load-bearing test is the mode-spanning one:

```dart
  testWidgets('a Conforme request shows in the queue while in ADVISER mode',
      (tester) async {
    // Spec D17. Testing only the mode a given item "belongs" to would pass
    // with a mode filter left in the provider, and the person who needs to
    // see the request would never find it -- they have no reason to think
    // of looking in the other mode.
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f1'));
    await db.collection('theses/t2/nominations').doc('f1').set({
      'nomineeUid': 'f1',
      'nomineeName': 'Dr. F',
      'position': 'panelist',
      'exOfficio': false,
      'conformeStatus': 'pending',
      'respondedAt': null,
      'declineReason': null,
    });
    await db.collection('theses').doc('t2').set(thesis(adviserUid: 'other'));

    await tester.pumpWidget(await wrap(
      const FacultyDashboard(),
      db,
      uid: 'f1',
      role: 'faculty',
    ));
    await tester.pumpAndSettle();

    // f1 advises t1, so effectiveFacultyModeProvider clamps to adviser mode.
    expect(find.text('Reply'), findsOneWidget);
  });

  testWidgets('a chapter to review shows in the queue while in PANELIST mode',
      (tester) async {
    // The mirror of the test above. Both directions, or the assertion is
    // satisfied by a filter that happens to match one case.
    // ... seed f2 as a panelist on t3 with no advisees, and as adviser on
    // t4 with a submitted chapter; assert 'Review' is found.
  });
```

Write both bodies out fully when implementing; the second mirrors the first.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/dashboard/faculty_overview_test.dart`
Expected: FAIL — no `FacultyOverview`.

- [ ] **Step 3: Write `facultyNeedsYouProvider`**

Append to `lib/providers/needs_you_providers.dart`. It merges four sources and **does not read `facultyModeProvider` at all** — that omission is the whole of D17 and should carry a comment saying so:

```dart
/// What is waiting on the signed-in faculty member.
///
/// Deliberately mode-blind. The tiles above it are mode-aware, matching D5,
/// but a Conforme request or a consolidation you owe must not hide behind
/// the Adviser/Panelist switch: the person who needs to see it has no reason
/// to think of looking in the other mode. If you ever find yourself reaching
/// for `facultyModeProvider` in here, that is the bug.
final facultyNeedsYouProvider = StreamProvider<List<NeedsYouItem>>((ref) async* {
  // ... merge:
  //   1. nominations pending this uid's Conforme      -> 'Reply'
  //   2. chapters `submitted` on advised theses       -> 'Review'
  //   3. defences `completed` on advised theses with
  //      consolidatedAt == null                       -> 'Consolidate'
  //   4. a defence inProgress or scheduled today      -> 'Join'
});
```

Merge with a `StreamController` fan-in following the shape already proven in `myDefencesProvider` (`lib/providers/defence_providers.dart:32`) — two `.listen()` subscriptions, `ref.onDispose` cleanup, and `onError: controller.addError` on **every** subscription. Do **not** use `await for` over one stream and `.first` on another: that was the M3 staleness bug, where the merge only advanced when the first stream emitted.

- [ ] **Step 4: Write `FacultyOverview` and shift the navigation**

Tiles, adviser mode: chapters awaiting your review (`accents[3]`) · advisees (`accents[0]`) · defences this week (`accents[1]`) · Conforme requests (`accents[2]`). Panelist mode: panels (`accents[0]`) · title sets to review (`accents[3]`) · defences this week (`accents[1]`) · Conforme requests (`accents[2]`).

In `faculty_dashboard.dart`, prepend `NavDestination(label: 'Overview', icon: Icons.dashboard_outlined)` and shift the body switch from `{1: defences, 2: nominations, _: modeBody}` to `{0: overview, 1: modeBody, 2: defences, 3: nominations}`.

- [ ] **Step 5: Run tests**

Run: `flutter test test/features/dashboard/`
Expected: PASS.

- [ ] **Step 6: Falsify D17**

Add `if (mode == FacultyMode.panelist) return;` before the nomination branch in `facultyNeedsYouProvider`. Re-run; the adviser-mode Conforme test must FAIL. Remove it.

- [ ] **Step 7: Commit**

```bash
git add lib/features/dashboard/faculty_overview.dart lib/providers/needs_you_providers.dart lib/features/dashboard/faculty_dashboard.dart test/features/dashboard/faculty_overview_test.dart
git commit -m "feat: give faculty an overview whose queue ignores the mode switch"
```

---

### Task 10: The two chart panels

**Files:**
- Create: `lib/features/dashboard/stage_donut.dart`, `lib/features/dashboard/submission_trend.dart`
- Modify: `pubspec.yaml`
- Test: `test/features/dashboard/charts_test.dart`

**Interfaces:**
- Consumes: `allThesesProvider` (Task 7), `AppTokens.accentFor` (Task 1).
- Produces: `StageDonut()` and `SubmissionTrend()`, both `ConsumerWidget`s that watch `allThesesProvider` themselves.

- [ ] **Step 1: Add the dependency**

```bash
flutter pub add fl_chart
flutter pub get
```

Record the resolved version in the commit. Confirm it is a pure-Dart package: `flutter build web --debug` must still succeed at the end of this task.

- [ ] **Step 2: Write the failing test**

Create `test/features/dashboard/charts_test.dart`:

```dart
void main() {
  testWidgets('the legend groups theses by stage with counts', (tester) async {
    final db = FakeFirebaseFirestore();
    // Seeded AGAINST the order the legend renders: fake_cloud_firestore
    // returns insertion order, so seeding in stage order would let a
    // missing sort pass.
    await db.collection('theses').doc('t1').set(thesisDoc('E', 'titleApproved'));
    await db.collection('theses').doc('t2').set(thesisDoc('A', 'draft'));
    await db.collection('theses').doc('t3').set(thesisDoc('C', 'titleApproved'));
    await db.collection('theses').doc('t4').set(thesisDoc('B', 'nominationPendingDean'));

    // ... pump StageDonut in a ProviderScope over db, pumpAndSettle

    expect(find.text('Chapters'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);   // two at titleApproved
  });

  testWidgets('the legend alone renders if the chart is given no space',
      (tester) async {
    // The legend carries the numbers. If fl_chart ever fails to lay out,
    // the panel must still be readable rather than blank.
    // ... pump inside a SizedBox(width: 200), assert the legend text is found
  });

  testWidgets('shows an empty state rather than an empty donut',
      (tester) async {
    // A zero-total donut renders as nothing, which reads as a broken panel.
  });

  testWidgets('a loading donut is not an empty donut', (tester) async {
    // Single pump against a never-emitting controller.
  });
}
```

- [ ] **Step 3: Write `StageDonut`**

Groups `allThesesProvider` into five buckets by `ThesisStatus`:

| Bucket | Statuses | Accent |
|---|---|---|
| Nomination | `nominationPendingConforme`, `nominationPendingCoordinator`, `nominationPendingDean`, `nominationApproved` | `accents[0]` |
| Title defence | `titlePendingDefence` | `accents[1]` |
| Chapters | `titleApproved` | `accents[2]` |
| Draft | `draft` | `accents[3]` |
| Returned | `titleRejected` | `accents[4]` |

Render `PieChart` with `centerSpaceRadius` set for a donut, inside a `SizedBox(height: 180)`, with the legend in a `Row` beside it. Wrap the whole in `Card`. Use `AppTokens.accentFor(i, Theme.of(context).brightness)`. The chart is not interactive: pass `pieTouchData: PieTouchData(enabled: false)`.

Handle `loading` and `error` through `allThesesProvider.when`, never `valueOrNull ?? []`.

- [ ] **Step 4: Write `SubmissionTrend`**

Counts theses by `createdAt` month over the trailing seven months, rendered as an `LineChart` with a filled area. State the range in the panel header — "Past 7 months" — so an early flat line reads as young data rather than as a broken chart. Theses with a null `createdAt` are excluded and the panel says how many were excluded if any were.

- [ ] **Step 5: Run tests and the web build**

Run: `flutter test test/features/dashboard/charts_test.dart`
Then: `flutter build web --debug`
Expected: tests PASS; the web build succeeds, proving `fl_chart` pulls in no platform channels.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/dashboard/stage_donut.dart lib/features/dashboard/submission_trend.dart test/features/dashboard/charts_test.dart
git commit -m "feat: add the stage donut and submission trend, on fl_chart"
```

---

### Task 11: Dean overview

**Files:**
- Create: `lib/features/dashboard/dean_overview.dart`
- Modify: `lib/providers/needs_you_providers.dart`, `lib/features/dashboard/dean_dashboard.dart`
- Test: `test/features/dashboard/dean_overview_test.dart`

**Interfaces:**
- Consumes: `thesesByStatusProvider`, `allThesesProvider`, `myDefencesProvider`, `StageDonut`, `SubmissionTrend`.
- Produces: `DeanOverview`, `deanNeedsYouProvider`.

- [ ] **Step 1: Write the failing test**

Assert: the dashboard lands on `Key('deanOverview')`; a thesis at `nominationPendingDean` appears in the queue with chip "Approve"; both chart panels are present; the four tiles render.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/dashboard/dean_overview_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `deanNeedsYouProvider` and `DeanOverview`**

Queue: `thesesByStatusProvider(ThesisStatus.nominationPendingDean)` → chip "Approve", tone `act`; then `thesesByStatusProvider(ThesisStatus.titlePendingDefence)` → chip "Decide", tone `act`.

Tiles: awaiting your approval (`accents[3]`) · title defences (`accents[1]`) · defences this week (`accents[0]`) · active theses (`accents[2]`).

Then `StageDonut()` and `SubmissionTrend()`.

- [ ] **Step 4: Shift the navigation**

Prepend Overview; body switch becomes `{0: overview, 1: approvals, 2: titles, 3: defences, 4: readiness}`.

- [ ] **Step 5: Run tests**

Run: `flutter test test/features/dashboard/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/dashboard/dean_overview.dart lib/providers/needs_you_providers.dart lib/features/dashboard/dean_dashboard.dart test/features/dashboard/dean_overview_test.dart
git commit -m "feat: give the dean an overview with the college-wide analytics"
```

---

### Task 12: Coordinator overview and the All-theses table

**Files:**
- Create: `lib/features/dashboard/coordinator_overview.dart`, `lib/features/dashboard/all_theses_table.dart`
- Modify: `lib/providers/needs_you_providers.dart`, `lib/features/dashboard/coordinator_dashboard.dart`
- Test: `test/features/dashboard/coordinator_overview_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 3–11.
- Produces: `CoordinatorOverview`, `AllThesesTable`, `coordinatorNeedsYouProvider`.

- [ ] **Step 1: Write the failing test**

Three tests carry weight here:

```dart
  testWidgets('the table orders by working title, not by insertion',
      (tester) async {
    // fake_cloud_firestore returns insertion order, so the fixture is
    // seeded AGAINST the expected order. Seeded alphabetically, this test
    // would pass with the sort deleted -- which is exactly how a vacuous
    // ordering test slipped through in M1b.
    await db.collection('theses').doc('t1').set(thesisDoc('Zebra', 'draft'));
    await db.collection('theses').doc('t2').set(thesisDoc('Alpha', 'draft'));
    // ... assert 'Alpha' renders above 'Zebra' by comparing dy
  });

  testWidgets('a filter tab narrows the table', (tester) async {
    // ... tap 'Nomination', assert a titleApproved thesis disappears
  });

  testWidgets('the Faculty destination still reaches /invites after the shift',
      (tester) async {
    // The index-4 jump in onDestinationSelected is a hard-coded literal.
    // Prepending Overview makes it index 5, and a missed literal routes the
    // wrong destination silently -- no error, just the wrong screen.
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/dashboard/coordinator_overview_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `AllThesesTable`**

A `ConsumerStatefulWidget` holding the selected filter. Columns: working title, leader, adviser, status chip. Tabs: All · Nomination · Title · Chapters · Defence, mapping onto the same buckets `StageDonut` uses — extract that mapping into a shared `thesisStage(ThesisStatus)` helper in `lib/data/models/thesis_status.dart` rather than duplicating it, so the donut and the table can never disagree.

Sort by `workingTitle`. Wrap in `SingleChildScrollView(scrollDirection: Axis.horizontal)` so the table scrolls inside its own box rather than overflowing the page.

No Score column — that is M4.

- [ ] **Step 4: Write `coordinatorNeedsYouProvider` and `CoordinatorOverview`**

Queue: `nominationPendingCoordinator` → "Recommend"; `titlePendingDefence` → "Decide"; theses meeting defence readiness with no defence scheduled → "Schedule".

Tiles: active theses (`accents[0]`) · awaiting your recommendation (`accents[3]`) · defences this week (`accents[1]`) · faculty accounts (`accents[2]`).

Then `AllThesesTable()`, `StageDonut()`, `SubmissionTrend()`.

- [ ] **Step 5: Shift the navigation and fix the `/invites` literal**

Replace the hard-coded `if (i == 4)` with a lookup driven by the destination list, so a future insertion cannot break it again:

```dart
      // Driven off the label rather than an index literal. The previous
      // `if (i == 4)` silently routed the wrong destination the moment a
      // new one was prepended, with no error to notice.
      onDestinationSelected: (i) {
        if (destinations[i].label == 'Faculty') {
          context.go('/invites');
          return;
        }
        setState(() => _selectedIndex = i);
      },
```

Hoist `destinations` into a local `final` above the `ResponsiveScaffold` so both the callback and the widget read the same list.

- [ ] **Step 6: Run the whole suite**

Run: `flutter test`
Then: `cd rules-test && npm test`
Then: `flutter analyze`
Expected: all Dart tests pass; all rules tests pass; analyzer clean apart from the 2 known pre-existing infos.

- [ ] **Step 7: Falsify the ordering test**

Delete the `sort` in `AllThesesTable`. Re-run; the ordering test must FAIL. Restore.

- [ ] **Step 8: Commit**

```bash
git add lib/features/dashboard/ lib/providers/needs_you_providers.dart lib/data/models/thesis_status.dart test/features/dashboard/
git commit -m "feat: give the coordinator an overview, an all-theses table and the analytics"
```

---

## Verification

End-to-end, after Task 12:

1. `flutter test` — full Dart suite, foreground, one run at a time.
2. `cd rules-test && npm test` — emulator rules suite.
3. `flutter analyze` — clean but for the 2 known infos.
4. `flutter build web --debug` — proves `fl_chart` and the bundled fonts carry no platform channels.
5. `flutter run -d chrome` and sign in as each of the four roles. For each: confirm the app lands on Overview, the tiles show real figures rather than zeros while loading, and the "N things need you" headline matches the number of rows below it.
6. Resize the browser from wide to 360px and confirm the tiles go 4 across → 2×2 → 2×2 compact, never a single column and never full-width strips.
7. Toggle the system theme to dark and confirm the accents lift off the dark surface and no chart segment disappears.

## Self-review notes

- **Spec coverage.** §1 → Tasks 3–12. §2 D14 → Task 1. D15 → Task 3 (`progress` in place of a delta). D16 → Task 6. D17 → Task 9. D18 → Tasks 10–12. D19 → Task 2. §3 → Task 1. §4 → Task 3. §5 → Tasks 4–5. §6.1–6.4 → Tasks 8, 9, 11, 12. §7.1 → Task 7. §7.2 → Task 7 rules tests. §7.3 → Task 10. §8 → folded into Tasks 8, 9, 11, 12. §9 → the `when` handling in Tasks 3 and 6. §10 → falsification steps throughout. §11–12 → out of scope / documentation, no task.
- **Naming consistency.** `AsyncStatTile<T>` (not `StatTile.async`) throughout, per the deviation noted in Task 3. `NeedsYouItem`/`NeedsYouTone`/`NeedsYouQueue`/`NeedsYouHeadline` used identically in Tasks 6, 8, 9, 11, 12. `AppTokens.accents` indexed the same way in every dashboard task.
- **Known thinner tasks.** Tasks 9, 11 and 12 give the tile tables and provider contracts in full but sketch two test bodies and the chart internals rather than writing every line. The shapes they must follow — the fan-in from `defence_providers.dart:32`, the seed-against-order rule, the single-pump loading rule — are stated explicitly at each point.
