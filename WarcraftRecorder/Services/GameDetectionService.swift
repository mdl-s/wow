import SwiftUI
import Foundation
import AppKit
import Combine

class GameDetectionService: ObservableObject {
    // États observables pour l'interface utilisateur
    @Published var isMonitoring = false
    @Published var currentGameType: GameType?
    @Published var currentMapName: String?
    @Published var detectionStatus = "Idle"
    @Published var lastLogCheck: Date?
    @Published var logFolderExists = false
    @Published var wowIsRunning = false
    @Published var logFilesFound: Bool = false
    @Published var currentLogFile: String?
    @Published var lastLogAnalysisResult: String = "Aucune analyse récente"
    @Published var autoStartMonitoring: Bool = UserDefaults.standard.bool(forKey: "autoStartMonitoring") {
        didSet {
            UserDefaults.standard.set(autoStartMonitoring, forKey: "autoStartMonitoring")
            print("Auto-start monitoring set to: \(autoStartMonitoring)")
        }
    }

    // Dépendances et configuration
    private var arenaDetector = ArenaDetector()
    private var directoryObserver: DirectoryObserver?
    private var logMonitorTimer: Timer?
    private var lastProcessedLog: String?
    var logFolderPath: String = ""
    var monitorInterval: TimeInterval = 1.0
    private var recordingService: RecordingService?

    private var cancellables = Set<AnyCancellable>()
    private var isGameDetectionInProgress = false

    // INIT
    init() {
        arenaDetector.onArenaStart = { [weak self] arenaType, mapName in
            guard let self = self else { return }
            print("ARENA START EVENT: \(arenaType) - \(mapName)")
            self.onGameDetected(type: arenaType, mapName: mapName)
        }
        arenaDetector.onArenaEnd = { [weak self] in
            guard let self = self else { return }
            print("ARENA END EVENT")
            self.onGameEnded()
        }
        checkWoWRunning()
        if logFolderPath.isEmpty { findWoWLogFolder() }
    }

    func setRecordingService(_ service: RecordingService) {
        recordingService = service
    }

    // MARK: - Monitoring Control

