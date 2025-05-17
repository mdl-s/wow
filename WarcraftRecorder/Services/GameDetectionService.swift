//
//  GameDetectionService.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//
import SwiftUI
import Foundation
import AppKit
import Combine

class GameDetectionService: ObservableObject {
    // États observables
    @Published var isMonitoring = false
    @Published var currentGameType: GameType?
    @Published var currentMapName: String?
    @Published var detectionStatus = "Idle"
    @Published var lastLogCheck: Date?
    @Published var logFolderExists = false
    @Published var wowIsRunning = false
    
    // États observables supplémentaires pour une meilleure interface
    @Published var logFilesFound: Bool = false
    @Published var currentLogFile: String?
    @Published var lastLogAnalysisResult: String = "Aucune analyse récente"
    
    // Option de démarrage automatique
    @Published var autoStartMonitoring: Bool = UserDefaults.standard.bool(forKey: "autoStartMonitoring") {
        didSet {
            UserDefaults.standard.set(autoStartMonitoring, forKey: "autoStartMonitoring")
            print("Auto-start monitoring set to: \(autoStartMonitoring)")
        }
    }
    
    private var arenaDetector = ArenaDetector()
    private var triedArenaAutoDetection = false
    
    // Configuration
    var logFolderPath: String = ""
    var monitorInterval: TimeInterval = 1.0
    private var logMonitorTimer: Timer?
    private var lastProcessedLog: String?
    private var directoryObserver: DirectoryObserver?
    
    // Dépendances
    private var recordingService: RecordingService?
    
    // Cancellables
    private var cancellables = Set<AnyCancellable>()
    
    // Variables pour le suivi des événements d'arène
    private var lastArenaPreparationTime: Date?
    private var potentialArenaInProgress = false
    
    init() {
        // Configuration du détecteur d'arène - approche événementielle
        arenaDetector.onArenaStart = { [weak self] arenaType, mapName in
            guard let self = self else { return }
            print("ARENA START EVENT: \(arenaType) - \(mapName)")
            
            // S'assurer qu'aucun enregistrement n'est en cours déjà
            if self.currentGameType == nil {
                self.gameDetected(type: arenaType, mapName: mapName)
            }
        }
        
        arenaDetector.onArenaEnd = { [weak self] in
            guard let self = self else { return }
            print("ARENA END EVENT")
            
            if self.currentGameType != nil {
                self.gameEnded()
            } else {
                print("No active recording to end!")
            }
        }
        
        // Vérifier au démarrage si WoW est en cours d'exécution
        checkWoWRunning()
        
        // Essayer de trouver le dossier de logs au démarrage
        if logFolderPath.isEmpty {
            findWoWLogFolder()
        }
        
        // Ne pas tester automatiquement en mode release
        #if DEBUG
        // Ne pas tester par défaut
        // testDetectArenaStart()
        #endif
    }
    
    func setRecordingService(_ service: RecordingService) {
        recordingService = service
    }
    
    // Test manuel pour la détection d'arène
    func testDetectArenaStart() {
        print("Manually testing arena start detection")
        // Simuler une ligne de log ARENA_MATCH_START
        let testLine = "5/14/2025 11:30:00.000  ARENA_MATCH_START,559,33,2v2,0"
        
        let logLine = LogLine(testLine)
        if logLine.eventType() == "ARENA_MATCH_START" {
            print("✅ LogLine correctly parsed ARENA_MATCH_START")
            handleArenaEvent(testLine)
        } else {
            print("❌ LogLine failed to parse ARENA_MATCH_START, got: \(logLine.eventType())")
        }
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        guard !isMonitoring else {
            print("Already monitoring")
            return
        }
        
        print("Starting monitoring. Log folder path: \(logFolderPath)")
        isMonitoring = true
        updateStatus("Starting monitoring...")
        
        // Vérifier le statut de WoW
        checkWoWRunning()
        
        // Si aucun chemin de log n'est spécifié, essayer de le trouver
        if logFolderPath.isEmpty {
            print("No log folder path set, attempting to find it")
            findWoWLogFolder()
        }
        
        // Vérifier que le dossier de logs existe
        if FileManager.default.fileExists(atPath: logFolderPath) {
            logFolderExists = true
            print("Log folder exists at: \(logFolderPath)")
            setupLogMonitoring()
        } else {
            logFolderExists = false
            print("Log folder not found at: \(logFolderPath)")
            updateStatus("Log folder not found: \(logFolderPath)")
            
            // Si WoW est en cours d'exécution mais que le dossier de logs n'existe pas
            if wowIsRunning {
                updateStatus("WoW is running but log folder not found. Enable combat logging in WoW.")
            }
        }
        
        // Pour la démo, simuler des détections
        #if DEBUG
        print("Debug mode: Will simulate game detection")
        simulateGameDetection()
        #endif
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("Stopping monitoring")
        isMonitoring = false
        updateStatus("Monitoring stopped")
        
        // Arrêter le timer
        logMonitorTimer?.invalidate()
        logMonitorTimer = nil
        
        // Arrêter l'observateur de dossier
        directoryObserver?.stopObserving()
        directoryObserver = nil
        
        // Si un jeu est en cours, le terminer
        if currentGameType != nil {
            gameEnded()
        }
    }
    
