import Foundation

/// All dates in pump reports are wall-clock times. Keep source ticks as integers:
/// a Double cannot represent every 100 ns tick used in the legacy basal sample ID.
private struct PumpTimestamp {
    let ticks: Int64
    let date: Date

    init?(_ input: String, zone: TimeZone) {
        let input = input.count == 10 ? input + "T00:00:00" : input
        guard input.count >= 19 else { return nil }
        let base = input.prefix(19).replacingOccurrences(of: " ", with: "T")
        let style = Date.ISO8601FormatStyle()
        let suffix = input.dropFirst(19)
        var fraction = Substring()
        var zoneSuffix = suffix
        if suffix.first == "." {
            fraction = suffix.dropFirst().prefix(while: { $0.isASCII && $0.isNumber })
            guard (1...7).contains(fraction.count) else { return nil }
            zoneSuffix = suffix.dropFirst(fraction.count + 1)
        }
        guard zoneSuffix.isEmpty || zoneSuffix == "Z" || zoneSuffix.first == "+" || zoneSuffix.first == "-" else { return nil }
        let iso = base + (zoneSuffix.isEmpty ? "Z" : String(zoneSuffix))
        guard let wall = try? style.parse(iso),
              let fractionTicks = Int64(fraction + String(repeating: "0", count: 7 - fraction.count)) else { return nil }
        // Resolve offsets on either side of a transition. .NET uses the standard
        // time offset for both repeated and nonexistent local wall-clock values.
        let before = wall.addingTimeInterval(-86400)
        let after = wall.addingTimeInterval(86400)
        let beforeOffset = zone.secondsFromGMT(for: before)
        let afterOffset = zone.secondsFromGMT(for: after)
        var offset = beforeOffset
        if beforeOffset != afterOffset {
            let matches = [beforeOffset, afterOffset].filter {
                zone.secondsFromGMT(for: wall.addingTimeInterval(-Double($0))) == $0
            }
            offset = matches.count == 1 ? matches[0] : (zone.isDaylightSavingTime(for: before) ? afterOffset : beforeOffset)
        }
        let seconds = Int64(wall.timeIntervalSince1970.rounded()) - Int64(offset)
        ticks = (62_135_596_800 + seconds) * 10_000_000 + fractionTicks
        // Legacy JSONCodec truncated wire dates to milliseconds before HealthKit.
        date = Date(timeIntervalSince1970: Double(seconds) + Double(fractionTicks / 10_000) / 1000)
    }
}

enum TandemPumpReports {
    private struct PumpList: Decodable { let pumps: [Pump] }

    private struct Pump: Decodable {
        let assignmentId: String?
        let maxDateOfEvents: String?
        let lastUploadDate: String?

