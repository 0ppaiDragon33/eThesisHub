# EthesisHub UI rebuild (v2)

The palette in `lib/core/theme/app_tokens.dart` is unchanged. Routing,
providers, repositories, Firebase/Supabase access, role guards and
`firestore.rules` are untouched: every screen was rebuilt in place, so all
routes stay connected.

## Design system
- `lib/core/design/tone.dart`: `Tone` (act / endorsed / returned / awaiting /
  neutral) and `Palette` (brightness-aware neutrals, ink sidebar).
- `lib/core/design/panel.dart`: `Panel`, `ToneBadge` (icon + word, never
  colour alone), `InitialsAvatar`, `PersonLine`, `FactLine`.
- `lib/core/design/layout.dart`: `Breakpoint` (compact < 720 ≤ medium <
  1200 ≤ expanded), `SplitColumns`, `Dates`.
- `lib/core/design/metrics.dart`: `MetricStrip` / `Metric` (async, never a
  false zero), `SegmentBar`.
- `app_theme.dart`: canvas/paper surfaces, wider serif display scale,
  sentence-case labels, component themes.

## Navigation
- Ink sidebar at ≥ 720 px (labels at ≥ 1200 px, collapsible), paper top bar
  with a parent crumb and back control.
- Phones get bottom navigation; beyond five destinations the last slot is
  "More" (remaining destinations + account controls).
- `AppShell.railBreakpoint` is now 720.

## Removed
- `StatTile` / `StatTileGrid` (replaced by `MetricStrip`) and their tests.

## Before merging
The rebuild was written without a Flutter SDK available, so:
1. `flutter pub get && flutter analyze` and fix anything reported.
2. `flutter test`. Widget tests that assert the old layouts will need
   updating (examples: evaluation scores now render as "3/5"; the calendar
   key `awaitingDateHeading` is on a Column; `ProgressRail` nodes are
   `AnimatedContainer`s; nav destinations are custom items keyed
   `nav-<route>` instead of a `NavigationRail`). Keys used by tests were
   kept wherever the widget still exists.
3. Check the four role dashboards at phone, tablet and desktop widths.
