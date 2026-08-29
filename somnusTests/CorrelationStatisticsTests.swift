import Testing
@testable import somnus

struct CorrelationStatisticsTests {

    @Test func pearsonRPerfectPositiveCorrelation() {
        let xs = [1.0, 2.0, 3.0, 4.0]
        let ys = [2.0, 4.0, 6.0, 8.0]
        #expect(abs(CorrelationStatistics.pearsonR(xs, ys)! - 1.0) < 1e-9)
    }

    @Test func pearsonRPerfectNegativeCorrelation() {
        let xs = [1.0, 2.0, 3.0, 4.0]
        let ys = [8.0, 6.0, 4.0, 2.0]
        #expect(abs(CorrelationStatistics.pearsonR(xs, ys)! - (-1.0)) < 1e-9)
    }

    @Test func pearsonRNoCorrelation() {
        let xs = [1.0, 2.0, 3.0, 4.0]
        let ys = [3.0, 1.0, 4.0, 1.0]
        let r = CorrelationStatistics.pearsonR(xs, ys)!
        #expect(abs(r) < 0.5)
    }

    @Test func pearsonRRequiresAtLeastThreePoints() {
        #expect(CorrelationStatistics.pearsonR([1.0, 2.0], [1.0, 2.0]) == nil)
    }

    @Test func pearsonRRequiresEqualLengths() {
        #expect(CorrelationStatistics.pearsonR([1.0, 2.0, 3.0], [1.0, 2.0]) == nil)
    }

    @Test func linearRegressionRecoversSlopeAndIntercept() {
        let xs = [1.0, 2.0, 3.0, 4.0]
        let ys = [3.0, 5.0, 7.0, 9.0] // y = 2x + 1
        let regression = CorrelationStatistics.linearRegression(xs, ys)!
        #expect(abs(regression.slope - 2.0) < 1e-9)
        #expect(abs(regression.intercept - 1.0) < 1e-9)
    }

    @Test func linearRegressionRequiresAtLeastThreePoints() {
        #expect(CorrelationStatistics.linearRegression([1.0, 2.0], [1.0, 2.0]) == nil)
    }
}
