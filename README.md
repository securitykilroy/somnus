# Somnus

A native iOS sleep analysis app that reads your Apple Health sleep data and surfaces deep, actionable insights about your sleep quality, patterns, and health correlations.

## Overview

Somnus pulls all sleep data recorded by your Apple Watch or third-party sleep-tracking apps directly from HealthKit and presents it across three focused views: a nightly overview, a per-night deep dive, and long-term trend analysis. It goes beyond raw sleep duration by computing clinical sleep metrics—fragmentation, WASO, REM latency, sleep debt, and more—and cross-correlating sleep quality with daytime activity, resting heart rate, and heart rate variability.

It also records what you eat, via Siri or a Home Screen widget, so meal timing and content can be set against the night that followed. See [Meal Logging](#meal-logging).

## Features

### Overview Tab
- **Last night at a glance** — total sleep, efficiency, and bed/wake times in a large-print header
- **Sleep debt cards** — deficit vs. both 7- and 8-hour targets, as well as vs. your personal lifetime mean and median
- **Continuity metrics** — awakening count, out-of-bed events, wake after sleep onset (WASO), longest uninterrupted sleep block, and a fragmentation index
- **Insight list** — automatically generated observations surfaced from your history
- **7-day rollup** — weekly totals and means for sleep, debt, efficiency, and fragmentation
- **Data quality indicator** — confidence score derived from source count, overlapping samples, gaps, and conflicting segments across your HealthKit records

### Daily Tab
- **Night navigator** — swipe through every recorded night chronologically
- **Stats bar** — bedtime, wake time, total sleep, and efficiency at a glance
- **Detailed metric grid** — sleep latency, WASO, awakenings, REM latency, deep sleep %, REM %
- **Awake event list** — each awakening classified as *Restless in Bed*, *Likely Out of Bed*, or *Unknown*, with a confidence score driven by step count, walking distance, and Apple Stand Hour data
- **Hypnogram** — a timeline chart of sleep stages across the night (Core, Deep, REM, Awake, In Bed)
- **Stage duration breakdown** — proportional bar chart of time spent in each stage
- **CSV export** — share the selected night's summary, stage timeline, awake events, movement evidence, and meal entries

### Trends Tab
- **Sleep debt chart** — bar chart of nightly surplus/deficit vs. a selectable 7- or 8-hour target, with a scrollable horizontal axis
- **Continuity chart** — multi-day view of fragmentation and awakening trends
- **Regularity chart** — tracks how consistent your mid-sleep anchor time is night over night
- **Movement/wake chart** — visualises out-of-bed events over time
- **CSV export** — share the visible range and the metrics that drive the trend and correlation charts, including per-night meal columns

### Meal Logging
- **Log without opening the app** — Siri and the widget's quick button record through an App Intent, so nothing waits on the HealthKit load that a cold launch performs
- **Free-text entries** — a timestamp plus a rough description ("big pasta dinner", "two beers"); no calorie counts, portion sizes or preset categories
- **Meal timing vs. sleep** — hours between the last meal and sleep onset, scattered against efficiency, deep sleep %, and time awake in bed, plus a late-meal/early-meal comparison
- **In-app card** — correct a time logged late, attach a description to a bare widget tap, or delete a mis-tap
- **CSV export** — every night's meals travel with that night's sleep metrics in the same row

### Correlation Views
- **HRV trend** — daily HRV (SDNN) plotted against sleep duration
- **Resting heart rate vs. sleep** — resting HR overlaid on nightly sleep totals
- **Sleep HR trend** — average heart rate during each sleep window
- **Activity vs. next night's sleep** — scatter plot of daytime active calories vs. subsequent sleep duration, with a linear regression trend line
- **Activity vs. sleep continuity** — daytime active calories plotted against wake after sleep onset (WASO)
- **Meal timing vs. sleep** — hours from the last logged meal to sleep onset, against efficiency, deep sleep %, and time awake in bed

## Logging a Meal

Meal entries are recorded by an App Intent (`LogMealIntent`) declared with `openAppWhenRun = false`. It touches nothing but a small file in the shared App Group container, so logging never triggers the HealthKit fetch that a normal launch performs — the point of the feature is that it costs a couple of seconds, not thirty.

**Build and launch Somnus once on the device first.** App Shortcuts are published by the app at install time, and Siri will not recognise the phrases until the app has been launched at least once.

### Siri

Say any of:

- "Log a meal in Somnus"
- "Log what I ate in Somnus"
- "Record a meal in Somnus"
- "Log food in Somnus"

Siri replies "What did you eat?", you answer in plain language, and it confirms with the time it recorded. The description cannot ride inside the spoken phrase itself — App Shortcut phrases only interpolate `AppEnum` and `AppEntity` parameters, not free text — so the follow-up question is by design.

### Shortcuts app

Search the Shortcuts action library for **Log a Meal** (it appears under Somnus). The action exposes both parameters:

| Parameter | Notes |
|---|---|
| **What You Ate** | Free text. Prompts if left empty. |
| **Time** | Optional. Defaults to now — set it to backdate an entry. |

This is the path for "had a big pasta dinner at 4:30pm" in a single step, and for building automations — for example, running the action on a location or NFC trigger, or assigning it to the **Action Button** (Settings → Action Button → Shortcut → Log a Meal).

### Home Screen widget

Long-press the Home Screen → **Edit** → **Add Widget** → **Somnus** → **Meal Log**. Both sizes show the clock time of your last meal and offer two actions:

| Action | What happens |
|---|---|
| **Tap the widget** (small) / **Add meal…** (medium) | Opens Somnus straight to a text field with the keyboard up, via the `somnus://log-meal` URL. This is the only meal path that launches the app. |
| **Log time only** | Records the timestamp with no description, entirely inside the widget extension's process. The app is never launched. |

A widget button runs its App Intent headlessly and **cannot present a text field** — so recording *what* you ate necessarily means opening the app, or using Siri, which can prompt. The **Log time only** button exists for when you want the timing captured now and will fill in the description later from the Meals card.

The medium size also lists today's entries, with an undo button that appears for 15 minutes after a mis-tap.

### In the app

The **Meals** card on the Overview tab shows today's entries. Type a description and tap the fork icon to log immediately, or tap any entry to correct its time, attach a description to a bare widget tap, or delete it.

### Where the data goes

Entries live in `meal-log.json` inside the `group.com.washere.somnus` App Group container, written through `NSFileCoordinator` because the app and the widget extension can both append. They are not written to HealthKit, and they do not sync to iCloud or to the Watch app.

### In the CSV export

The Trends export carries each night's meals on that night's own row, so what was eaten sits beside `awakenings`, `waso_minutes`, `fragmentation_index` and the stage minutes without any joining:

| Column | Content |
|---|---|
| `meal_count` | Entries logged for that night |
| `first_meal_time` / `last_meal_time` | ISO-8601, UTC |
| `hours_last_meal_to_sleep` | Last meal to sleep onset |
| `meals` | `<timestamp>\|<what was eaten>` entries joined by `; ` |

A meal counts toward a night if it falls between the start of the previous calendar day and the moment sleep began — so a snack after midnight is attributed to the night it preceded, not the next one. `meal_count` of `0` means nothing was logged, not that nothing was eaten. The Daily export lists the same entries as individual `meal` rows, with the description in a `note` column.

## Technical Architecture

| Layer | Technology |
|---|---|
| UI | SwiftUI with Swift Charts |
| State management | Swift Observation (`@Observable`) |
| Data source | Apple HealthKit |
| Concurrency | Swift Structured Concurrency (`async`/`await`) |
| Minimum deployment | iOS 17 |

### Key components

- **`HealthKitManager`** — requests HealthKit authorisation and fetches sleep samples, step counts, walking distance, Apple Stand Hours, active calories, resting HR, HRV, and per-session heart rates
- **`SleepTimelineNormalizer`** — reconciles overlapping or conflicting sleep samples from multiple sources (Apple Watch, third-party apps) into a single authoritative timeline using a priority-based algorithm
- **`SleepSession`** — the central domain model; computes all derived metrics (efficiency, WASO, REM latency, fragmentation index, sleep debt, etc.) lazily from the normalized timeline
- **`AwakeEventDetector`** — classifies each awakening by correlating it with movement evidence windows pulled from HealthKit (steps, distance, Stand Hours), producing a confidence-weighted classification
- **`SleepStore`** — `@Observable` store that orchestrates data loading: sleep sessions first, then movement enrichment and health metrics in parallel background `Task`s
- **`SleepTrendSummary`** — aggregates sessions over configurable windows to compute regularity scores, debt trends, and weekly summaries
- **`MealLogStore`** — the shared meal log; a coordinated JSON file in the App Group container, readable and writable from the app, the widget extension and the intents alike
- **`LogMealIntent`** / **`SomnusAppShortcuts`** — the Siri and Shortcuts entry point, in the app target; `QuickLogMealIntent` and `UndoLastMealIntent` live in the widget extension instead, so each intent is registered by exactly one binary
- **`MealDeepLink`** / **`MealEntrySheet`** — the `somnus://log-meal` route the widget uses when an entry needs typing, and the sheet it opens over whatever the app is already showing
- **`MealSleepAnalyzer`** — pairs each night with everything eaten from the previous morning up to sleep onset, and splits nights into late- and early-meal groups for comparison

### HealthKit data types read

| Type | Purpose |
|---|---|
| `HKCategoryTypeIdentifierSleepAnalysis` | Sleep stages (Core, Deep, REM, Awake, In Bed) |
| `HKQuantityTypeIdentifierStepCount` | Movement evidence during awake segments |
| `HKQuantityTypeIdentifierDistanceWalkingRunning` | Out-of-bed distance confirmation |
| `HKQuantityTypeIdentifierActiveEnergyBurned` | Activity–sleep correlation |
| `HKQuantityTypeIdentifierRestingHeartRate` | Cardiovascular trends |
| `HKQuantityTypeIdentifierHeartRateVariabilitySDNN` | HRV trends |
| `HKQuantityTypeIdentifierHeartRate` | Per-session sleep heart rate |
| `HKCategoryTypeIdentifierAppleStandHour` | Stand-hour based out-of-bed detection |

## Requirements

- iOS 17.0 or later
- iPhone with Apple Health access
- An Apple Watch or compatible third-party app that records sleep stages to Apple Health (e.g., AutoSleep, Sleep Cycle, Pillow)
- Xcode 15 or later (to build from source)

## Building

1. Clone the repository
2. Open `somnus.xcodeproj` in Xcode
3. Select your development team in **Signing & Capabilities**
4. Build and run on a physical device (HealthKit is not available in the Simulator)

> **Note:** On first launch, Somnus will prompt for permission to read the HealthKit data types listed above. All data stays on your device — Somnus has no network access and does not transmit any health data.

## Privacy

Somnus requests read-only access to HealthKit. It never writes to HealthKit, never uploads data to any server, and has no analytics or tracking of any kind. The app entitlement is `com.apple.developer.healthkit` (read-only).

## License

Released under the [CC0 1.0 Universal](LICENSE) public domain dedication. You may use, modify, and distribute this software for any purpose without restriction or attribution.
