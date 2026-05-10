import Foundation

public enum UsageAggregator {
    public static func aggregate(_ records: [UsageRecord]) throws -> UsageSummary {
        var rowsByModel: [String: UsageModelSummary] = [:]
        var promptCacheHitTokens = 0
        var promptCacheMissTokens = 0
        var completionTokens = 0
        var totalTokens = 0
        var totalCost = Decimal.zero

        for record in records {
            let canonicalModel = try DeepSeekPricing.canonicalModel(for: record.model)
            let pricing = try DeepSeekPricing.pricing(for: record.model)
            let inputTokens = record.promptCacheHitTokens + record.promptCacheMissTokens
            let outputTokens = record.completionTokens
            let cost = pricing.costUSD(
                promptCacheHitTokens: record.promptCacheHitTokens,
                promptCacheMissTokens: record.promptCacheMissTokens,
                completionTokens: record.completionTokens
            )

            promptCacheHitTokens += record.promptCacheHitTokens
            promptCacheMissTokens += record.promptCacheMissTokens
            completionTokens += record.completionTokens
            totalTokens += inputTokens + outputTokens
            totalCost += cost

            var row = rowsByModel[canonicalModel] ?? UsageModelSummary(
                model: canonicalModel,
                inputTokens: 0,
                outputTokens: 0,
                totalCostUSD: .zero,
                promptCacheHitTokens: 0,
                promptCacheMissTokens: 0,
                completionTokens: 0
            )
            row.promptCacheHitTokens += record.promptCacheHitTokens
            row.promptCacheMissTokens += record.promptCacheMissTokens
            row.completionTokens += record.completionTokens
            row.inputTokens += inputTokens
            row.outputTokens += outputTokens
            row.totalCostUSD += cost
            rowsByModel[canonicalModel] = row
        }

        return UsageSummary(
            promptCacheHitTokens: promptCacheHitTokens,
            promptCacheMissTokens: promptCacheMissTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            totalCostUSD: totalCost,
            byModel: ModelBreakdown(rowsByModel.values.sorted { $0.model < $1.model })
        )
    }

    public static func summary(
        for events: [UsageEvent],
        interval: DateInterval
    ) -> UsageSummary {
        let filtered = events.filter { interval.contains($0.timestamp) }
        var rowsByModel: [String: UsageModelSummary] = [:]
        var promptCacheHitTokens = 0
        var promptCacheMissTokens = 0
        var completionTokens = 0
        var totalTokens = 0
        var totalCost = Decimal.zero

        for event in filtered {
            promptCacheHitTokens += event.usage.cacheHitInputTokens
            promptCacheMissTokens += event.usage.cacheMissInputTokens
            completionTokens += event.usage.outputTokens
            totalTokens += event.usage.totalTokens
            totalCost += event.costUSD

            var row = rowsByModel[event.model] ?? UsageModelSummary(
                model: event.model,
                inputTokens: 0,
                outputTokens: 0,
                totalCostUSD: .zero,
                promptCacheHitTokens: 0,
                promptCacheMissTokens: 0,
                completionTokens: 0
            )
            row.promptCacheHitTokens += event.usage.cacheHitInputTokens
            row.promptCacheMissTokens += event.usage.cacheMissInputTokens
            row.completionTokens += event.usage.outputTokens
            row.inputTokens += event.usage.inputTokens
            row.outputTokens += event.usage.outputTokens
            row.totalCostUSD += event.costUSD
            rowsByModel[event.model] = row
        }

        return UsageSummary(
            promptCacheHitTokens: promptCacheHitTokens,
            promptCacheMissTokens: promptCacheMissTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            totalCostUSD: totalCost,
            byModel: ModelBreakdown(rowsByModel.values.sorted { $0.model < $1.model })
        )
    }

    public static func dailyTrend(
        for events: [UsageEvent],
        interval: DateInterval,
        calendar: Calendar = .current
    ) -> [DailyUsagePoint] {
        let startDay = calendar.startOfDay(for: interval.start)
        let endDay = calendar.startOfDay(for: interval.end)
        var pointsByDay: [Date: DailyUsagePoint] = [:]
        var day = startDay

        while day < endDay {
            pointsByDay[day] = DailyUsagePoint(day: day, totalTokens: 0, totalCostUSD: .zero)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = next
        }

        for event in events where interval.contains(event.timestamp) {
            let eventDay = calendar.startOfDay(for: event.timestamp)
            guard var point = pointsByDay[eventDay] else {
                continue
            }
            point.totalTokens += event.usage.totalTokens
            point.totalCostUSD += event.costUSD
            pointsByDay[eventDay] = point
        }

        return pointsByDay.values.sorted { $0.day < $1.day }
    }
}
