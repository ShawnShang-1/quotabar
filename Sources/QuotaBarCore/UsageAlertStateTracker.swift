public struct UsageAlertStateTracker: Equatable, Sendable {
    private var alreadyNotifiedIDs = Set<String>()

    public init() {}

    public mutating func alertsToNotify(from activeAlerts: [UsageAlertCandidate]) -> [UsageAlertCandidate] {
        let activeIDs = Set(activeAlerts.map(\.id))
        alreadyNotifiedIDs.formIntersection(activeIDs)

        let newAlerts = activeAlerts.filter { !alreadyNotifiedIDs.contains($0.id) }
        alreadyNotifiedIDs.formUnion(newAlerts.map(\.id))
        return newAlerts
    }
}
