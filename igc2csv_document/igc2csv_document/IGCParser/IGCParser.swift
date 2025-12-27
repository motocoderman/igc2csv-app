//
//  IGCParser.swift
//  igc2csv_document
//
//  Created for IGC file parsing - reusable module
//

import Foundation

/// Represents the metadata extracted from an IGC file header (H-records)
public struct IGCFlightInfo: Sendable {
    public let pilot: String?
    public let gliderType: String?
    public let gliderID: String?
    public let flightDate: Date?
    public let firstFixTime: Date?  // First B-record timestamp (UTC)
    public let competitionID: String?
    public let competitionClass: String?
    public let bRecordCount: Int
    public let kRecordCount: Int
    public let hasExtensions: Bool  // True if I-record defines B-record extensions

    /// Formatted date string for display in local time zone
    /// Uses first B-record timestamp if available, otherwise header date
    public var formattedDate: String {
        let dateToFormat = firstFixTime ?? flightDate
        guard let date = dateToFormat else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

/// Parser for IGC (International Gliding Commission) flight log files
/// Reference: FAI IGC Data File Specification (Appendix A to GNSS FR Approval)
public struct IGCParser: Sendable {

    public init() {}

    /// Parse an IGC file and extract flight information from H-records
    /// - Parameter content: The raw string content of an IGC file
    /// - Returns: IGCFlightInfo containing pilot, glider, and date information
    public func parseFlightInfo(from content: String) -> IGCFlightInfo {
        let lines = content.components(separatedBy: .newlines)

        var pilot: String?
        var gliderType: String?
        var gliderID: String?
        var flightDate: Date?
        var firstFixTime: Date?
        var competitionID: String?
        var competitionClass: String?
        var bRecordCount = 0
        var kRecordCount = 0
        var hasExtensions = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Count B-records and get first fix time
            if trimmed.hasPrefix("B") && trimmed.count >= 7 {
                bRecordCount += 1
                if firstFixTime == nil, let date = flightDate {
                    firstFixTime = parseFirstBRecordTime(trimmed, baseDate: date)
                }
                continue
            }

            // Count K-records
            if trimmed.hasPrefix("K") && trimmed.count >= 7 {
                kRecordCount += 1
                continue
            }

            // Check for I-record (B-record extensions)
            if trimmed.hasPrefix("I") && trimmed.count >= 3 {
                hasExtensions = true
                continue
            }

            guard trimmed.hasPrefix("H") else {
                continue
            }

            // H-record format: H + Source (F/O/P) + TLC (3-letter code) + : + data
            // or HFDTE format for date

            if let date = parseDateRecord(trimmed) {
                flightDate = date
            } else if let value = parseHRecord(trimmed, code: "PLT") {
                pilot = value
            } else if let value = parseHRecord(trimmed, code: "GTY") {
                gliderType = value
            } else if let value = parseHRecord(trimmed, code: "GID") {
                gliderID = value
            } else if let value = parseHRecord(trimmed, code: "CID") {
                competitionID = value
            } else if let value = parseHRecord(trimmed, code: "CCL") {
                competitionClass = value
            }
        }

        return IGCFlightInfo(
            pilot: pilot,
            gliderType: gliderType,
            gliderID: gliderID,
            flightDate: flightDate,
            firstFixTime: firstFixTime,
            competitionID: competitionID,
            competitionClass: competitionClass,
            bRecordCount: bRecordCount,
            kRecordCount: kRecordCount,
            hasExtensions: hasExtensions
        )
    }

    /// Parse date from HFDTE record
    /// Format: HFDTEDDMMYY or HFDTE:DDMMYY or HFDTEDATE:DDMMYY,NN
    private func parseDateRecord(_ line: String) -> Date? {
        // Look for DTE pattern
        guard line.uppercased().contains("DTE") else { return nil }

        // Extract 6-digit date (DDMMYY)
        let pattern = #"(\d{2})(\d{2})(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        guard let dayRange = Range(match.range(at: 1), in: line),
              let monthRange = Range(match.range(at: 2), in: line),
              let yearRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        let day = Int(line[dayRange]) ?? 0
        let month = Int(line[monthRange]) ?? 0
        var year = Int(line[yearRange]) ?? 0

        // Convert 2-digit year to 4-digit (assume 2000s for years < 80, 1900s otherwise)
        year = year < 80 ? 2000 + year : 1900 + year

        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        components.timeZone = TimeZone(identifier: "UTC")

        return Calendar(identifier: .gregorian).date(from: components)
    }

    /// Parse time from first B-record to get actual flight start time
    /// B-record format: B HHMMSS ... (time at positions 1-6)
    private func parseFirstBRecordTime(_ line: String, baseDate: Date) -> Date? {
        guard line.count >= 7 else { return nil }

        let index1 = line.index(line.startIndex, offsetBy: 1)
        let index3 = line.index(line.startIndex, offsetBy: 3)
        let index5 = line.index(line.startIndex, offsetBy: 5)
        let index7 = line.index(line.startIndex, offsetBy: 7)

        guard let hour = Int(line[index1..<index3]),
              let minute = Int(line[index3..<index5]),
              let second = Int(line[index5..<index7]) else {
            return nil
        }

        var components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: baseDate
        )
        components.hour = hour
        components.minute = minute
        components.second = second

        return Calendar(identifier: .gregorian).date(from: components)
    }

    /// Parse an H-record with a specific 3-letter code
    /// Format: H + Source + TLC + LongName: Value or H + Source + TLC: Value
    private func parseHRecord(_ line: String, code: String) -> String? {
        let upper = line.uppercased()

        // Check if line contains the code
        guard upper.contains(code) else { return nil }

        // Find the value after the colon
        if let colonIndex = line.firstIndex(of: ":") {
            let valueStart = line.index(after: colonIndex)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }

        return nil
    }
}