    // MARK: - Status Updates
    
    private func updateStatus(_ status: String) {
        print("GameDetectionService: \(status)")
        DispatchQueue.main.async {
            self.detectionStatus = status
        }
    }
    
    private func checkForOngoingArena(in logFile: String) {
        print("Checking for ongoing arena in log file: \(logFile)")
        
        do {
            let contents = try String(contentsOfFile: logFile, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines)
            
            // Chercher des indications d'une arène en cours
            var hasArenaRelatedLines = false
            var hasRecentCombat = false
            var recentTimestamp: Date?
            var playerNames = Set<String>()
            
            // Parcourir les lignes pour détecter une arène en cours
            for line in lines.suffix(500) {  // Examiner les 500 dernières lignes
                if line.contains("ARENA") {
                    hasArenaRelatedLines = true
                }
                
                // N'examiner que les lignes des 5 dernières minutes
                let logLine = LogLine(line)
                let timestamp = logLine.date()
                
                if Date().timeIntervalSince(timestamp) < 300 { // 5 minutes
                    recentTimestamp = timestamp
                    
                    // Détecter des dégâts ou soins récents
                    if line.contains("SPELL_DAMAGE") || line.contains("SPELL_HEAL") {
                        hasRecentCombat = true
                        
                        // Collecter les noms des joueurs impliqués
                        if line.contains("Player-") {
                            let names = arenaDetector.extractPlayerNames(from: line)
                            playerNames.formUnion(names)
                        }
                    }
                    
                    // Vérifier si un match vient de commencer
                    if line.contains("ARENA_PREPARATION") {
                        print("Found ARENA_PREPARATION in recent logs")
                        let logLine = LogLine(line)
                        handleArenaPreparation(logLine)
                        return
                    }
                }
            }
            
            // Si nous avons des indices d'une arène en cours, démarrer l'enregistrement
            if hasArenaRelatedLines && hasRecentCombat && playerNames.count >= 2 && recentTimestamp != nil {
                print("DETECTED: Likely ongoing arena match with \(playerNames.count) players")
                
                // Démarrer l'enregistrement si nous ne l'avons pas déjà fait
                if self.currentGameType == nil {
                    self.gameDetected(type: .arena2v2, mapName: "Arena (Auto-detected)")
                    
                    // Informer l'utilisateur
                    DispatchQueue.main.async {
                        self.lastLogAnalysisResult = "Detected ongoing arena match with \(playerNames.count) players"
                    }
                }
            }
        } catch {
            print("Error checking for ongoing arena: \(error)")
        }
    }
    
    // Ajoutez cette méthode dans votre classe GameDetectionService

    private func parseLine(_ line: String) {
        guard !line.isEmpty else { return }
        
        // Passer la ligne au détecteur d'arène pour traitement
        arenaDetector.processLine(line)
        
        // Traiter différents types d'événements en fonction de leur contenu
        if line.contains("ARENA_MATCH_START") {
            let logLine = LogLine(line)
            handleArenaMatchStart(logLine)
        }
        else if line.contains("ARENA_MATCH_END") {
            let logLine = LogLine(line)
            handleArenaMatchEnd(logLine)
        }
        else if line.contains("SPELL_AURA_APPLIED") && line.contains("ARENA_PREPARATION") {
            let logLine = LogLine(line)
            handleArenaPreparation(logLine)
        }
        else if line.contains("CHALLENGE_MODE_START") || line.contains("CHALLENGE_MODE_END") {
            handleMythicPlusEvent(line)
        }
        else if line.contains("BATTLEFIELD_MATCH_START") || line.contains("BATTLEFIELD_MATCH_END") {
            handleBattlegroundEvent(line)
        }
        else if line.contains("ENCOUNTER_START") || line.contains("ENCOUNTER_END") {
            handleRaidEvent(line)
        }
        else if line.contains("ARENA_SKIRMISH") {
            handleSkirmishEvent(line)
        }
    }
    
    // MARK: - Game Events
    
    private var isGameDetectionInProgress = false

    private func gameDetected(type: GameType, mapName: String) {
        guard currentGameType == nil && !isGameDetectionInProgress else {
            print("⚠️ Game detection already in progress or recording already active.")
            return
        }

        isGameDetectionInProgress = true

        DispatchQueue.main.async {
            self.currentGameType = type
            self.currentMapName = mapName

            if let path = self.recordingService?.startRecording(gameType: type, mapName: mapName) {
                print("✅ Game detected and recording started: \(type.rawValue) on \(mapName)")
            } else {
                print("❌ Failed to start recording for \(type.rawValue) - \(mapName)")
            }

            self.isGameDetectionInProgress = false
        }
    }

    
    
