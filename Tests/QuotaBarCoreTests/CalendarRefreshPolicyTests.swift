import Foundation
import Testing
@testable import QuotaBarCore

@Test func secondsUntilNextDayUsesLocalCalendarBoundary() throws {
    let calendar = Calendar(identifier: .gregorian)
    let now = try #require(DateComponents(calendar: calendar, year: 2026, month: 5, day: 10, hour: 23, minute: 59, second: 30).date)

    #expect(CalendarRefreshPolicy.secondsUntilNextDay(from: now, calendar: calendar) == 30)
}

@Test func secondsUntilNextDayNeverReturnsZeroOrNegative() throws {
    let calendar = Calendar(identifier: .gregorian)
    let midnight = try #require(DateComponents(calendar: calendar, year: 2026, month: 5, day: 11).date)

    #expect(CalendarRefreshPolicy.secondsUntilNextDay(from: midnight, calendar: calendar) == 86_400)
}
