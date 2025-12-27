//
//  IGCConverter.swift
//  igc2csv_document
//
//  IGC to CSV conversion - reusable module
//

import Foundation

/// Extension definition from I-record (B-record extensions) or J-record (K-record extensions)
public struct IGCExtension: Sendable {
    public let code: String
    public let startIndex: Int  // 0-based inclusive
    public let endIndex: Int    // 0-based inclusive
}

/// A parsed B-record (position fix)
public struct IGCBRecord: Sendable {
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let pressureAltitude: Int?
    public let gpsAltitude: Int?
    public let extensions: [String: String]
}

/// A parsed K-record (supplementary data)
public struct IGCKRecord: Sendable {
    public let timestamp: Date
    public let extensions: [String: String]
}

/// Result of IGC to CSV conversion
public struct IGCConversionResult: Sendable {
    public let bRecordCount: Int
    public let kRecordCount: Int
    public let bRecordCSVPath: URL?
    public let kRecordCSVPath: URL?
}

/// Converter for IGC files to CSV format
public struct IGCConverter: Sendable {

    public init() {}

    /// Parse I-record to get B-record extension definitions
    /// Format: I NN SSFFCCC SSFFCCC ...
    /// NN = number of extensions, SS = start (1-based), FF = finish (1-based), CCC = 3-letter code
    public func parseIRecord(_ line: String) -> [IGCExtension] {
        guard line.hasPrefix("I"), line.count >= 3 else { return [] }

        guard let numExtensions = Int(line.substring(from: 1, length: 2)) else { return [] }

        var extensions: [IGCExtension] = []
        for i in 0..<numExtensions {
            let base = 3 + i * 7
            guard line.count >= base + 7 else { break }

            guard let start1 = Int(line.substring(from: base, length: 2)),
                  let end1 = Int(line.substring(from: base + 2, length: 2)) else { continue }

            let code = line.substring(from: base + 4, length: 3)

            // Convert to 0-based inclusive indices
            extensions.append(IGCExtension(code: code, startIndex: start1 - 1, endIndex: end1 - 1))
        }
        return extensions
    }

    /// Parse J-record to get K-record extension definitions (same format as I-record)
    public func parseJRecord(_ line: String) -> [IGCExtension] {
        guard line.hasPrefix("J"), line.count >= 3 else { return [] }

        guard let numExtensions = Int(line.substring(from: 1, length: 2)) else { return [] }

        var extensions: [IGCExtension] = []
        for i in 0..<numExtensions {
            let base = 3 + i * 7
            guard line.count >= base + 7 else { break }

            guard let start1 = Int(line.substring(from: base, length: 2)),
                  let end1 = Int(line.substring(from: base + 2, length: 2)) else { continue }

            let code = line.substring(from: base + 4, length: 3)
            extensions.append(IGCExtension(code: code, startIndex: start1 - 1, endIndex: end1 - 1))
        }
        return extensions
    }

    /// Convert IGC file content to CSV files
    /// - Parameters:
    ///   - content: Raw IGC file content
    ///   - outputDirectory: Directory to write CSV files
    ///   - baseFileName: Base name for output files (without extension)
    /// - Returns: Conversion result with record counts and file paths
    public func convert(content: String, outputDirectory: URL, baseFileName: String) throws -> IGCConversionResult {
        let lines = content.components(separatedBy: .newlines)

        // First pass: parse header records (I, J, HFDTE)
        var bExtensions: [IGCExtension] = []
        var kExtensions: [IGCExtension] = []
        var flightDate: Date?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("I") {
                bExtensions = parseIRecord(trimmed)
            } else if trimmed.hasPrefix("J") {
                kExtensions = parseJRecord(trimmed)
            } else if trimmed.uppercased().contains("HFDTE") || trimmed.uppercased().contains("HFDTEDATE") {
                if let date = parseDateRecord(trimmed) {
                    flightDate = date
                }
            }
        }

        guard let baseDate = flightDate else {
            throw IGCConverterError.noDateFound
        }

        // Second pass: parse B and K records
        var bRecords: [IGCBRecord] = []
        var kRecords: [IGCKRecord] = []
        var currentDate = baseDate
        var lastTimestamp: Date?