    private func gameEnded() {
        print("Game ended")
        
        DispatchQueue.main.async {
            self.updateStatus("Game ended - Monitoring")
            
            // Stocker temporairement les valeurs
            let previousType = self.currentGameType
            let previousMap = self.currentMapName
            
            // Réinitialiser les états
            self.currentGameType = nil
            self.currentMapName = nil
            
            // Arrêter l'enregistrement
            if let recording = self.recordingService?.stopRecording(),
               previousType != nil && previousMap != nil {
                print("Recording stopped and saved for \(previousType?.rawValue ?? "unknown") - \(previousMap ?? "unknown")")
            } else {
                print("No recording to stop or recording failed to save")
            }
        }
    }
    
    // MARK: - WoW Process Detection
    
    func checkWoWRunning() {
        let isRunning = isWoWRunning()
        
        DispatchQueue.main.async {
            self.wowIsRunning = isRunning
            if isRunning {
                if self.isMonitoring {
                    self.updateStatus("WoW is running - Monitoring")
                } else {
                    self.updateStatus("WoW is running - Not monitoring")
                }
            } else {
                self.updateStatus("WoW is not running")
            }
        }
    }
    
    private func isWoWRunning() -> Bool {
        let runningApplications = NSWorkspace.shared.runningApplications
        
        for app in runningApplications {
            guard let appName = app.localizedName?.lowercased() else { continue }
            
            if appName.contains("world of warcraft") ||
               appName.contains("wow") ||
               app.bundleIdentifier?.contains("warcraft") == true ||
               app.bundleIdentifier?.contains("wow") == true {
                print("WoW process detected: \(appName)")
                
                // Mettre à jour l'état en temps réel
                DispatchQueue.main.async {
                    self.wowIsRunning = true
                }
                return true
            }
        }
        
        print("WoW process not detected among \(runningApplications.count) running applications")
        
        // Mettre à jour l'état en temps réel
        DispatchQueue.main.async {
            self.wowIsRunning = false
        }
        return false
    }
    
    // MARK: - Log Folder Management
    
    func findWoWLogFolder() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        
        print("Searching for WoW log folder in home directory: \(homeDir)")
        
        // Liste des chemins possibles pour le dossier de logs
        let potentialFolderPaths = [
            // Windows via Parallels/Wine
            "\(homeDir)/Games/World of Warcraft/_retail_/Logs",
            "\(homeDir)/Games/World of Warcraft/_classic_/Logs",
            
            // macOS installations
            "\(homeDir)/Applications/World of Warcraft/_retail_/Logs",
            "\(homeDir)/Applications/World of Warcraft/_classic_/Logs",
            
            // Chemins relatifs au Documents
            "\(homeDir)/Documents/World of Warcraft/Logs",
            "\(homeDir)/Documents/World of Warcraft/_retail_/Logs",
            "\(homeDir)/Documents/World of Warcraft/_classic_/Logs",
            
            // Parallels spécifique
            "\(homeDir)/Parallels/World of Warcraft/_retail_/Logs",
            "\(homeDir)/Parallels/World of Warcraft/_classic_/Logs",
            
            // Applications standard macOS
            "/Applications/World of Warcraft/_retail_/Logs",
            "/Applications/World of Warcraft/_classic_/Logs",
            
            // Autres emplacements potentiels
            "\(homeDir)/Desktop/World of Warcraft/_retail_/Logs",
            "\(homeDir)/Desktop/World of Warcraft/_classic_/Logs"
        ]
        
        for path in potentialFolderPaths {
            print("Checking path: \(path)")
            if fileManager.fileExists(atPath: path) {
                print("Found log folder at: \(path)")
                logFolderPath = path
                logFolderExists = true
                updateStatus("Found log folder: \(path)")
                
                // Vérifier s'il y a des fichiers de log existants dans le dossier
                checkForExistingLogFiles()
                return
            }
        }
        
        // Recherche plus approfondie - parcourir certains répertoires
        let searchDirectories = [
            "\(homeDir)/Games",
            "\(homeDir)/Applications",
            "\(homeDir)/Documents",
            "\(homeDir)/Desktop",
            "/Applications"
        ]
        
        for directory in searchDirectories {
            if fileManager.fileExists(atPath: directory) {
                searchDirectoryForLogFolder(directory, maxDepth: 5)
                if !logFolderPath.isEmpty {
                    // Vérifier s'il y a des fichiers de log existants dans le dossier
                    checkForExistingLogFiles()
                    return
                }
            }
        }
        
