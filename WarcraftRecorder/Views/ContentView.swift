import SwiftUI

struct ContentView: View {
    @EnvironmentObject var gameDetectionService: GameDetectionService
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var storageService: StorageService
    
    @State private var selectedCategory: GameType?
    @State private var status: String = "Waiting"
    @State private var showSettings: Bool = false
    
    var body: some View {
        NavigationView {
            SidebarView(
                selectedCategory: $selectedCategory,
                status: $status,
                showSettings: $showSettings,
                recordings: storageService.allRecordings
            )
            
            if showSettings {
                GeneralSettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else if let selected = selectedCategory {
                RecordingsList(
                    gameType: selected,
                    recordings: storageService.allRecordings.filter { $0.type == selected }
                )
            } else {
                VStack(spacing: 20) {
                    Text("Welcome to Warcraft Recorder")
                        .font(.largeTitle)
                        .bold()
                    
                    // Status détaillé
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Status: \(status)")
                            .font(.headline)
                            .foregroundColor(status == "Waiting" ? .orange :
                                            (status.contains("Recording") ? .red :
                                            (status.contains("Monitoring") ? .green : .primary)))
                        
                        // Statut détaillé de WoW
                        if gameDetectionService.wowIsRunning {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("World of Warcraft is running")
                                    .foregroundColor(.green)
                            }
                        } else {
                            HStack {
                                Image(systemName: "x.circle")
                                    .foregroundColor(.orange)
                                Text("World of Warcraft is not running")
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        // Statut des logs
                        if !gameDetectionService.logFolderPath.isEmpty {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                Text("Logs folder: \(gameDetectionService.logFolderPath.components(separatedBy: "/").last ?? "")")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            
                            if let currentLog = gameDetectionService.currentLogFile {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(.green)
                                    Text("Current log file: \(currentLog)")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }
                            } else if gameDetectionService.logFilesFound {
                                HStack {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(.green)
                                    Text("Log files found, waiting for WoW events")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }
                            } else {
                                HStack {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .foregroundColor(.red)
                                    Text("No log files found in the selected folder")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            
                            if let lastCheck = gameDetectionService.lastLogCheck {
                                let formatter = RelativeDateTimeFormatter()
                                let relativeTime = formatter.localizedString(for: lastCheck, relativeTo: Date())
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundColor(.secondary)
                                    Text("Last log check: \(relativeTime)")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text(gameDetectionService.lastLogAnalysisResult)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        } else {
                            HStack {
                                Image(systemName: "folder.badge.questionmark")
                                    .foregroundColor(.red)
                                Text("Logs folder not set")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        
                        if recordingService.isRecording {
                            HStack {
                                Image(systemName: "record.circle")
                                    .foregroundColor(.red)
                                Text("Currently recording: \(formatDuration(recordingService.recordingDuration))")
                                    .foregroundColor(.red)
                                    .font(.title2)
                            }
                            .padding(.top, 5)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.windowBackgroundColor)))
                    
                    // Actions principales
                    HStack(spacing: 20) {
                        Button("Open Settings") {
                            showSettings = true
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(gameDetectionService.isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                            toggleMonitoring()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(gameDetectionService.isMonitoring ? .red : .green)
                        
                        Button("Check Monitoring Status") {
                            performDiagnostics()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.blue)
                    }
                    .padding()
                    
                    // Instructions rapides
                    if !gameDetectionService.isMonitoring {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Quick Start Guide:")
                                .font(.headline)
                            
                            Text("1. Set up your logs folder in Settings")
                            Text("2. Enable combat logging in WoW with '/combatlog'")
                            Text("3. Click 'Start Monitoring' to detect games")
                            Text("4. Enter an arena, dungeon, or raid")
                            Text("5. Recording will start automatically")
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.windowBackgroundColor).opacity(0.5)))
                    }
                    
                    // Section test pour débogage
                    #if DEBUG
                    VStack(alignment: .center) {
                        Text("Debug Actions")
                            .font(.headline)
                            .foregroundColor(.orange)
                        
                        HStack(spacing: 10) {
                            Button("Simulate Skirmish") {
                                gameDetectionService.simulateSkirmishDetection()
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.orange)
                        }
                        .padding(.top, 5)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).opacity(0.1))
                    #endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: toggleRecording) {
                    Image(systemName: recordingService.isRecording ? "stop.circle" : "record.circle")
                        .foregroundColor(recordingService.isRecording ? .red : .primary)
                }
                .help(recordingService.isRecording ? "Stop Recording" : "Start Recording")
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: toggleMonitoring) {
                    Image(systemName: gameDetectionService.isMonitoring ? "eye.slash" : "eye")
                        .foregroundColor(gameDetectionService.isMonitoring ? .green : .primary)
                }
                .help(gameDetectionService.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                }
                .help("Settings")
            }
            
            ToolbarItem(placement: .automatic) {
                if recordingService.isRecording {
                    Text(formatDuration(recordingService.recordingDuration))
                        .foregroundColor(.red)
                        .monospacedDigit()
                }
            }
        }
        .onAppear {
            updateStatus()
        }
        .onChange(of: gameDetectionService.isMonitoring) { _, _ in
            updateStatus()
        }
        .onChange(of: recordingService.isRecording) { _, _ in
            updateStatus()
        }
        .onChange(of: gameDetectionService.detectionStatus) { _, _ in
            updateStatus()
        }
    }
    
    private func toggleRecording() {
        if recordingService.isRecording {
            if let recording = recordingService.stopRecording() {
                storageService.saveRecording(recording)
            }
        } else {
            _ = recordingService.startRecording(
                gameType: gameDetectionService.currentGameType ?? .clip,
                mapName: gameDetectionService.currentMapName ?? "Manual Recording"
            )
        }
    }
    
    private func toggleMonitoring() {
        if gameDetectionService.isMonitoring {
            gameDetectionService.stopMonitoring()
        } else {
            gameDetectionService.startMonitoring()
        }
    }
    
    private func updateStatus() {
        if recordingService.isRecording {
            status = "Recording"
        } else if gameDetectionService.isMonitoring {
            if gameDetectionService.wowIsRunning {
                status = "Monitoring: WoW running"
            } else {
                status = "Monitoring: Waiting for WoW"
            }
        } else {
            // Utiliser le status de détection directement
            status = gameDetectionService.detectionStatus
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00:00"
    }
    
    private func performDiagnostics() {
        let quality = UserDefaults.standard.string(forKey: "videoQuality") ?? "Default/Unknown"
        let diagnosticResults = """
        === WarcraftRecorder Diagnostics ===
        
        WoW Status: \(gameDetectionService.wowIsRunning ? "Running" : "Not detected")
        Monitoring: \(gameDetectionService.isMonitoring ? "Active" : "Inactive")
        
        Logs folder: \(gameDetectionService.logFolderPath)
        Folder exists: \(FileManager.default.fileExists(atPath: gameDetectionService.logFolderPath) ? "Yes" : "No")
        
        Current log file: \(gameDetectionService.currentLogFile ?? "None")
        Log files found: \(gameDetectionService.logFilesFound ? "Yes" : "No")
        
        Last status update: \(gameDetectionService.detectionStatus)
        Last log check: \(gameDetectionService.lastLogCheck?.description ?? "Never")
        
        Recording settings:
        Output folder: \(recordingService.recordingsFolder)
        Quality: \(quality)
        
        === End of Diagnostics ===
        """
        
        print(diagnosticResults)
        
        // Afficher les résultats dans une alerte (uniquement macOS)
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Diagnostics Results"
        alert.informativeText = diagnosticResults
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        #endif
        
        // Forcer une vérification des logs
        if gameDetectionService.isMonitoring {
            gameDetectionService.checkForExistingLogFiles()
        }
    }
}
