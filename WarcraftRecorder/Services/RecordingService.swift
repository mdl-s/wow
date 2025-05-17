//
//  RecordingService.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//

import SwiftUI
import Combine
import AVFoundation

class RecordingService: NSObject, ObservableObject {
    // États observables
    @Published var isRecording = false
    @Published var currentRecordingPath: String?
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingStatus = "Ready"
    @Published var recordingError: String?
    
    var recordingsFolder: String
    
    // Internes
    private var startTime: Date?
    private var timer: Timer?
    private var currentRecordingInfo: (gameType: GameType, mapName: String)?
    
    // AVFoundation
    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    
    override init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let warcraftRecorderPath = documentsPath.appendingPathComponent("Warcraft Recorder")
        if !FileManager.default.fileExists(atPath: warcraftRecorderPath.path) {
            try? FileManager.default.createDirectory(at: warcraftRecorderPath, withIntermediateDirectories: true)
        }
        self.recordingsFolder = warcraftRecorderPath.path
        super.init()
        print("RecordingService initialized with recordings folder: \(self.recordingsFolder)")
    }
    
    // MARK: - Public API
    
    func startRecording(gameType: GameType, mapName: String) -> String? {
        guard !isRecording else {
            recordingStatus = "Already recording"
            print("Recording already in progress")
            return nil
        }
        
        // Génère le chemin du fichier MOV
        let path = generateFilePath(gameType: gameType, mapName: mapName)
        let url = URL(fileURLWithPath: path)
        
        let directoryURL = URL(fileURLWithPath: recordingsFolder)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            self.recordingError = "Failed to create recordings directory: \(error.localizedDescription)"
            return nil
        }
        
        // Prépare la capture vidéo AVFoundation
        captureSession = AVCaptureSession()
        guard let input = AVCaptureScreenInput(displayID: CGMainDisplayID()) else {
            print("Failed to create AVCaptureScreenInput")
            recordingError = "Screen input creation failed"
            return nil
        }
        input.capturesCursor = false
        input.capturesMouseClicks = false
        if captureSession!.canAddInput(input) {
            captureSession!.addInput(input)
        } else {
            print("Cannot add screen input to capture session")
            recordingError = "Failed to add input"
            captureSession = nil
            return nil
        }
        
        movieOutput = AVCaptureMovieFileOutput()
        if captureSession!.canAddOutput(movieOutput!) {
            captureSession!.addOutput(movieOutput!)
        } else {
            print("Cannot add movie output to capture session")
            recordingError = "Failed to add movie output"
            captureSession = nil
            return nil
        }
        
        captureSession!.startRunning()
        movieOutput!.startRecording(to: url, recordingDelegate: self)
        
        startTime = Date()
        isRecording = true
        currentRecordingPath = path
        currentRecordingInfo = (gameType, mapName)
        recordingStatus = "Recording..."
        startDurationTimer()
        
        print("Recording started for: \(gameType.rawValue) - \(mapName)")
        return path
    }
    
    func stopRecording() -> Recording? {
        guard isRecording, let startTime = self.startTime, let info = currentRecordingInfo else {
            recordingStatus = "Not recording"
            print("Cannot stop recording: not recording")
            return nil
        }
        print("Stopping recording...")
        recordingStatus = "Finalizing recording..."
        isRecording = false // <-- AJOUT ICI pour éviter double stop
        movieOutput?.stopRecording()
        captureSession?.stopRunning()
        captureSession = nil
        movieOutput = nil
        timer?.invalidate()
        timer = nil
        recordingStatus = "Ready"
        let duration = Date().timeIntervalSince(startTime)
        let recordingPath = currentRecordingPath ?? ""
        currentRecordingPath = nil
        let recording = Recording(
            type: info.gameType,
            mapName: info.mapName,
            date: startTime,
            duration: duration,
            filePath: recordingPath,
            result: "Completed",
            difficulty: info.gameType == .mythicPlus ? 10 : 0,
            players: []
        )
        currentRecordingInfo = nil
        self.startTime = nil
        print("Recording stopped: \(recordingPath)")
        return recording
    }

    
    func cancelRecording() {
        if isRecording {
            print("Cancelling recording...")
            movieOutput?.stopRecording()
            captureSession?.stopRunning()
            captureSession = nil
            movieOutput = nil
            timer?.invalidate()
            timer = nil
            if let path = currentRecordingPath, FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: path)
            }
            isRecording = false
            currentRecordingPath = nil
            recordingStatus = "Ready"
            recordingDuration = 0
            currentRecordingInfo = nil
            startTime = nil
        }
    }
    
    // MARK: - Outils internes
    
    private func startDurationTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            self.recordingDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    private func generateFilePath(gameType: GameType, mapName: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let sanitizedMapName = mapName.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "/", with: "_")
        let filename = "\(gameType.rawValue)_\(sanitizedMapName)_\(timestamp).mov"
        return "\(recordingsFolder)/\(filename)"
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension RecordingService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Recording error: \(error)")
            DispatchQueue.main.async {
                self.recordingError = error.localizedDescription
            }
        } else {
            print("Finished recording: \(outputFileURL)")
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Started recording to file: \(fileURL)")
    }
}