        logFolderExists = false
        updateStatus("Could not find WoW log folder automatically")
        print("No log folder found in any standard locations")
    }
    
    private func searchDirectoryForLogFolder(_ directory: String, maxDepth: Int) {
        guard maxDepth > 0 else { return }
        
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(atPath: directory)
            
            // Chercher directement un dossier "Logs"
            if contents.contains("Logs") {
                let path = "\(directory)/Logs"
                if fileManager.fileExists(atPath: path, isDirectory: nil) {
                    print("Found potential log folder during search: \(path)")
                    
                    // Vérifier si c'est un dossier de logs WoW en cherchant des fichiers .txt
                    do {
                        let logFiles = try fileManager.contentsOfDirectory(atPath: path)
                        if logFiles.contains(where: { $0.hasSuffix(".txt") && ($0.contains("WoWCombatLog") || $0.contains("CombatLog")) }) {
                            print("Confirmed as WoW log folder: \(path)")
                            logFolderPath = path
                            logFolderExists = true
                            updateStatus("Found log folder: \(path)")
                            return
                        }
                    } catch {
                        print("Error checking log folder contents: \(error)")
                    }
                }
            }
            
            // Recherche récursive dans les sous-dossiers
            for item in contents {
                if item == "." || item == ".." {
                    continue
                }
                
                let itemPath = "\(directory)/\(item)"
                var isDir: ObjCBool = false
                
                if fileManager.fileExists(atPath: itemPath, isDirectory: &isDir), isDir.boolValue {
                    // Vérifier si c'est un dossier pertinent
                    let relevantFolders = ["World of Warcraft", "_retail_", "_classic_", "Logs"]
                    if relevantFolders.contains(item) ||
                       item.contains("WoW") ||
                       item.contains("Warcraft") {
                        searchDirectoryForLogFolder(itemPath, maxDepth: maxDepth - 1)
                        
                        if !logFolderPath.isEmpty {
                            return
                        }
                    }
                }
            }
        } catch {
            print("Error searching directory \(directory): \(error)")
        }
    }
    
    func checkForExistingLogFiles() {
        do {
            let fileManager = FileManager.default
            let logFiles = try fileManager.contentsOfDirectory(atPath: logFolderPath)
                .filter { $0.hasSuffix(".txt") && ($0.contains("WoWCombatLog") || $0.contains("CombatLog")) }
                .sorted { (file1, file2) -> Bool in
                    // Trier par date de modification (plus récent d'abord)
                    let path1 = "\(logFolderPath)/\(file1)"
                    let path2 = "\(logFolderPath)/\(file2)"
                    
                    do {
                        let attrs1 = try fileManager.attributesOfItem(atPath: path1)
                        let attrs2 = try fileManager.attributesOfItem(atPath: path2)
                        
                        let date1 = attrs1[.modificationDate] as? Date ?? Date.distantPast
                        let date2 = attrs2[.modificationDate] as? Date ?? Date.distantPast
                        
                        return date1 > date2
                    } catch {
                        return false
                    }
                }
            
            if let mostRecentLog = logFiles.first {
                print("Found most recent log file: \(mostRecentLog)")
                lastProcessedLog = "\(logFolderPath)/\(mostRecentLog)"
                
                DispatchQueue.main.async {
                    self.logFilesFound = true
                    self.currentLogFile = mostRecentLog
                }
                
                updateStatus("Found log file: \(mostRecentLog)")
            } else {
                print("No log files found in folder yet")
                
                DispatchQueue.main.async {
                    self.logFilesFound = false
                    self.currentLogFile = nil
                }
                
                updateStatus("No log files found yet. Please generate logs in WoW.")
            }
        } catch {
            print("Error checking for existing log files: \(error)")
            
            DispatchQueue.main.async {
                self.logFilesFound = false
                self.currentLogFile = nil
            }
            
            updateStatus("Error checking log files: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Log Monitoring
    
    private func setupLogMonitoring() {
        // Configurer l'observateur de dossier pour détecter les nouveaux fichiers de log
        directoryObserver = DirectoryObserver(url: URL(fileURLWithPath: logFolderPath))
        directoryObserver?.startObserving { [weak self] newFile in
            guard let self = self else { return }
            
            if newFile.pathExtension.lowercased() == "txt" &&
               (newFile.lastPathComponent.contains("WoWCombatLog") ||
                newFile.lastPathComponent.contains("CombatLog")) {
                print("New log file detected: \(newFile.path)")
                self.processNewLogFile(newFile.path)
            }
        }
        
        // Configurer un timer pour vérifier régulièrement les mises à jour des fichiers existants
        logMonitorTimer?.invalidate() // Annuler un timer précédent si présent
        
        logMonitorTimer = Timer.scheduledTimer(withTimeInterval: monitorInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isMonitoring else { return }
            
            // Mettre à jour le temps de la dernière vérification
            let now = Date()
            DispatchQueue.main.async {
                self.lastLogCheck = now
            }
            
            // Vérifier si WoW est toujours en cours d'exécution
            let isRunning = self.isWoWRunning()
            if self.wowIsRunning != isRunning {
                self.wowIsRunning = isRunning
                if !isRunning {
                    self.updateStatus("WoW has been closed")
                    if self.currentGameType != nil {
                        self.gameEnded()
                    }
                } else {
                    self.updateStatus("WoW is now running - Monitoring")
                }
            }
            
            // Vérifier les mises à jour du fichier de log actuel
            if let logFile = self.lastProcessedLog {
                self.checkLogFileForChanges(logFile)
                
                // Indiquer que l'application est activement en train de monitorer les logs
                DispatchQueue.main.async {
                    if self.isMonitoring {
                        if self.wowIsRunning {
                            self.lastLogAnalysisResult = "Monitoring logs actively - WoW is running"
                        } else {
                            self.lastLogAnalysisResult = "Monitoring logs - Waiting for WoW"
                        }
                    }
                }
            } else {
                // Si aucun fichier de log n'a encore été traité, chercher des fichiers dans le dossier
                self.checkForExistingLogFiles()
                
                // Mettre à jour le status
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                    guard let self = self, self.isMonitoring else { return }
                    
                    // Si nous n'avons pas encore de détection d'arène après 20 secondes
                    // mais qu'il y a activité de combat, démarrer l'enregistrement par défaut
                    if self.currentGameType == nil && self.arenaDetector.isArenaLikelyActive() {
                        print("Auto-starting recording for potential arena match after delay")
                        self.gameDetected(type: .arena2v2, mapName: "Auto-detected Arena (Delay)")
                    }
                }
            }
        }
        
        updateStatus("Monitoring log folder")
    }
    
    private func processNewLogFile(_ filePath: String) {
        // Réinitialiser le détecteur pour le nouveau fichier
        arenaDetector.reset()
        lastProcessedLog = filePath
        print("Now monitoring log file: \(filePath)")
        
        DispatchQueue.main.async {
            self.currentLogFile = URL(fileURLWithPath: filePath).lastPathComponent
        }
        
        // Vérifier s'il y a une arène en cours
        checkForOngoingArena(in: filePath)
        
        // Lire tout le contenu du nouveau fichier
        do {
            let contents = try String(contentsOfFile: filePath, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines)
            
            print("Processing \(lines.count) lines from new log file")
            
            // Analyser chaque ligne pour détecter des événements
            for line in lines {
                if !line.isEmpty {
                    parseLine(line)
                }
            }
        } catch {
            print("Error reading new log file: \(error)")
        }
    }
    
    private func checkLogFileForChanges(_ filePath: String) {
        let fileManager = FileManager.default
        
        // Vérifier que le fichier existe encore
        guard fileManager.fileExists(atPath: filePath) else {
            print("Log file no longer exists: \(filePath)")
            lastProcessedLog = nil
            // Chercher un nouveau fichier de log
            checkForExistingLogFiles()
            return
        }
        
        // Obtenir les attributs du fichier
        guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return
        }
        
        // Vérifier si le fichier a été modifié depuis la dernière vérification
        if let lastCheck = lastLogCheck, modificationDate > lastCheck {
            print("Log file has been modified since last check")
            
            // Lire et analyser les nouvelles lignes
            readAndProcessLogFileChanges(filePath)
        }
    }
    
    private func readAndProcessLogFileChanges(_ filePath: String) {
        do {
            let contents = try String(contentsOfFile: filePath, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines)
            
            // Pour le débogage, imprimer spécifiquement les lignes contenant "ARENA"
            for line in lines {
                if line.contains("ARENA") {
                    print("ARENA DEBUG: Found line with ARENA: \(line)")
                }
            }
            
            // Prendre les 200 dernières lignes pour limiter le traitement
            let recentLines = lines.suffix(200)
            
            print("=========== PROCESSING LOG LINES ===========")
            print("Reading \(recentLines.count) recent lines from: \(filePath)")
            
            // Variables pour suivre ce qu'on a détecté
            var arenaEndDetected = false
            let recentLinesArray = Array(recentLines)
            
            // Utiliser le détecteur d'arène pour analyser tout le batch de lignes
            let arenaDetected = arenaDetector.analyzeBatch(recentLinesArray)
            if arenaDetected {
                print("Arena match detected by ArenaDetector!")
            }
            
            // Traiter chaque ligne individuellement pour d'autres événements
            for line in recentLinesArray {
                // Vérifier que la ligne n'est pas vide pour éviter les crashes
                guard !line.isEmpty else { continue }
                
                // Passer chaque ligne au détecteur d'arène
                arenaDetector.processLine(line)
                
                // Détection spécifique de fin d'arène
                if line.contains("ARENA_MATCH_END") {
                    print("ARENA MATCH END DETECTED: \(line)")
                    arenaEndDetected = true
                    
                    // Si nous avons un enregistrement en cours, l'arrêter
                    if currentGameType != nil {
                        gameEnded()
                    } else {
                        print("WARNING: Arena match end detected but no recording was active!")
                    }
                }
                
                // Continuer le traitement normal des lignes
                parseLine(line)
            }
            
            print("=========== END OF LOG PROCESSING ===========")
            
            // Mise à jour de l'interface utilisateur
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Mettre à jour le statut pour montrer si une arène est détectée
                if arenaDetected || arenaDetector.isArenaLikelyActive() {
                    self.lastLogAnalysisResult = "Arena activity detected at \(Date().formatted(date: .omitted, time: .shortened))"
                } else if arenaEndDetected {
                    self.lastLogAnalysisResult = "Arena match ended at \(Date().formatted(date: .omitted, time: .shortened))"
                } else {
                    self.lastLogAnalysisResult = "Log analyzed: \(Date().formatted(date: .omitted, time: .shortened))"
                }
            }
            
        } catch {
            print("Error reading log file changes: \(error)")
        }
    }