        enum Keys: CodingKey { case assignmentId, maxDateOfEvents, lastUploadDate }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            if let id = try? values.decode(Int64.self, forKey: .assignmentId) {
                assignmentId = String(id)
            } else {
                assignmentId = try values.decodeIfPresent(String.self, forKey: .assignmentId)
            }
            maxDateOfEvents = try values.decodeIfPresent(String.self, forKey: .maxDateOfEvents)
            lastUploadDate = try values.decodeIfPresent(String.self, forKey: .lastUploadDate)
        }
    }

    static func selectedPump(_ data: Data, zone: TimeZone) throws -> String {
        let devices = try JSONDecoder().decode(PumpList.self, from: data).pumps
        var selected: (id: String, latest: Int64)?
        for pump in devices {
            guard let id = pump.assignmentId, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let latest = pump.maxDateOfEvents.flatMap { PumpTimestamp($0, zone: zone)?.ticks }
                ?? pump.lastUploadDate.flatMap { PumpTimestamp($0, zone: zone)?.ticks } ?? .min
            if selected == nil || latest > selected!.latest { selected = (id, latest) }
        }
        guard let selected else { throw DirectTandemError.noPump }
        return selected.id
    }

    private struct Report: Decodable { let events: [ReportRow] }

    // The reports endpoint mixes event types. One malformed event should not
    // discard well-formed events from the same pump log.
    private struct ReportRow: Decodable {
        let event: Event?
        init(from decoder: Decoder) { event = try? Event(from: decoder) }
    }

    private struct Event: Decodable {
        let eventCode: Int
        let sequenceGroup: Int?
        let sequenceNumber: Int64
        let pumpDateTime: String
        let eventProperties: Properties
        enum Keys: CodingKey { case eventCode, sequenceGroup, sequenceNumber, pumpDateTime, eventProperties }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            eventCode = Int(try values.decode(Int32.self, forKey: .eventCode))
            sequenceNumber = try values.decode(Int64.self, forKey: .sequenceNumber)
            sequenceGroup = (try? values.decode(Int32.self, forKey: .sequenceGroup)).map(Int.init)
            pumpDateTime = try values.decode(String.self, forKey: .pumpDateTime)
            eventProperties = try values.decode(Properties.self, forKey: .eventProperties)
        }
        var sourceID: String { "\(eventCode)-\(sequenceGroup ?? 0)-\(sequenceNumber)" }
    }

    private struct Properties: Decodable {
        let bolusId: Int64?
        let carbAmount: Decimal?
        let insulinDelivered: Decimal?
        let completionStatus: Int?
        let commandedBasalRate: Decimal?
        let commandedRate: Decimal?

        enum Keys: CodingKey { case bolusId, carbAmount, insulinDelivered, completionStatus, commandedBasalRate, commandedRate }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            bolusId = try? values.decode(Int64.self, forKey: .bolusId)
            carbAmount = try? values.decode(Decimal.self, forKey: .carbAmount)
            insulinDelivered = try? values.decode(Decimal.self, forKey: .insulinDelivered)
            completionStatus = (try? values.decode(Int32.self, forKey: .completionStatus)).map(Int.init)
            commandedBasalRate = try? values.decode(Decimal.self, forKey: .commandedBasalRate)
            commandedRate = try? values.decode(Decimal.self, forKey: .commandedRate)
        }
    }

    private struct StampedSample {
        let startTicks: Int64
        let sample: SampleDTO
    }

    private struct Point {
        let event: Event
        let timestamp: PumpTimestamp

        func sample(pump: String, prefix: String, type: String, value: Decimal, unit: String, metadata: [String: String]) -> StampedSample {
            let sample = SampleDTO(externalId: prefix + "-" + event.sourceID, type: type, value: value, unit: unit,
                      startAt: timestamp.date, endAt: timestamp.date, metadata: metadata,
                      source: .init(deviceId: pump, eventIds: [event.sourceID]))
            return .init(startTicks: timestamp.ticks, sample: sample)
        }
    }

    private struct SequenceKey: Hashable { let group: Int; let number: Int64 }

    static func samples(_ data: Data, pump: String, zone: TimeZone, window: ClosedRange<Date>) throws -> [SampleDTO] {
        let events = try JSONDecoder().decode(Report.self, from: data).events
        var seen = Set<SequenceKey>()
        var points: [Point] = []
        for row in events {
            try Task.checkCancellation()
            guard let event = row.event, let stamp = PumpTimestamp(event.pumpDateTime, zone: zone) else { continue }
            let key = SequenceKey(group: event.sequenceGroup ?? 0, number: event.sequenceNumber)
            if seen.insert(key).inserted { points.append(Point(event: event, timestamp: stamp)) }
        }
        points.sort {
            if $0.timestamp.ticks != $1.timestamp.ticks { return $0.timestamp.ticks < $1.timestamp.ticks }
            return $0.event.sourceID < $1.event.sourceID
        }
        let tickWindow = utcTicks(window.lowerBound)...utcTicks(window.upperBound)
        var samples = try basalSamples(points: points, pump: pump, window: tickWindow)
        let inWindow = points.filter { tickWindow.contains($0.timestamp.ticks) }
        var requests = [Int64: [Point]]()
        for point in inWindow where point.event.eventCode == 64 {
            if let id = point.event.eventProperties.bolusId { requests[id, default: []].append(point) }
        }
        var linked = Set<String>()
        for point in inWindow where point.event.eventCode == 20 || point.event.eventCode == 21 {
            let properties = point.event.eventProperties
            guard let id = properties.bolusId, let delivered = properties.insulinDelivered else { continue }
            if delivered > 0 {
                samples.append(point.sample(pump: pump, prefix: "tandem-bolus-\(id)", type: "insulin.bolus", value: delivered,
                                            unit: "IU", metadata: ["deliveryReason": "bolus", "bolusId": String(id),
                                            "completionStatusRaw": String(properties.completionStatus ?? 0),
                                            "isExtended": point.event.eventCode == 21 ? "True" : "False"]))
            }
            guard let candidates = requests[id] else { continue }
            let latest = candidates.last(where: { $0.timestamp.ticks <= point.timestamp.ticks })?.timestamp.ticks
            // When multiple requests share a timestamp, preserve first source-ID
            // order, matching the stable OrderByDescending in the reference.
            let request = latest.flatMap { ticks in candidates.first(where: { $0.timestamp.ticks == ticks }) } ?? candidates[0]
            if let carbs = request.event.eventProperties.carbAmount, carbs > 0, linked.insert(request.event.sourceID).inserted {
                samples.append(request.sample(pump: pump, prefix: "tandem-carb-\(id)", type: "nutrition.carbohydrates",
                                              value: carbs, unit: "g", metadata: ["bolusId": String(id)]))
            }
        }
        return samples.sorted {
            $0.startTicks == $1.startTicks ? $0.sample.externalId < $1.sample.externalId : $0.startTicks < $1.startTicks
        }.map(\.sample)
    }

    private static func utcTicks(_ date: Date) -> Int64 {
        let seconds = date.timeIntervalSinceReferenceDate
        let whole = floor(seconds)
        // Keep the integer epoch separate to preserve the representable
        // subsecond precision of Foundation dates near the 2001 reference date.
        return 631_139_040_000_000_000 + Int64(whole) * 10_000_000 + Int64(((seconds - whole) * 10_000_000).rounded())
    }

    private static func basalSamples(points: [Point], pump: String, window: ClosedRange<Int64>) throws -> [StampedSample] {
        var basal: [(point: Point, rate: Decimal, kind: String)] = []
        for point in points {
            switch point.event.eventCode {
            case 3:
                if let rate = point.event.eventProperties.commandedBasalRate { basal.append((point, rate, "BasalRateChange")) }
            case 279:
                if let rate = point.event.eventProperties.commandedRate { basal.append((point, rate / 1000, "BasalDelivery")) }
            default: continue
            }
        }
        var result: [StampedSample] = []
        for (start, next) in zip(basal, basal.dropFirst()) {
            try Task.checkCancellation()
            let begin = start.point.timestamp
            let end = next.point.timestamp
            guard end.ticks > begin.ticks, end.ticks > window.lowerBound, begin.ticks < window.upperBound else { continue }
            // Reference code casts TimeSpan.TotalHours (a Double) to .NET
            // Decimal before multiplication, preserving 15 significant digits.
            let hours = Double(end.ticks - begin.ticks) / 36_000_000_000
            guard let decimalHours = Decimal(string: String(format: "%.15g", hours), locale: Locale(identifier: "en_US_POSIX")) else {
                throw DirectTandemError.invalidResponse
            }
            var delivered = start.rate * decimalHours
            var rounded = Decimal()
            NSDecimalRound(&rounded, &delivered, 6, .plain)
            guard rounded > 0 else { continue }
            var rate = start.rate
            var roundedRate = Decimal()
            NSDecimalRound(&roundedRate, &rate, 6, .plain)
            let source = start.point.event.sourceID
            let sample = SampleDTO(externalId: "tandem-basal-\(source)-\(begin.ticks)-\(end.ticks)", type: "insulin.basal",
                                value: rounded, unit: "IU", startAt: begin.date, endAt: end.date,
                                metadata: ["deliveryReason": "basal", "rateIUPerHour": NSDecimalNumber(decimal: roundedRate).stringValue,
                                           "sourceKind": start.kind], source: .init(deviceId: pump, eventIds: [source]))
            result.append(.init(startTicks: begin.ticks, sample: sample))
        }
        return result
    }
}