        let calendar = Calendar(identifier: .gregorian)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("B") {
                guard trimmed.count >= 35 else { continue }

                if let bRecord = parseBRecord(trimmed, baseDate: currentDate, extensions: bExtensions) {
                    // Handle midnight rollover
                    if let last = lastTimestamp, bRecord.timestamp < last {
                        currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
                        // Re-parse with new date
                        if let correctedRecord = parseBRecord(trimmed, baseDate: currentDate, extensions: bExtensions) {
                            bRecords.append(correctedRecord)
                            lastTimestamp = correctedRecord.timestamp
                        }
                    } else {
                        bRecords.append(bRecord)
                        lastTimestamp = bRecord.timestamp
                    }
                }
            } else if trimmed.hasPrefix("K") && !kExtensions.isEmpty {
                guard trimmed.count >= 7 else { continue }

                if let kRecord = parseKRecord(trimmed, baseDate: currentDate, extensions: kExtensions) {
                    // Handle midnight rollover
                    if let last = lastTimestamp, kRecord.timestamp < last {
                        currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
                        if let correctedRecord = parseKRecord(trimmed, baseDate: currentDate, extensions: kExtensions) {
                            kRecords.append(correctedRecord)
                            lastTimestamp = correctedRecord.timestamp
                        }
                    } else {
                        kRecords.append(kRecord)
                        lastTimestamp = kRecord.timestamp
                    }
                }
            }
        }

        // Write CSV files
        let bCSVPath = outputDirectory.appendingPathComponent("\(baseFileName).csv")
        try writeBRecordsCSV(bRecords, extensions: bExtensions, to: bCSVPath)

        var kCSVPath: URL? = nil
        if !kRecords.isEmpty {
            kCSVPath = outputDirectory.appendingPathComponent("\(baseFileName)_k.csv")
            try writeKRecordsCSV(kRecords, extensions: kExtensions, to: kCSVPath!)
        }

        return IGCConversionResult(
            bRecordCount: bRecords.count,
            kRecordCount: kRecords.count,
            bRecordCSVPath: bCSVPath,
            kRecordCSVPath: kCSVPath
        )
    }

    // MARK: - Private Parsing Methods

    private func parseDateRecord(_ line: String) -> Date? {
        guard line.uppercased().contains("DTE") else { return nil }

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
        year = year < 80 ? 2000 + year : 1900 + year

        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")

        return Calendar(identifier: .gregorian).date(from: components)
    }

    private func parseBRecord(_ line: String, baseDate: Date, extensions: [IGCExtension]) -> IGCBRecord? {
        guard line.count >= 35 else { return nil }

        // Time: positions 1-6 (HHMMSS)
        guard let hour = Int(line.substring(from: 1, length: 2)),
              let minute = Int(line.substring(from: 3, length: 2)),
              let second = Int(line.substring(from: 5, length: 2)) else { return nil }

        // Latitude: positions 7-14 (DDMMmmmN/S)
        let latStr = line.substring(from: 7, length: 7)
        let latDir = line.substring(from: 14, length: 1)

        // Longitude: positions 15-23 (DDDMMmmmE/W)
        let lonStr = line.substring(from: 15, length: 8)
        let lonDir = line.substring(from: 23, length: 1)

        // Validity: position 24 (A = 3D fix, V = 2D or invalid)
        // let validity = line.substring(from: 24, length: 1)

        // Pressure altitude: positions 25-29
        let pressAltStr = line.substring(from: 25, length: 5)

        // GPS altitude: positions 30-34
        let gpsAltStr = line.substring(from: 30, length: 5)

        guard let latitude = parseLatitude(latStr, direction: latDir),
              let longitude = parseLongitude(lonStr, direction: lonDir) else { return nil }

        let pressureAltitude = cleanExtensionValue(pressAltStr) as? Int
        let gpsAltitude = cleanExtensionValue(gpsAltStr) as? Int

        // Build timestamp
        var components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: baseDate)
        components.hour = hour
        components.minute = minute
        components.second = second

        guard let timestamp = Calendar(identifier: .gregorian).date(from: components) else { return nil }

        // Parse extensions
        var extValues: [String: String] = [:]
        for ext in extensions {
            if ext.endIndex < line.count {
                let value = line.substring(from: ext.startIndex, length: ext.endIndex - ext.startIndex + 1)
                if let cleaned = cleanExtensionValue(value) {
                    extValues[ext.code] = formatValue(cleaned)
                }
            }
        }

        return IGCBRecord(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            pressureAltitude: pressureAltitude,
            gpsAltitude: gpsAltitude,
            extensions: extValues
        )
    }

    private func parseKRecord(_ line: String, baseDate: Date, extensions: [IGCExtension]) -> IGCKRecord? {
        guard line.count >= 7 else { return nil }

        // Time: positions 1-6 (HHMMSS)
        guard let hour = Int(line.substring(from: 1, length: 2)),
              let minute = Int(line.substring(from: 3, length: 2)),
              let second = Int(line.substring(from: 5, length: 2)) else { return nil }

        // Build timestamp
        var components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: baseDate)
        components.hour = hour
        components.minute = minute
        components.second = second

        guard let timestamp = Calendar(identifier: .gregorian).date(from: components) else { return nil }

        // Parse extensions
        var extValues: [String: String] = [:]
        for ext in extensions {
            if ext.endIndex < line.count {
                let value = line.substring(from: ext.startIndex, length: ext.endIndex - ext.startIndex + 1)
                if let cleaned = cleanExtensionValue(value) {
                    extValues[ext.code] = formatValue(cleaned)
                }
            }
        }

        return IGCKRecord(timestamp: timestamp, extensions: extValues)
    }

    private func parseLatitude(_ str: String, direction: String) -> Double? {
        guard str.count == 7 else { return nil }
        guard let degrees = Int(str.prefix(2)),
              let minutes = Int(str.dropFirst(2).prefix(2)),
              let thousandths = Int(str.dropFirst(4)) else { return nil }

        var lat = Double(degrees) + (Double(minutes) + Double(thousandths) / 1000.0) / 60.0
        if direction == "S" { lat = -lat }
        return lat
    }

    private func parseLongitude(_ str: String, direction: String) -> Double? {
        guard str.count == 8 else { return nil }
        guard let degrees = Int(str.prefix(3)),
              let minutes = Int(str.dropFirst(3).prefix(2)),
              let thousandths = Int(str.dropFirst(5)) else { return nil }

        var lon = Double(degrees) + (Double(minutes) + Double(thousandths) / 1000.0) / 60.0
        if direction == "W" { lon = -lon }
        return lon
    }

    /// Clean extension value: handle dashes, convert to number if possible
    private func cleanExtensionValue(_ value: String) -> Any? {
        var v = value.trimmingCharacters(in: .whitespaces)
        if v.isEmpty || v.allSatisfy({ $0 == "-" }) {
            return nil
        }
        // Remove trailing dashes
        while v.hasSuffix("-") && !v.allSatisfy({ $0 == "-" }) {
            v.removeLast()
        }
        if let intVal = Int(v) {
            return intVal
        }
        if let doubleVal = Double(v) {
            return doubleVal
        }
        return v
    }

    private func formatValue(_ value: Any) -> String {
        if let intVal = value as? Int {
            return String(intVal)
        } else if let doubleVal = value as? Double {
            return String(doubleVal)
        } else if let strVal = value as? String {
            return strVal
        }
        return ""
    }

    // MARK: - CSV Writing

    private func writeBRecordsCSV(_ records: [IGCBRecord], extensions: [IGCExtension], to url: URL) throws {
        var csv = "date,Latitude,Longitude,GPS Altitude,Pressure Altitude"
        for ext in extensions {
            csv += ",\(ext.code)"
        }
        csv += "\n"

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        for record in records {
            let dateStr = dateFormatter.string(from: record.timestamp)
            let lat = String(format: "%.6f", record.latitude)
            let lon = String(format: "%.6f", record.longitude)
            let gpsAlt = record.gpsAltitude.map { String($0) } ?? ""
            let presAlt = record.pressureAltitude.map { String($0) } ?? ""

            csv += "\(dateStr),\(lat),\(lon),\(gpsAlt),\(presAlt)"

            for ext in extensions {
                let val = record.extensions[ext.code] ?? ""
                csv += ",\(val)"
            }
            csv += "\n"
        }

        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeKRecordsCSV(_ records: [IGCKRecord], extensions: [IGCExtension], to url: URL) throws {
        var csv = "date"
        for ext in extensions {
            csv += ",\(ext.code)"
        }
        csv += "\n"

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        for record in records {
            let dateStr = dateFormatter.string(from: record.timestamp)
            csv += dateStr

            for ext in extensions {
                let val = record.extensions[ext.code] ?? ""
                csv += ",\(val)"
            }
            csv += "\n"
        }

        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Errors

public enum IGCConverterError: Error, LocalizedError {
    case noDateFound
    case invalidFormat
    case writeError(String)

    public var errorDescription: String? {
        switch self {
        case .noDateFound:
            return "No HFDTE or HFDTEDATE record found in IGC file"
        case .invalidFormat:
            return "Invalid IGC file format"
        case .writeError(let message):
            return "Failed to write CSV: \(message)"
        }
    }
}

// MARK: - String Extension for Substring

private extension String {
    func substring(from start: Int, length: Int) -> String {
        guard start >= 0, start < count else { return "" }
        let startIndex = index(self.startIndex, offsetBy: start)
        let endOffset = min(start + length, count)
        let endIndex = index(self.startIndex, offsetBy: endOffset)
        return String(self[startIndex..<endIndex])
    }
}