// MARK: - Arena Event Handlers

    private func handleArenaMatchStart(_ logLine: LogLine) {
        // Extraire les informations nécessaires
        let arenaType: GameType
        let typeStr = logLine.arg(3) ?? ""
        if !typeStr.isEmpty {
            if typeStr.contains("2v2") {
                arenaType = .arena2v2
            } else if typeStr.contains("3v3") {
                arenaType = .arena3v3
            } else {
                arenaType = .arena2v2 // Par défaut
            }
        } else {
            arenaType = .arena2v2 // Par défaut
        }
        
        // Essayer d'obtenir le nom de l'arène si disponible
        let mapID = logLine.arg(1) ?? "0"
        let arenaName = getArenaNameFromMapID(mapID)
        
        print("DETECTED: Arena match start - Type \(arenaType.rawValue), Map \(arenaName)")
        gameDetected(type: arenaType, mapName: arenaName)
    }
    
    
private func handleArenaMatchEnd(_ logLine: LogLine) {
    // Déterminer si victoire ou défaite
    let result = "Match Ended"
    
    print("DETECTED: Arena match ended - Result: \(result)")
    gameEnded()
}

private func handleArenaPreparation(_ logLine: LogLine) {
    // Extraire les informations nécessaires
    let arenaType: GameType = .arena2v2  // Par défaut
    
    // Essayer d'obtenir le nom de l'arène si disponible
    let arenaName = determineArenaMap(from: logLine.original)
    
    print("DETECTED: Arena preparation - Type \(arenaType.rawValue), Map \(arenaName)")
    potentialArenaInProgress = true
    gameDetected(type: arenaType, mapName: arenaName)
}
    
    func analyzeSpecificLogFile(_ path: String) {
        print("Analyzing specific log file: \(path)")
        
        do {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines)
            
            print("Reading \(lines.count) lines from log file")
            
            // Rechercher spécifiquement les événements ARENA
            var arenaStartLines = 0
            var arenaEndLines = 0
            var arenaRelatedLines = 0
            
            for line in lines {
                if line.contains("ARENA_MATCH_START") {
                    print("FOUND ARENA_MATCH_START: \(line)")
                    arenaStartLines += 1
                }
                if line.contains("ARENA_MATCH_END") {
                    print("FOUND ARENA_MATCH_END: \(line)")
                    arenaEndLines += 1
                }
                if line.contains("ARENA") {
                    arenaRelatedLines += 1
                }
            }
            
            print("Analysis complete. Found \(arenaStartLines) ARENA_MATCH_START events, \(arenaEndLines) ARENA_MATCH_END events, and \(arenaRelatedLines) arena-related lines.")
            
        } catch {
            print("Error analyzing log file: \(error)")
        }
    }

