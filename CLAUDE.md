# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build the project from command line
xcodebuild -project igc2csv_document/igc2csv_document.xcodeproj -scheme igc2csv_document -configuration Debug build

# Build for release
xcodebuild -project igc2csv_document/igc2csv_document.xcodeproj -scheme igc2csv_document -configuration Release build

# Run tests (when added)
xcodebuild -project igc2csv_document/igc2csv_document.xcodeproj -scheme igc2csv_document test
```

Alternatively, open `igc2csv_document/igc2csv_document.xcodeproj` in Xcode and use Cmd+B to build or Cmd+R to run.

## Architecture

This is a SwiftUI app for converting IGC (glider flight recorder) files to CSV format for post-flight analysis.

### Key Files

- **igc2csv_documentApp.swift** - App entry point using `WindowGroup`
- **ContentView.swift** - Main UI with state machine (welcome → fileSelected → converting → completed)
- **IGCParser/IGCParser.swift** - H-record parsing for flight metadata (pilot, glider, date)
- **IGCParser/IGCConverter.swift** - Full conversion: I/J/B/K record parsing and CSV export
- **Info.plist** - Declares UTType `org.fai.igc` for `.igc` file handling

### IGC File Format

The IGC format is defined by the FAI International Gliding Commission. Key record types:
- **H-records** - Header metadata (pilot, glider, date, etc.)
- **I-records** - Define B-record extensions (additional fields)
- **J-records** - Define K-record extensions
- **B-records** - Position fixes (time, lat/lon in DDMMmmm format, pressure/GPS altitude)
- **K-records** - Supplementary sensor data

Reference: FAI IGC Data File Specification (Appendix A to GNSS FR Approval) - see IGC_Data_File_Specification_2024.pdf in the project

### Module Separation

The `IGCParser` module is intentionally separate from UI code to allow reuse in other projects:
- `IGCFlightInfo` - Parsed header data for display
- `IGCParser` - H-record parsing
- `IGCConverter` - Full I/J/B/K parsing and CSV export
- `IGCBRecord`, `IGCKRecord` - Parsed data records
- `IGCExtension` - Extension field definitions from I/J records

### CSV Output Format

B-records CSV: `date,Latitude,Longitude,GPS Altitude,Pressure Altitude,[extensions...]`
K-records CSV: `date,[extensions...]`

Timestamps are ISO 8601 UTC format. Latitude/longitude are decimal degrees (6 decimal places).

### Platform Support

Multi-platform app targeting:
- macOS 26.1+
- iOS 26.1+
- visionOS 26.1+

### Swift Concurrency

Project uses Swift 6 concurrency model:
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- Parser/converter structs marked `Sendable` for thread safety
- Conversion runs on background Task
