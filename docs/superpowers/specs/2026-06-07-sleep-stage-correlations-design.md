# Sleep Stage ↔ Activity/HRV Correlations — Design

## Goal

Add a Trends-tab feature that shows how sleep stage composition (Deep %, REM %,
Fragmentation) relates to (a) the prior day's activity level and (b) the
following morning's HRV — with scatter plots, regression lines, and Pearson
correlation coefficients, matching the visual language of the existing
Correlations cards (`ActivitySleepCorrelationView`, `HRVTrendView`, etc.).

## Data already available

- `SleepSession.deepRatio` / `.remRatio` / `.fragmentationIndex` — per-night
  stage composition (0–1).
- `SleepStore.dailyCalories` — `[DailyMetricSample]`, active-energy by day.
- `SleepStore.dailyHRV` — `[DailyMetricSample]`, daily HRV (requires Apple
  Watch).
- Existing convention (see `ActivitySleepCorrelationView`): activity on day
  `nightDate - 1` pairs with that night's sleep (`nightDate`); HRV/heart-rate
  keyed directly on `session.nightDate` represents the morning after
  (`SleepHRActivityView` keys `sleepHeartRates` the same way).

## New pieces

### 1. `Models/CorrelationStatistics.swift`

Pure-function helper, factored out of the duplicated regression code already
present in `ActivitySleepCorrelationView` / `SleepHRActivityView`:

```swift
enum CorrelationStatistics {
    static func linearRegression(_ xs: [Double], _ ys: [Double]) -> (slope: Double, intercept: Double)?
    static func pearsonR(_ xs: [Double], _ ys: [Double]) -> Double?
}
```

Both require `xs.count == ys.count && xs.count >= 3`, returning `nil`
otherwise (mirrors the existing `count >= 3` gate).

### 2. `Views/Correlations/MetricScatterChartView.swift`

Generic reusable scatter card body (not a full `.regularMaterial` card —
just the chart + caption block) used by both new views to avoid copy-pasting
chart code three times per card:

```swift
struct MetricScatterChartView: View {
    let points: [(x: Double, y: Double)]
    let color: Color
    let xAxisLabel: String
    let yAxisLabel: String
    let title: String          // e.g. "Deep Sleep %"
    let interpretation: (Double) -> String   // slope -> caption text
}
```

Renders: title, `PointMark` scatter, dashed regression `LineMark` (when
regression exists), axis labels, and a caption row showing
`"r = 0.42 · " + interpretation(slope)` (or "Not enough data" when fewer
than 3 paired points).

### 3. `Views/Correlations/ActivityToSleepStagesView.swift`

Card titled **"Activity vs Sleep Stage Composition"**, subtitle "Active
calories on day N vs stage makeup of sleep that night." Builds paired points
the same way `ActivitySleepCorrelationView` does (prior-day calories ↔
session), then renders three `MetricScatterChartView`s stacked vertically:

- Deep % (x = calories, y = `deepRatio * 100`)
- REM % (x = calories, y = `remRatio * 100`)
- Fragmentation (x = calories, y = `fragmentationIndex`)

Empty state: "No paired activity and sleep data available" (matches sibling
cards).

### 4. `Views/Correlations/SleepStagesToNextDayHRVView.swift`

Card titled **"Sleep Stages vs Next-Day HRV"**, subtitle "Stage composition
of last night's sleep vs HRV the following morning." Pairs each session's
`deepRatio`/`remRatio`/`fragmentationIndex` with `dailyHRV` keyed on
`session.nightDate` (same lookup pattern as `HRVTrendView`/
`ActivitySleepCorrelationView`, via a `Calendar.startOfDay` dictionary).
Three `MetricScatterChartView`s:

- Deep % (x = `deepRatio * 100`, y = HRV ms)
- REM % (x = `remRatio * 100`, y = HRV ms)
- Fragmentation (x = `fragmentationIndex`, y = HRV ms)

Empty state: "No HRV data available — requires Apple Watch" (matches
`HRVTrendView`).

## Wiring

In `TrendsView.correlationsSection`, add the two new cards after the existing
five, passing `visibleSessions`, `filteredCalories`, and `filteredHRV` (all
already computed in `TrendsView`).

## Testing

- Unit tests for `CorrelationStatistics.pearsonR` / `linearRegression`
  (known datasets: perfect positive/negative correlation, no correlation,
  insufficient data) in `somnusTests/`.
- Visual check in the simulator: confirm cards render with real HealthKit
  data, and confirm empty states render when filtered data is sparse (e.g.
  7-day range with no Watch data).

## Out of scope

- Refactoring existing correlation views (`ActivitySleepCorrelationView`,
  `SleepHRActivityView`) to use the new shared helpers — left as-is to keep
  this change focused, though they are natural future cleanup candidates.
- p-values / statistical significance testing.
- Core sleep % correlation (deferred per user preference for Deep + REM +
  fragmentation focus).
