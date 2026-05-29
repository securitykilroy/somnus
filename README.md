# Somnus

A native iOS sleep analysis app that reads your Apple Health sleep data and surfaces deep, actionable insights about your sleep quality, patterns, and health correlations.

## Overview

Somnus pulls all sleep data recorded by your Apple Watch or third-party sleep-tracking apps directly from HealthKit and presents it across three focused views: a nightly overview, a per-night deep dive, and long-term trend analysis. It goes beyond raw sleep duration by computing clinical sleep metrics—fragmentation, WASO, REM latency, sleep debt, and more—and cross-correlating sleep quality with daytime activity, resting heart rate, and heart rate variability.

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
- **CSV export** — share the selected night's summary, stage timeline, awake events, and movement evidence

### Trends Tab
- **Sleep debt chart** — bar chart of nightly surplus/deficit vs. a selectable 7- or 8-hour target, with a scrollable horizontal axis
- **Continuity chart** — multi-day view of fragmentation and awakening trends
- **Regularity chart** — tracks how consistent your mid-sleep anchor time is night over night
- **Movement/wake chart** — visualises out-of-bed events over time
- **CSV export** — share the visible range and the metrics that drive the trend and correlation charts

### Correlation Views
- **HRV trend** — daily HRV (SDNN) plotted against sleep duration
- **Resting heart rate vs. sleep** — resting HR overlaid on nightly sleep totals
- **Sleep HR trend** — average heart rate during each sleep window
- **Activity vs. next night's sleep** — scatter plot of daytime active calories vs. subsequent sleep duration, with a linear regression trend line
- **Activity vs. sleep continuity** — daytime active calories plotted against wake after sleep onset (WASO)

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