private func getArenaNameFromMapID(_ mapID: String) -> String {
    // Mappage des IDs vers les noms d'arène (à remplir avec des valeurs réelles)
    let arenaMap = [
        "559": "Nagrand Arena",
        "562": "Blade's Edge Arena",
        "572": "Ruins of Lordaeron",
        "617": "Dalaran Sewers",
        "980": "Tol'viron Arena",
        "1134": "Tiger's Peak",
        "1552": "Black Rook Hold Arena",
        "1504": "Hook Point",
        "2167": "Maldraxxus Arena",
        "2620": "Empyrean Domain"
    ]
    
    return arenaMap[mapID] ?? "Unknown Arena"
}

// MARK: - Event Handlers

private func handleMythicPlusEvent(_ line: String) {
    // Détecter le début d'un donjon mythique+
    if line.contains("CHALLENGE_MODE_START") ||
       line.lowercased().contains("mythic keystone run started") ||
       line.lowercased().contains("challenge mode began") {
        
        print("DETECTED: Mythic+ dungeon beginning...")
        
        // Déterminer le nom du donjon
        var dungeonName = "Unknown Dungeon"
        
        // Liste des noms de donjons (mise à jour pour inclure plusieurs extensions)
        let dungeons = [
            // Dragonflight
            "Ruby Life Pools", "The Nokhud Offensive", "The Azure Vault", "Algeth'ar Academy",
            "Uldaman: Legacy of Tyr", "Neltharus", "Brackenhide Hollow", "Halls of Infusion",
            "Dawn of the Infinite",
            
            // Shadowlands
            "The Necrotic Wake", "Plaguefall", "Mists of Tirna Scithe", "Halls of Atonement",
            "Theater of Pain", "De Other Side", "Spires of Ascension", "Sanguine Depths",
            "Tazavesh"
        ]
        
        for dungeon in dungeons {
            if line.lowercased().contains(dungeon.lowercased()) {
                dungeonName = dungeon
                break
            }
        }
        
        // Extraire le niveau du mythique
        var mythicLevel = 0
        if let match = line.range(of: #"Mythic \+(\d+)"#, options: .regularExpression) {
            let levelString = String(line[match])
                .replacingOccurrences(of: "Mythic +", with: "")
            mythicLevel = Int(levelString) ?? 0
        }
        
        // Créer le nom du donjon avec le niveau si disponible
        let mapName = mythicLevel > 0 ? "\(dungeonName) +\(mythicLevel)" : dungeonName
        
        print("DETECTED: Mythic+ dungeon - \(mapName)")
        gameDetected(type: .mythicPlus, mapName: mapName)
    }
    // Détecter la fin d'un donjon mythique+
    else if line.contains("CHALLENGE_MODE_END") ||
            line.lowercased().contains("mythic keystone run completed") ||
            line.lowercased().contains("challenge mode completed") {
        
        print("DETECTED: Mythic+ dungeon ended")
        gameEnded()
    }
}

