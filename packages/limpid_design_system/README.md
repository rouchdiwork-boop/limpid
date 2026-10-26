# limpid_design_system

The design system of **Limpid**, the writing studio.

It is not a document: it is code. The tokens, the four themes and the
`Limpid*` widgets live in this package, and the same values are exported to
`tokens.json` so that the HTML mockups and the Figma library never drift
away from the application.

---

## Installation

The package lives in the Limpid monorepo. Add it to the `pubspec.yaml` of
`apps/limpid_app` with a path dependency:

```yaml
dependencies:
  limpid_design_system:
    path: ../../packages/limpid_design_system
```

Then import the barrel:

```dart
import 'package:limpid_design_system/limpid_design_system.dart';
```

The package has **no runtime dependency** other than Flutter. `google_fonts`
is forbidden: the four faces are embedded as OFL assets by the application,
never downloaded at runtime (see D-13).

---

## Setting up the theme

`LimpidTheme.of` builds the complete `ThemeData` of a variant:

```dart
import 'package:flutter/material.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

class LimpidApp extends StatelessWidget {
  const LimpidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      darkTheme: LimpidTheme.of(LimpidThemeVariant.night),
      home: const HomePage(),
    );
  }
}
```

`LimpidTheme.ofContext(context)` returns the theme of the closest `Theme`
ancestor.

### Reading the tokens inside a screen

`context.limpid` gives access to every token of the active variant:

```dart
Container(
  padding: EdgeInsets.all(context.limpid.spacing.space16),
  decoration: BoxDecoration(
    color: context.limpid.colors.bgSurface,
    borderRadius: BorderRadius.circular(context.limpid.radii.md),
    boxShadow: context.limpid.elevation.level1,
  ),
  child: Text(
    'Manuscrit',
    style: Theme.of(context).textTheme.titleMedium,
  ),
);
```

| Accessor | Content |
| --- | --- |
| `context.limpid.variant` | The active `LimpidThemeVariant`. |
| `context.limpid.colors` | Every color token (`LimpidColors`). |
| `context.limpid.spacing` | The 4pt spacing scale. |
| `context.limpid.radii` | The corner radius scale. |
| `context.limpid.motion` | The durations and the easing curves. |
| `context.limpid.elevation` | The five shadow levels. |

The palette is also reachable through the classic Flutter API:

```dart
final LimpidColors colors = Theme.of(context).extension<LimpidColors>()!;
```

---

## Adding a theme

A theme is a palette plus a brightness. To add one:

1. Add a `LimpidColorTokens` entry in `lib/src/tokens/colors.dart` with the
   twenty-two tokens of the palette.
2. Add the matching variant to the `LimpidThemeVariant` enum in
   `lib/src/theme/limpid_theme_variant.dart` and map it to the palette.
3. Regenerate the JSON export:

   ```bash
   flutter test tool/export_tokens.dart
   ```

4. Add the values to `tokens.json` — the generator writes them for you.
5. Extend `test/tokens_parity_test.dart` if the new variant needs a
   dedicated assertion.

The parity test fails as soon as the Dart constants and `tokens.json` stop
matching, so a new theme can never be half-deployed.

---

## Tokens

### Colors

The four palettes share the same twenty-two tokens.

| Token | paper | sepia | night | contrast |
| --- | --- | --- | --- | --- |
| `bgCanvas` | `#FAF8F4` | `#F4EBD8` | `#14110E` | `#000000` |
| `bgSurface` | `#FFFFFF` | `#FBF6EA` | `#1C1915` | `#000000` |
| `bgRaised` | `#FFFFFF` | `#FFFDF8` | `#242019` | `#0A0A0A` |
| `bgSunken` | `#F2EEE6` | `#E9DEC6` | `#0F0D0A` | `#000000` |
| `fgDefault` | `#16130F` | `#33281A` | `#F0EBE2` | `#FFFFFF` |
| `fgMuted` | `#57504A` | `#6B5C48` | `#A79E92` | `#FFFFFF` |
| `fgSubtle` | `#857C72` | `#8C7C64` | `#7A7268` | `#E6E6E6` |
| `borderSubtle` | `#E7E1D6` | `#DFD3B8` | `#2B261F` | `#FFFFFF` |
| `borderDefault` | `#D8D0C2` | `#CDBFA0` | `#3A332A` | `#FFFFFF` |
| `borderStrong` | `#BCB2A0` | `#B3A184` | `#4C4438` | `#FFFFFF` |
| `accent` | `#9C5518` | `#8E4A12` | `#E0A460` | `#FFB454` |
| `accentHover` | `#83450F` | `#763C0B` | `#F0BC85` | `#FFC87A` |
| `accentPressed` | `#6E3909` | `#633207` | `#C98E4A` | `#D99338` |
| `accentSubtle` | `#F6E7D6` | `#F0E0C8` | `#2E2418` | `#2A2013` |
| `accentBorder` | `#E4C4A0` | `#DCBC93` | `#4A3A22` | `#6B5223` |
| `fgOnAccent` | `#FFFFFF` | `#FFFFFF` | `#1A1207` | `#000000` |
| `secondary` | `#35407E` | `#2F3A72` | `#9BA4E8` | `#AEB6F5` |
| `secondarySubtle` | `#E8EAF7` | `#E4E7F5` | `#1E2138` | `#1A1D2E` |
| `success` | `#3E6B4F` | `#356043` | `#7FB093` | `#6ED79B` |
| `warning` | `#8A6410` | `#7A5810` | `#D9A845` | `#FFC44D` |
| `danger` | `#A8341F` | `#97301C` | `#E08573` | `#FF8A72` |
| `info` | `#2E5F7A` | `#28566F` | `#7FB3CE` | `#7FD4F5` |

