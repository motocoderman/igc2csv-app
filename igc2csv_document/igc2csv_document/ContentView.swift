//
//  ContentView.swift
//  igc2csv_document
//
//  Created by Alonzo Kelly on 12/8/25.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// UTType for IGC files
extension UTType {
    static let igc = UTType(importedAs: "org.fai.igc")
}

/// App state for navigation
enum AppState {
    case welcome
    case fileSelected
    case converting
    case completed
}

struct ContentView: View {
    @State private var appState: AppState = .welcome
    @State private var isFilePickerPresented = false
    @State private var selectedFileURL: URL?
    @State private var flightInfo: IGCFlightInfo?
    @State private var errorMessage: String?
    @State private var fileContent: String?
    @State private var conversionResult: IGCConversionResult?
    @State private var isDragOver = false
    @State private var showingAbout = false

    private let parser = IGCParser()
    private let converter = IGCConverter()

    var body: some View {
        VStack(spacing: 20) {
            switch appState {
            case .welcome:
                welcomeView
            case .fileSelected:
                if let info = flightInfo {
                    flightInfoView(info)
                }
            case .converting:
                convertingView
            case .completed:
                if let result = conversionResult {
                    completedView(result)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .padding(30)
        .frame(minWidth: 450, minHeight: 350)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isDragOver ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .onDrop(of: [.igc, .plainText, .fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.igc, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingAbout = true
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }
        }
    }

    // MARK: - Drag and Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Try to load as file URL
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        loadFile(at: url)
                    }
                }
            }
            return true
        }
        return false
    }

    // MARK: - Views

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Text("IGC to CSV Converter")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Convert IGC flight logs to CSV format for post-flight analysis")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { isFilePickerPresented = true }) {
                Label("Select IGC File", systemImage: "doc.badge.plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func flightInfoView(_ info: IGCFlightInfo) -> some View {
        VStack(spacing: 20) {
            Text("Flight Information")
                .font(.title)
                .fontWeight(.bold)

            if let url = selectedFileURL {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    Text("Pilot:")
                        .fontWeight(.semibold)
                    Text(info.pilot ?? "Not specified")
                }
                GridRow {
                    Text("Glider:")
                        .fontWeight(.semibold)
                    Text(info.gliderType ?? "Not specified")
                }
                GridRow {
                    Text("Glider ID:")
                        .fontWeight(.semibold)
                    Text(info.gliderID ?? "Not specified")
                }
                GridRow {
                    Text("Date:")
                        .fontWeight(.semibold)
                    Text(info.formattedDate)
                }
                if let compID = info.competitionID {
                    GridRow {
                        Text("Competition ID:")
                            .fontWeight(.semibold)
                        Text(compID)
                    }
                }
                GridRow {
                    Text("Position fixes:")
                        .fontWeight(.semibold)
                    Text("\(info.bRecordCount.formatted()) records\(info.hasExtensions ? " + extensions" : "")")
                }
                if info.kRecordCount > 0 {
                    GridRow {
                        Text("Sensor data:")
                            .fontWeight(.semibold)
                        Text("\(info.kRecordCount.formatted()) records")
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 16) {
                Button("Select Different File") {
                    isFilePickerPresented = true
                }
                .buttonStyle(.bordered)

                Button("Convert to CSV") {
                    performConversion()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var convertingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Converting...")
                .font(.headline)
            if let info = flightInfo {
                Text("Processing \(info.bRecordCount.formatted()) position records")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func completedView(_ result: IGCConversionResult) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)

            Text("Conversion Complete")
                .font(.title)
                .fontWeight(.bold)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    Text("B-Records:")
                        .fontWeight(.semibold)
                    Text("\(result.bRecordCount) records")
                }
                if let bPath = result.bRecordCSVPath {
                    GridRow {
                        Text("B-Record File:")
                            .fontWeight(.semibold)
                        Text(bPath.lastPathComponent)
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("K-Records:")
                        .fontWeight(.semibold)
                    Text(result.kRecordCount > 0 ? "\(result.kRecordCount) records" : "None found")
                }
                if let kPath = result.kRecordCSVPath {
                    GridRow {
                        Text("K-Record File:")
                            .fontWeight(.semibold)
                        Text(kPath.lastPathComponent)
                            .foregroundStyle(.secondary)
                    }
                }
                if let bPath = result.bRecordCSVPath {
                    GridRow {
                        Text("Saved to:")
                            .fontWeight(.semibold)
                        Text(bPath.deletingLastPathComponent().path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 16) {
                Button("Convert Another File") {
                    resetState()
                    isFilePickerPresented = true
                }
                .buttonStyle(.borderedProminent)

                #if os(macOS)
                if let bPath = result.bRecordCSVPath {
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(bPath.path, inFileViewerRootedAtPath: bPath.deletingLastPathComponent().path)
                    }
                    .buttonStyle(.bordered)
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                #else
                // iOS/visionOS share button
                if let bPath = result.bRecordCSVPath {
                    ShareLink(item: bPath) {
                        Label("Share CSV", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                #endif
            }
        }
    }

    // MARK: - Actions

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        errorMessage = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                errorMessage = "No file selected"
                return
            }
            loadFile(at: url)

        case .failure(let error):
            errorMessage = "Failed to select file: \(error.localizedDescription)"
        }
    }

    private func loadFile(at url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)

            // Validate this looks like an IGC file
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = "The selected file is empty"
                return
            }

            // Check for basic IGC structure (should have H-records or A-record)
            let hasIGCContent = trimmed.contains("HFDTE") ||
                               trimmed.contains("HFDTEDATE") ||
                               trimmed.hasPrefix("A")
            guard hasIGCContent else {
                errorMessage = "This doesn't appear to be a valid IGC file"
                return
            }

            selectedFileURL = url
            fileContent = content
            let info = parser.parseFlightInfo(from: content)
            flightInfo = info

            // Validate we got at least a date
            if info.flightDate == nil {
                errorMessage = "Could not find flight date in file. The file may be corrupted."
                return
            }

            // Warn if no B-records found
            if info.bRecordCount == 0 {
                errorMessage = "No position records found. The file may be incomplete."
                return
            }

            appState = .fileSelected
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                errorMessage = "Permission denied to read this file"
            } else {
                errorMessage = "Failed to read file: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
    }

    private func performConversion() {
        guard let content = fileContent,
              let sourceURL = selectedFileURL else {
            errorMessage = "No file content available"
            return
        }

        // Check for empty content
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "The selected file is empty"
            return
        }

        // Output to same directory as input file
        let outputDirectory = sourceURL.deletingLastPathComponent()

        // Get base filename without extension
        let baseFileName = sourceURL.deletingPathExtension().lastPathComponent

        appState = .converting
        errorMessage = nil

        // Perform conversion on background thread
        Task {
            do {
                // Re-acquire security-scoped access for writing
                let hasAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                let result = try converter.convert(
                    content: content,
                    outputDirectory: outputDirectory,
                    baseFileName: baseFileName
                )

                // Check if any records were converted
                if result.bRecordCount == 0 {
                    await MainActor.run {
                        errorMessage = "No position records (B-records) found in file"
                        appState = .fileSelected
                    }
                    return
                }

                await MainActor.run {
                    conversionResult = result
                    appState = .completed
                }
            } catch let error as IGCConverterError {
                await MainActor.run {
                    errorMessage = error.errorDescription ?? "Conversion failed"
                    appState = .fileSelected
                }
            } catch let error as NSError {
                await MainActor.run {
                    if error.domain == NSCocoaErrorDomain {
                        switch error.code {
                        case NSFileWriteNoPermissionError, NSFileWriteUnknownError:
                            errorMessage = "Cannot write to this location. Try selecting a file from a different folder."
                        case NSFileWriteOutOfSpaceError:
                            errorMessage = "Not enough storage space to save the CSV file"
                        default:
                            errorMessage = "Failed to save CSV: \(error.localizedDescription)"
                        }
                    } else {
                        errorMessage = "Conversion failed: \(error.localizedDescription)"
                    }
                    appState = .fileSelected
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Conversion failed: \(error.localizedDescription)"
                    appState = .fileSelected
                }
            }
        }
    }

    private func resetState() {
        appState = .welcome
        selectedFileURL = nil
        flightInfo = nil
        fileContent = nil
        conversionResult = nil
        errorMessage = nil
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("igc2csv")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                Label("Convert IGC flight logs to CSV format", systemImage: "doc.text")
                Label("Extracts position fixes (B-records) and sensor data (K-records)", systemImage: "location")
                Label("Preserves all extension fields from I/J records", systemImage: "list.bullet")
                Label("Conforms to FAI IGC Data File Specification", systemImage: "checkmark.seal")
            }
            .font(.callout)
            .padding()

            Divider()
                .padding(.horizontal, 40)

            Text("Drop an IGC file onto the window or use the file picker to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding(30)
        .frame(minWidth: 400, minHeight: 400)
    }
}

#Preview {
    ContentView()
}

#Preview("About") {
    AboutView()
}
