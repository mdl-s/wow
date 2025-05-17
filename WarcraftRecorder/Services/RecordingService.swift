//
//  RecordingService.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//
import SwiftUI
import Combine
import AVFoundation

class RecordingService: ObservableObject {
    // États observables
    @Published var isRecording = false
    @Published var currentRecordingPath: String?
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingStatus = "Ready"
    @Published var recordingError: String?
    
    // Configuration
    var recordingsFolder: String
    
    // État interne
    private var startTime: Date?
    private var timer: Timer?
    private var currentRecordingInfo: (gameType: GameType, mapName: String)?
    private var recordingProcess: Process?
    
    // Initialisation
    init(recordingsFolder: String? = nil) {
        if let folder = recordingsFolder {
            self.recordingsFolder = folder
        } else {
            // Utiliser le dossier Documents par défaut
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let warcraftRecorderPath = documentsPath.appendingPathComponent("Warcraft Recorder")
            
            // Créer le dossier s'il n'existe pas
            if !FileManager.default.fileExists(atPath: warcraftRecorderPath.path) {
                try? FileManager.default.createDirectory(at: warcraftRecorderPath, withIntermediateDirectories: true)
            }
            
            self.recordingsFolder = warcraftRecorderPath.path
        }
        
        print("RecordingService initialized with recordings folder: \(self.recordingsFolder)")
    }
    
    // MARK: - API Publique
    
    func startRecording(gameType: GameType, mapName: String) -> String? {
        guard !isRecording else {
            recordingStatus = "Already recording"
            print("Recording already in progress")
            return nil
        }
        
        // Générer un chemin de fichier pour l'enregistrement
        let path = generateFilePath(gameType: gameType, mapName: mapName)
        print("Generated recording path: \(path)")
        
        recordingStatus = "Starting recording..."
        
        // S'assurer que le dossier existe
        let directoryURL = URL(fileURLWithPath: recordingsFolder)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            print("Ensured recordings directory exists: \(directoryURL.path)")
        } catch {
            print("Error creating recordings directory: \(error)")
            self.recordingError = "Failed to create recordings directory: \(error.localizedDescription)"
            return nil
        }
        
        // Démarrer l'enregistrement avec screencapture
        if startScreenCapture(outputPath: path) {
            isRecording = true
            currentRecordingPath = path
            currentRecordingInfo = (gameType, mapName)
            startTime = Date()
            
            // Démarrer le timer pour suivre la durée
            startDurationTimer()
            
            recordingStatus = "Recording..."
            print("Recording started for: \(gameType.rawValue) - \(mapName)")
            return path
        } else {
            recordingStatus = "Failed to start recording"
            print("Failed to start recording")
            return nil
        }
    }
    
    func stopRecording() -> Recording? {
        guard isRecording, let startTime = self.startTime, let info = currentRecordingInfo else {
            recordingStatus = "Not recording"
            print("Cannot stop recording: not recording")
            return nil
        }
        
        print("Stopping recording...")
        recordingStatus = "Finalizing recording..."
        
        // Arrêter l'enregistrement
        stopScreenCapture()
        
        // Attendre que l'enregistrement soit finalisé
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            
            // Arrêter le timer après la finalisation
            self.timer?.invalidate()
            self.timer = nil
            
            // Réinitialiser les états
            self.isRecording = false
            self.recordingStatus = "Ready"
            self.recordingDuration = 0
        }
        
        // Calculer la durée finale
        let duration = Date().timeIntervalSince(startTime)
        print("Recording duration: \(duration) seconds")
        
        // Conserver le chemin du fichier enregistré
        let recordingPath = currentRecordingPath ?? ""
        currentRecordingPath = nil
        
        // Vérifier que le fichier existe et a une taille valide
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: recordingPath) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: recordingPath)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                print("Recorded file size: \(fileSize) bytes")
                
                if fileSize == 0 {
                    print("WARNING: Recorded file has zero size, recording may have failed")
                }
            } catch {
                print("Error checking file size: \(error)")
            }
        } else {
            print("WARNING: Recorded file does not exist at path: \(recordingPath)")
        }
        
        // Créer un enregistrement pour l'historique
        let recording = Recording(
            type: info.gameType,
            mapName: info.mapName,
            date: startTime,
            duration: duration,
            filePath: recordingPath,
            result: "Completed",  // À déterminer dynamiquement plus tard
            difficulty: info.gameType == .mythicPlus ? 10 : 0,  // À déterminer dynamiquement plus tard
            players: []  // À remplir dynamiquement plus tard
        )
        
        currentRecordingInfo = nil
        self.startTime = nil
        
        print("Recording stopped: \(recordingPath)")
        return recording
    }
    
    func cancelRecording() {
        if isRecording {
            print("Cancelling recording...")
            
            stopScreenCapture()
            
            // Arrêter le timer
            timer?.invalidate()
            timer = nil
            
            // Supprimer le fichier partiellement enregistré
            if let path = currentRecordingPath, FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                    print("Deleted partial recording: \(path)")
                } catch {
                    print("Failed to delete partial recording: \(error)")
                }
            }
            
            // Réinitialiser les états
            isRecording = false
            currentRecordingPath = nil
            recordingStatus = "Ready"
            recordingDuration = 0
            currentRecordingInfo = nil
            startTime = nil
        }
    }
    
    // MARK: - Gestion de la durée
    
    private func startDurationTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            self.recordingDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    // MARK: - Gestion des fichiers
    
    private func generateFilePath(gameType: GameType, mapName: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let sanitizedMapName = mapName.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "/", with: "_")
        
        let filename = "\(gameType.rawValue)_\(sanitizedMapName)_\(timestamp).mp4"
        return "\(recordingsFolder)/\(filename)"
    }
    
    // MARK: - Screen Capture avec l'utilitaire système
    
    private func startScreenCapture(outputPath: String) -> Bool {
        // Utiliser l'utilitaire screencapture intégré à macOS
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        
        // -v: verbose
        // -V: durée en secondes (24h = 86400 secondes)
        // -c: capture depuis caméra si disponible (facultatif)
        // -a: capture audio
        // -U: capture entire screen (pas seulement une fenêtre)
        process.arguments = ["-v", "-V", "86400", "-a", "-U", outputPath]
        
        do {
            try process.run()
            print("Screen capture process started")
            recordingProcess = process
            return true
        } catch {
            print("Failed to start screen capture: \(error)")
            recordingError = "Failed to start screen capture: \(error.localizedDescription)"
            return false
        }
    }
    
    private func stopScreenCapture() {
        if let process = recordingProcess, process.isRunning {
            // Terminer proprement le processus
            process.terminate()
            print("Screen capture process terminated")
            recordingProcess = nil
        }
    }
}