private func handleSkirmishEvent(_ line: String) {
    // Envelopper dans un bloc do-catch pour éviter les crashes
    do {
        // Détecter le début grâce à l'aura de préparation
        if line.contains("SPELL_AURA_APPLIED") && line.contains("ARENA_PREPARATION") {
            print("DETECTED: Skirmish beginning via preparation aura")
            let mapName = determineArenaMap(from: line)
            gameDetected(type: .skirmish, mapName: mapName)
            return
        }
        
        // Autres méthodes de détection existantes
        if line.contains("ARENA_SKIRMISH_START") ||
           line.lowercased().contains("skirmish started") ||
           line.lowercased().contains("entering skirmish") ||
           line.lowercased().contains("skirmish queue") ||
           line.lowercased().contains("skirmish match has begun") {
            
            let mapName = determineArenaMap(from: line)
            gameDetected(type: .skirmish, mapName: mapName)
            print("Detected skirmish on map: \(mapName)")
            return
        }
        
        // Détecter la fin d'un skirmish
        if line.contains("ARENA_SKIRMISH_END") ||
           line.lowercased().contains("skirmish ended") ||
           line.lowercased().contains("skirmish match complete") {
            
            gameEnded()
            print("Skirmish ended")
        }
    } catch {
        print("Error in handleSkirmishEvent: \(error)")
    }
}

    private func handleArenaEvent(_ line: String) {
        do {
            // Ne traiter que les événements vraiment importants d'arène
            if line.contains("ARENA_MATCH_START") {
                print("DETECTED: Arena match beginning via ARENA_MATCH_START")
                
                // Déterminer le type d'arène
                let arenaType: GameType
                if line.contains("2v2") || line.contains("2 vs 2") {
                    arenaType = .arena2v2
                } else if line.contains("3v3") || line.contains("3 vs 3") {
                    arenaType = .arena3v3
                } else if line.contains("5v5") || line.contains("5 vs 5") {
                    arenaType = .arena5v5
                } else {
                    // Par défaut, considérer comme 2v2
                    arenaType = .arena2v2
                }
                
                // Démarrer uniquement si aucun enregistrement n'est déjà en cours
                if currentGameType == nil {
                    gameDetected(type: arenaType, mapName: "Arena (Direct Detection)")
                }
                return
            }
            
            // Détection spécifique de fin d'arène
            if line.contains("ARENA_MATCH_END") {
                print("DETECTED: Arena match ended")
                gameEnded()
                return
            }
        } catch {
            print("Error in handleArenaEvent: \(error)")
        }
    }

private func determineArenaMap(from line: String) -> String {
    let arenaNames = [
        "Nagrand": "Nagrand Arena",
        "Blade's Edge": "Blade's Edge Arena",
        "Blades Edge": "Blade's Edge Arena",
        "Ruins of Lordaeron": "Ruins of Lordaeron",
        "Dalaran": "Dalaran Sewers",
        "Tol'viron": "Tol'viron Arena",
        "Tolviron": "Tol'viron Arena",
        "Tiger's Peak": "The Tiger's Peak",
        "Tigers Peak": "The Tiger's Peak",
        "Black Rook": "Black Rook Hold Arena",
        "Hook Point": "Hook Point",
        "Maldraxxus": "Maldraxxus Arena",
        "Empyrean Domain": "The Empyrean Domain",
        "Enigma Crucible": "Enigma Crucible"
    ]
    
    for (keyword, arenaName) in arenaNames {
        if line.contains(keyword) {
            return arenaName
        }
    }
    
    return "Unknown Arena"
}