### Typography

| Token | Family | Size | Line height | Weight | Letter spacing |
| --- | --- | --- | --- | --- | --- |
| `displayXl` | Fraunces | 40 | 42 | 600 | — |
| `displayL` | Fraunces | 32 | 38 | 600 | — |
| `displayM` | Fraunces | 26 | 32 | 600 | — |
| `titleL` | Fraunces | 22 | 28 | 600 | — |
| `titleM` | Fraunces | 18 | 24 | 600 | — |
| `titleS` | Instrument Sans | 15 | 21 | 600 | — |
| `bodyL` | Instrument Sans | 16 | 26 | 400 | — |
| `bodyM` | Instrument Sans | 14 | 22 | 400 | — |
| `bodyS` | Instrument Sans | 13 | 20 | 400 | — |
| `label` | Instrument Sans | 12 | 16 | 500 | 0.06em |
| `caption` | Instrument Sans | 11 | 15 | 500 | 0.04em |
| `mono` | IBM Plex Mono | 13 | 20 | 400 | — |
| `manuscript` | Literata | 18 | 32 | 400 | — |
| `manuscriptSm` | Literata | 16 | 28 | 400 | — |

The label style is uppercase. Flutter has no style level text
transformation, so the components apply it explicitly with
`LimpidTextTransform.label('…')`.

### Spacing, radii, elevation and motion

* **Spacing** (4pt base): `0, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48, 64,
  80, 96, 128`.
* **Radii**: `none 0`, `xs 4`, `sm 6`, `md 10`, `lg 14`, `xl 20`, `xxl 28`,
  `pill 999`.
* **Elevation**: `e0` (none) to `e4`. The dark palettes use black shadows and
  rely on a hairline border to separate the raised surfaces.
* **Motion**: `instant 0ms`, `fast 120ms`, `base 180ms`, `slow 260ms`,
  `slower 400ms`; curves `standard cubic-bezier(0.2,0,0,1)`,
  `decelerate cubic-bezier(0,0,0,1)`, `exit cubic-bezier(0.4,0,1,1)`,
  `emphasized cubic-bezier(0.2,0,0,1)`.

---

## Components

45 widgets, all prefixed with `Limpid`.

| Family | Components |
| --- | --- |
| Buttons | `LimpidButton`, `LimpidIconButton` |
| Inputs | `LimpidTextField`, `LimpidTextArea`, `LimpidSearchField` |
| Selection | `LimpidSelect`, `LimpidCombobox`, `LimpidSegmentedControl` |
| Toggles | `LimpidCheckbox`, `LimpidRadio`, `LimpidRadioGroup`, `LimpidSwitch`, `LimpidSlider` |
| Status | `LimpidBadge`, `LimpidChip`, `LimpidTag`, `LimpidBanner` |
| Overlays | `LimpidTooltip`, `LimpidMenu`, `LimpidDialog`, `LimpidBottomSheet`, `LimpidDrawer` |
| Navigation | `LimpidTabs`, `LimpidBreadcrumb`, `LimpidPagination`, `LimpidStepper` |
| Feedback | `LimpidLinearProgress`, `LimpidCircularProgress`, `LimpidSpinner`, `LimpidSnackbar`, `LimpidEmptyState` |
| Data | `LimpidDataTable`, `LimpidDataTableEmpty` |
| Surfaces | `LimpidCard`, `LimpidListTile`, `LimpidAvatar`, `LimpidStatCard` |
| Command | `LimpidCommandPalette`, `LimpidCommandPaletteOverlay` |
| Editor | `LimpidSceneCard`, `LimpidOutlineRow`, `LimpidCommentThread`, `LimpidAiSuggestionDiff`, `LimpidSyncStatusPill`, `LimpidCoverPreview`, `LimpidWordCountMeter`, `LimpidCharacterAvatar` |

---

## Usage rules

1. **No literal in a screen.** No `Color(0x…)`, no `TextStyle`, no
   `EdgeInsets.all(16)` outside this package. Read the tokens instead.
2. **One theme, four variants.** Every screen must be correct in `paper`,
   `sepia`, `night` and `contrast` without a single conditional.
3. **Accessibility (WCAG 2.2 AA).**
   * every interactive target is at least 44×44 (the theme uses
     `MaterialTapTargetSize.padded`);
   * the focus is always visible;
   * every widget exposes a correct `Semantics` contract;
   * a status is always carried by a color **and** an icon **and** a text.
4. **Immutability.** The components never mutate their input; they build a
   new widget tree on every change.
5. **No hardcoded strings in the widgets.** The design system accepts the
   texts as parameters: the application owns the translations.

---

## Development

```bash
flutter pub get
flutter analyze          # must report zero issue
flutter test             # widget tests and token parity
flutter test tool/export_tokens.dart   # regenerates tokens.json
dart format .
```

`tokens.json` is generated from the Dart constants — never edit it by hand.
The parity test in `test/tokens_parity_test.dart` compares both sources and
fails on any drift.