    func startMonitoring() {
        guard !isMonitoring else { print("Already monitoring"); return }
        print("Starting monitoring. Log folder path: \(logFolderPath)")
        isMonitoring = true
        updateStatus("Starting monitoring...")
        checkWoWRunning()
        if logFolderPath.isEmpty { findWoWLogFolder() }
        if FileManager.default.fileExists(atPath: logFolderPath) {
            logFolderExists = true
            setupLogMonitoring()
        } else {
            logFolderExists = false
            updateStatus("Log folder not found: \(logFolderPath)")
            if wowIsRunning {
                updateStatus("WoW is running but log folder not found. Enable combat logging in WoW.")
            }
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        print("Stopping monitoring")
        isMonitoring = false
        updateStatus("Monitoring stopped")
        logMonitorTimer?.invalidate()
        logMonitorTimer = nil
        directoryObserver?.stopObserving()
        directoryObserver = nil
        if currentGameType != nil { onGameEnded() }
    }

    private func updateStatus(_ status: String) {
        DispatchQueue.main.async { self.detectionStatus = status }
    }

    // MARK: - Log Monitoring
    private func setupLogMonitoring() {
        directoryObserver = DirectoryObserver(url: URL(fileURLWithPath: logFolderPath))
        directoryObserver?.startObserving { [weak self] newFile in
            guard let self = self else { return }
            if newFile.pathExtension.lowercased() == "txt" && newFile.lastPathComponent.contains("WoWCombatLog") {
                print("New log file detected: \(newFile.path)")
                self.processNewLogFile(newFile.path)
            }
        }
        logMonitorTimer?.invalidate()
        logMonitorTimer = Timer.scheduledTimer(withTimeInterval: monitorInterval, repeats: true) { [weak self] _ in
            guard let self, self.isMonitoring else { return }
            DispatchQueue.main.async { self.lastLogCheck = Date() }
            let isRunning = self.isWoWRunning()
            if self.wowIsRunning != isRunning {
                self.wowIsRunning = isRunning
                if !isRunning {
                    self.updateStatus("WoW has been closed")
                    if self.currentGameType != nil { self.onGameEnded() }
                } else {
                    self.updateStatus("WoW is now running - Monitoring")
                }
            }
            if let logFile = self.lastProcessedLog { self.checkLogFileForChanges(logFile) }
            else { self.checkForExistingLogFiles() }
        }
        updateStatus("Monitoring log folder")
    }

    private func processNewLogFile(_ filePath: String) {
        arenaDetector.reset()
        lastProcessedLog = filePath
        print("Now monitoring log file: \(filePath)")
        DispatchQueue.main.async { self.currentLogFile = URL(fileURLWithPath: filePath).lastPathComponent }
        readAndProcessLogFileChanges(filePath)
    }

    private func checkLogFileForChanges(_ filePath: String) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: filePath) else {
            lastProcessedLog = nil
            checkForExistingLogFiles()
            return
        }
        guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
              let modificationDate = attributes[.modificationDate] as? Date else { return }
        if let lastCheck = lastLogCheck, modificationDate > lastCheck {
            print("Log file has been modified since last check")
            readAndProcessLogFileChanges(filePath)
        }
    }

    private func readAndProcessLogFileChanges(_ filePath: String) {
        do {
            let contents = try String(contentsOfFile: filePath, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines)
            let recentLines = lines.suffix(200)
            for line in recentLines where line.contains("ARENA") { print("ARENA DEBUG: \(line)") }
            for line in recentLines where !line.isEmpty { parseLine(line) }
            print("=========== END OF LOG PROCESSING ===========")
        } catch { print("Error reading log file changes: \(error)") }
    }

    // MARK: - Log/Folder management
    func findWoWLogFolder() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        let paths = [
            "\(homeDir)/Games/World of Warcraft/_retail_/Logs",
            "\(homeDir)/Games/World of Warcraft/_classic_/Logs",
            "\(homeDir)/Applications/World of Warcraft/_retail_/Logs",
            "\(homeDir)/Applications/World of Warcraft/_classic_/Logs",
            "\(homeDir)/Documents/World of Warcraft/Logs",
            "\(homeDir)/Documents/World of Warcraft/_retail_/Logs",
            "\(homeDir)/Documents/World of Warcraft/_classic_/Logs",
            "/Applications/World of Warcraft/_retail_/Logs",
            "/Applications/World of Warcraft/_classic_/Logs"
        ]
        for path in paths {
            if fileManager.fileExists(atPath: path) {
                logFolderPath = path
                logFolderExists = true
                checkForExistingLogFiles()
                updateStatus("Found log folder: \(path)")
                return
            }
        }
        logFolderExists = false
        updateStatus("Could not find WoW log folder automatically")
        print("No log folder found in any standard locations")
    }

    func checkForExistingLogFiles() {
        do {
            let fileManager = FileManager.default
            let fileNames = try fileManager.contentsOfDirectory(atPath: logFolderPath)
            let filtered = fileNames.filter { $0.hasSuffix(".txt") && $0.contains("WoWCombatLog") }
            
            struct LogFileInfo {
                let name: String
                let date: Date
            }
            let logFileInfos: [LogFileInfo] = filtered.compactMap { fileName in
                let path = "\(logFolderPath)/\(fileName)"
                let attrs = try? fileManager.attributesOfItem(atPath: path)
                let date = attrs?[.modificationDate] as? Date ?? .distantPast
                return LogFileInfo(name: fileName, date: date)
            }
            let sortedInfos = logFileInfos.sorted { $0.date > $1.date }
            let logFiles = sortedInfos.map { $0.name }
            
            if let mostRecentLog = logFiles.first {
                lastProcessedLog = "\(logFolderPath)/\(mostRecentLog)"
                DispatchQueue.main.async {
                    self.logFilesFound = true
                    self.currentLogFile = mostRecentLog
                }
                updateStatus("Found log file: \(mostRecentLog)")
            } else {
                DispatchQueue.main.async {
                    self.logFilesFound = false
                    self.currentLogFile = nil
                }
                updateStatus("No log files found yet. Please generate logs in WoW.")
            }
        } catch {
            DispatchQueue.main.async {
                self.logFilesFound = false
                self.currentLogFile = nil
            }
            updateStatus("Error checking log files: \(error.localizedDescription)")
        }
    }

    // MARK: - Process/Detection

    func checkWoWRunning() {
        let isRunning = isWoWRunning()
        DispatchQueue.main.async {
            self.wowIsRunning = isRunning
            self.updateStatus(isRunning
                ? (self.isMonitoring ? "WoW is running - Monitoring" : "WoW is running - Not monitoring")
                : "WoW is not running")
        }
    }
    private func isWoWRunning() -> Bool {
        for app in NSWorkspace.shared.runningApplications {
            let name = app.localizedName?.lowercased() ?? ""
            if name.contains("world of warcraft") || name == "wow" {
                DispatchQueue.main.async { self.wowIsRunning = true }
                return true
            }
        }
        DispatchQueue.main.async { self.wowIsRunning = false }
        return false
    }

    // MARK: - Event Routing

    private func parseLine(_ line: String) {
        arenaDetector.processLine(line)
        if line.contains("ARENA_MATCH_START") { handleArenaMatchStart(LogLine(line)) }
        else if line.contains("ARENA_MATCH_END") { handleArenaMatchEnd(LogLine(line)) }
        else if line.contains("SPELL_AURA_APPLIED") && line.contains("ARENA_PREPARATION") { handleArenaPreparation(LogLine(line)) }
        else if line.contains("ARENA_SKIRMISH") { handleSkirmishEvent(line) }
    }

    private func handleArenaMatchStart(_ logLine: LogLine) {
        let typeStr = logLine.arg(3) ?? ""
        let arenaType: GameType
        if typeStr.contains("2v2") { arenaType = .arena2v2 }
        else if typeStr.contains("3v3") { arenaType = .arena3v3 }
        else { arenaType = .arena2v2 }
        let mapID = logLine.arg(1) ?? "0"
        let arenaName = getArenaNameFromMapID(mapID)
        print("DETECTED: Arena match start - Type \(arenaType.rawValue), Map \(arenaName)")
        onGameDetected(type: arenaType, mapName: arenaName)
    }
    private func handleArenaMatchEnd(_ logLine: LogLine) {
        print("DETECTED: Arena match ended")
        onGameEnded()
    }
    private func handleArenaPreparation(_ logLine: LogLine) {
        let arenaName = determineArenaMap(from: logLine.original)
        print("DETECTED: Arena preparation - Map \(arenaName)")
        onGameDetected(type: .arena2v2, mapName: arenaName)
    }
    private func handleSkirmishEvent(_ line: String) {
        if line.contains("ARENA_SKIRMISH_START") || line.lowercased().contains("skirmish started") {
            let mapName = determineArenaMap(from: line)
            print("Detected skirmish on map: \(mapName)")
            onGameDetected(type: .skirmish, mapName: mapName)
        } else if line.contains("ARENA_SKIRMISH_END") || line.lowercased().contains("skirmish ended") {
            print("Skirmish ended")
            onGameEnded()
        }
    }

    // ** Ce qui change vraiment (plus fiable): **
    private func onGameDetected(type: GameType, mapName: String) {
        guard !isGameDetectionInProgress else { print("Already detecting."); return }
        isGameDetectionInProgress = true
        DispatchQueue.main.async {
            self.currentGameType = type
            self.currentMapName = mapName
            if let started = self.recordingService?.startRecording(gameType: type, mapName: mapName) {
                print("✅ Recording started for \(type.rawValue) / \(mapName) (\(started))")
            } else {
                print("❌ Failed to start recording for \(type.rawValue) - \(mapName)")
            }
            self.isGameDetectionInProgress = false
        }
    }
    private func onGameEnded() {
        DispatchQueue.main.async {
            let prevType = self.currentGameType
            let prevMap = self.currentMapName
            self.currentGameType = nil
            self.currentMapName = nil
            if let recording = self.recordingService?.stopRecording(), prevType != nil && prevMap != nil {
                print("Recording stopped and saved for \(prevType!.rawValue) - \(prevMap!)")
            } else {
                print("No recording to stop or recording failed to save")
            }
        }
    }

    // --- Utilities
    private func getArenaNameFromMapID(_ mapID: String) -> String {
        let arenaMap = [
            "559": "Nagrand Arena", "562": "Blade's Edge Arena", "572": "Ruins of Lordaeron",
            "617": "Dalaran Sewers", "980": "Tol'viron Arena", "1134": "Tiger's Peak",
            "1552": "Black Rook Hold Arena", "1504": "Hook Point", "2167": "Maldraxxus Arena", "2620": "Empyrean Domain"
        ]
        return arenaMap[mapID] ?? "Unknown Arena"
    }
    private func determineArenaMap(from line: String) -> String {
        let arenaNames = [
            "Nagrand": "Nagrand Arena", "Blade's Edge": "Blade's Edge Arena", "Blades Edge": "Blade's Edge Arena",
            "Ruins of Lordaeron": "Ruins of Lordaeron", "Dalaran": "Dalaran Sewers", "Tol'viron": "Tol'viron Arena",
            "Tolviron": "Tol'viron Arena", "Tiger's Peak": "The Tiger's Peak", "Tigers Peak": "The Tiger's Peak",
            "Black Rook": "Black Rook Hold Arena", "Hook Point": "Hook Point", "Maldraxxus": "Maldraxxus Arena",
            "Empyrean Domain": "The Empyrean Domain", "Enigma Crucible": "Enigma Crucible"
        ]
        for (keyword, arenaName) in arenaNames where line.contains(keyword) { return arenaName }
        return "Unknown Arena"
    }

    // Simulate for debug
    func simulateSkirmishDetection() {
        print("Simulating skirmish detection")
        onGameDetected(type: .skirmish, mapName: "Nagrand Arena (Simulated)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.onGameEnded() }
    }
}

