import Testing
@testable import QuotaBarCore

@Test func alertStateTrackerEmitsOnlyNewActiveAlertsAndAllowsRenotifyAfterRecovery() {
    var tracker = UsageAlertStateTracker()
    let lowBalance = UsageAlertCandidate(
        id: "low-balance",
        kind: .lowBalance,
        title: "Low",
        body: "Low balance"
    )

    #expect(tracker.alertsToNotify(from: [lowBalance]).map(\.id) == ["low-balance"])
    #expect(tracker.alertsToNotify(from: [lowBalance]).isEmpty)
    #expect(tracker.alertsToNotify(from: []).isEmpty)
    #expect(tracker.alertsToNotify(from: [lowBalance]).map(\.id) == ["low-balance"])
}