private func handleBattlegroundEvent(_ line: String) {
    // Détecter le début d'un champ de bataille
    if line.contains("BATTLEFIELD_MATCH_START") ||
       line.contains("Entering Battleground") ||
       line.lowercased().contains("battleground has begun") {
        
        print("DETECTED: Battleground beginning...")
        
        // Déterminer le nom du champ de bataille
        var bgName = "Unknown Battleground"
        
        // Liste des champs de bataille
        let battlegrounds = [
            "Warsong Gulch", "Arathi Basin", "Alterac Valley", "Eye of the Storm",
            "Strand of the Ancients", "Isle of Conquest", "Deepwind Gorge", "Twin Peaks",
            "Battle for Gilneas", "Temple of Kotmogu", "Silvershard Mines",
            "Seething Shore", "Wintergrasp", "Ashran"
        ]
        
        for bg in battlegrounds {
            if line.lowercased().contains(bg.lowercased()) {
                bgName = bg
                break
            }
        }
        
        print("DETECTED: Battleground - \(bgName)")
        gameDetected(type: .battleground, mapName: bgName)
    }
    // Détecter la fin d'un champ de bataille
    else if line.contains("BATTLEFIELD_MATCH_END") ||
            line.lowercased().contains("battleground has ended") ||
            line.lowercased().contains("battleground complete") {
        
        print("DETECTED: Battleground ended")
        gameEnded()
    }
}

private func handleRaidEvent(_ line: String) {
    // Détecter le début d'un raid
    if line.contains("ENCOUNTER_START") ||
       line.lowercased().contains("raid encounter started") ||
       line.lowercased().contains("begins combat with") {
        
        print("DETECTED: Raid encounter beginning...")
        
        // Déterminer le nom du raid/boss
        var raidName = "Unknown Raid"
        
        // Liste des raids récents
        let raids = [
            // Dragonflight
            "Amirdrassil", "Aberrus", "Vault of the Incarnates",
            
            // Shadowlands
            "Sepulcher of the First Ones", "Sanctum of Domination", "Castle Nathria"
        ]
        
        for raid in raids {
            if line.lowercased().contains(raid.lowercased()) {
                raidName = raid
                break
            }
        }
        
        // Si le nom du raid n'est pas identifié, essayer d'extraire le nom du boss
        if raidName == "Unknown Raid" {
            // Tentative d'extraction du nom du boss
            let bossPattern = #"combat with (.*?)[\.!]"#
            if let range = line.range(of: bossPattern, options: .regularExpression),
               let bossName = line[range]
                .replacingOccurrences(of: "combat with ", with: "")
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: "!", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? nil : line[range]
                .replacingOccurrences(of: "combat with ", with: "")
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: "!", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines) {
                
                raidName = "Boss: \(bossName)"
            }
        }
        
        print("DETECTED: Raid - \(raidName)")
        gameDetected(type: .raid, mapName: raidName)
    }
    // Détecter la fin d'un raid
    else if line.contains("ENCOUNTER_END") ||
            line.lowercased().contains("raid encounter ended") ||
            line.lowercased().contains("has been defeated") {
        
        print("DETECTED: Raid encounter ended")
        gameEnded()
    }
}

// MARK: - Debug & Testing

func simulateSkirmishDetection() {
    print("Simulating skirmish detection")
    gameDetected(type: .skirmish, mapName: "Nagrand Arena (Simulated)")
    
    // Simuler la fin après quelques secondes
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
        guard let self = self else { return }
        print("Simulating skirmish end")
        self.gameEnded()
    }
}

// MARK: - Debug Simulation

#if DEBUG
private func simulateGameDetection() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
        guard let self = self else { return }
        
        print("Simulating game detection in 5 seconds")
        self.gameDetected(type: .arena2v2, mapName: "Nagrand Arena (Simulated)")
        
        // Simuler la fin après 15 secondes
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self else { return }
            self.gameEnded()
        }
    }
}
#endif
}

// MARK: - Directory Observer

// Classe auxiliaire pour observer les changements dans un dossier
class DirectoryObserver {
private let url: URL
private var source: DispatchSourceFileSystemObject?

init(url: URL) {
    self.url = url
}

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
        
        // Vérifier les nouveaux fichiers dans le dossier
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: self.url, includingPropertiesForKeys: [.contentModificationDateKey])
            
            // Trier par date de modification (plus récent d'abord)
            let sortedFiles = contents.sorted { file1, file2 in
                do {
                    let date1 = try file1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                    let date2 = try file2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                    return date1 > date2
                } catch {
                    return false
                }
            }
            
            // Si des fichiers existent et qu'ils ont été modifiés récemment
            if let mostRecent = sortedFiles.first {
                // Vérifier si c'est un fichier de log récent (modifié dans les 10 dernières secondes)
                do {
                    let attrs = try mostRecent.resourceValues(forKeys: [.contentModificationDateKey])
                    if let modDate = attrs.contentModificationDate,
                       Date().timeIntervalSince(modDate) < 10 {
                        // Appeler le handler avec le fichier le plus récent
                        handler(mostRecent)
                    }
                } catch {
                    print("Error checking file modification date: \(error)")
                }
            }
        } catch {
            print("Error observing directory changes: \(error)")
        }
    }
    
    source?.setCancelHandler {
        close(descriptor)
    }
    
    source?.resume()
    print("Started observing directory: \(url.path)")
}

func stopObserving() {
    source?.cancel()
    source = nil
    print("Stopped observing directory")
}
}