// --- DirectoryObserver (inchangé) ---
class DirectoryObserver {
    private let url: URL
    private var source: DispatchSourceFileSystemObject?
    init(url: URL) { self.url = url }
    func startObserving(handler: @escaping (URL) -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        if descriptor < 0 {
            print("Failed to open directory for observation: \(url.path)")
            return
        }
        let queue = DispatchQueue(label: "DirectoryObserver", attributes: .concurrent)
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: queue)
        source?.setEventHandler { [weak self] in
            guard let self = self else { return }
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: self.url, includingPropertiesForKeys: [.contentModificationDateKey])
                
                // On découpe ici : on crée une petite struct pour le tri
                struct FileWithDate {
                    let url: URL
                    let date: Date
                }
                let filesWithDates: [FileWithDate] = contents.compactMap { fileURL in
                    let date = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return FileWithDate(url: fileURL, date: date)
                }
                let sortedFiles = filesWithDates.sorted { $0.date > $1.date }
                
                if let mostRecent = sortedFiles.first,
                   Date().timeIntervalSince(mostRecent.date) < 10 {
                    handler(mostRecent.url)
                }
            } catch {
                print("Error observing directory changes: \(error)")
            }
        }
        source?.setCancelHandler { close(descriptor) }
        source?.resume()
        print("Started observing directory: \(url.path)")
    }
    func stopObserving() {
        source?.cancel()
        source = nil
        print("Stopped observing directory")
    }
}
