//
//  StorageService.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//

import Foundation
import Combine
import SwiftUI

class StorageService: ObservableObject {
    // États observables
    @Published var allRecordings: [Recording] = []
    @Published var isLoading: Bool = false
    @Published var loadingError: String?
    
    // Configuration
    private let recordingsKey = "savedRecordings"
    private let storageType: StorageType
    private let fileManager = FileManager.default
    
    // Dépendances
    private var cancellables = Set<AnyCancellable>()
    
    enum StorageType {
        case userDefaults
        case fileSystem(String)
        case synchronizedCloud
    }
    
    // MARK: - Initialisation
    
    init(storageType: StorageType = .userDefaults) {
        self.storageType = storageType
        loadRecordings()
    }
    
    // MARK: - API Publique
    
    func saveRecording(_ recording: Recording) {
        // Vérifier que le fichier existe
        guard fileManager.fileExists(atPath: recording.filePath) else {
            print("Warning: Recording file does not exist at path: \(recording.filePath)")
            return // Ajoutez un return pour sortir de la fonction si la condition échoue
        }
        // Ajouter ou mettre à jour l'enregistrement
        if let existingIndex = allRecordings.firstIndex(where: { $0.id == recording.id }) {
            allRecordings[existingIndex] = recording
        } else {
            allRecordings.append(recording)
        }
        
        saveAllRecordings()
    }
    
    func updateRecording(_ recording: Recording) {
        if let index = allRecordings.firstIndex(where: { $0.id == recording.id }) {
            allRecordings[index] = recording
            saveAllRecordings()
        }
    }
    
    func deleteRecording(_ recording: Recording) {
        // Supprimer de la liste
        if let index = allRecordings.firstIndex(where: { $0.id == recording.id }) {
            allRecordings.remove(at: index)
            saveAllRecordings()
            
            // Supprimer le fichier vidéo
            deleteVideoFile(path: recording.filePath)
        }
    }
    
    func getRecordingsForType(_ type: GameType) -> [Recording] {
        return allRecordings.filter { $0.type == type }
    }
    
    func findRecording(withID id: UUID) -> Recording? {
        return allRecordings.first(where: { $0.id == id })
    }
    
    func refreshRecordings() {
        loadRecordings()
    }
    
    // MARK: - Gestion du stockage
    
    private func loadRecordings() {
        isLoading = true
        loadingError = nil
        
        switch storageType {
        case .userDefaults:
            loadFromUserDefaults()
        case .fileSystem(let path):
            loadFromFileSystem(path: path)
        case .synchronizedCloud:
            loadFromCloud()
        }
    }
    
    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: recordingsKey) else {
            // Pas d'enregistrements sauvegardés
            createSampleRecordingsIfEmpty()
            isLoading = false
            return
        }
        
        do {
            let decoder = JSONDecoder()
            allRecordings = try decoder.decode([Recording].self, from: data)
            
            // Vérifier les fichiers existants
            validateRecordingFiles()
            isLoading = false
        } catch {
            loadingError = "Error loading recordings: \(error.localizedDescription)"
            createSampleRecordingsIfEmpty()
            isLoading = false
        }
    }
    
    private func loadFromFileSystem(path: String) {
        let recordingsFilePath = "\(path)/recordings.json"
        
        if fileManager.fileExists(atPath: recordingsFilePath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: recordingsFilePath))
                let decoder = JSONDecoder()
                allRecordings = try decoder.decode([Recording].self, from: data)
                validateRecordingFiles()
                isLoading = false
            } catch {
                loadingError = "Error loading recordings from file: \(error.localizedDescription)"
                createSampleRecordingsIfEmpty()
                isLoading = false
            }
        } else {
            createSampleRecordingsIfEmpty()
            saveAllRecordings() // Créer le fichier pour la prochaine fois
            isLoading = false
        }
    }
    
    private func loadFromCloud() {
        // Future implementation for Cloud syncing
        // Pour l'instant, on utilise UserDefaults
        loadFromUserDefaults()
    }
    
    private func saveAllRecordings() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(allRecordings)
            
            switch storageType {
            case .userDefaults:
                UserDefaults.standard.set(data, forKey: recordingsKey)
                
            case .fileSystem(let path):
                // S'assurer que le dossier existe
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
                
                let recordingsFilePath = "\(path)/recordings.json"
                try data.write(to: URL(fileURLWithPath: recordingsFilePath))
                
            case .synchronizedCloud:
                // Future implementation
                UserDefaults.standard.set(data, forKey: recordingsKey)
            }
        } catch {
            print("Error saving recordings: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Gestion des fichiers
    
    private func deleteVideoFile(path: String) {
        do {
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
        } catch {
            print("Error deleting video file: \(error.localizedDescription)")
        }
    }
    
    private func validateRecordingFiles() {
        // Filtrer les enregistrements avec des fichiers manquants
        allRecordings = allRecordings.filter { recording in
            let fileExists = fileManager.fileExists(atPath: recording.filePath)
            if !fileExists {
                print("Warning: Recording file missing: \(recording.filePath)")
            }
            return fileExists
        }
    }
    
    // MARK: - Données d'exemple
    
    private func createSampleRecordingsIfEmpty() {
        if allRecordings.isEmpty {
            createSampleRecordings()
        }
    }
    
    private func createSampleRecordings() {
        let now = Date()
        
        // Créer des enregistrements d'exemple
        let samples = [
            Recording(
                type: .arena2v2,
                mapName: "Nagrand Arena",
                date: now.addingTimeInterval(-3600),  // 1 heure avant
                duration: 380,
                filePath: "\(getDocumentsDirectory())/sample_arena2v2.mp4",
                result: "+2",
                difficulty: 0,
                players: ["Player1", "Player2", "Opponent1", "Opponent2"]
            ),
            Recording(
                type: .arena3v3,
                mapName: "Blade's Edge Arena",
                date: now.addingTimeInterval(-7200),  // 2 heures avant
                duration: 420,
                filePath: "\(getDocumentsDirectory())/sample_arena3v3.mp4",
                result: "+1",
                difficulty: 0,
                players: ["Player1", "Player2", "Player3", "Opponent1", "Opponent2", "Opponent3"]
            ),
            Recording(
                type: .mythicPlus,
                mapName: "The Necrotic Wake",
                date: now.addingTimeInterval(-14400),  // 4 heures avant
                duration: 1800,
                filePath: "\(getDocumentsDirectory())/sample_mythic.mp4",
                result: "+15",
                difficulty: 15,
                players: ["Player1", "Player2", "Player3", "Player4", "Player5"]
            ),
            Recording(
                type: .battleground,
                mapName: "Warsong Gulch",
                date: now.addingTimeInterval(-28800),  // 8 heures avant
                duration: 960,
                filePath: "\(getDocumentsDirectory())/sample_bg.mp4",
                result: "Win",
                difficulty: 0,
                players: []
            ),
            Recording(
                type: .raid,
                mapName: "Castle Nathria",
                date: now.addingTimeInterval(-86400),  // 1 jour avant
                duration: 3600,
                filePath: "\(getDocumentsDirectory())/sample_raid.mp4",
                result: "Completed",
                difficulty: 10,
                players: []
            )
        ]
        
        // Créez des fichiers factices pour les exemples
        createSampleFiles(for: samples)
        
        // Ajouter les échantillons à la collection
        allRecordings.append(contentsOf: samples)
    }
    
    private func createSampleFiles(for recordings: [Recording]) {
        // Créer des fichiers vidéo vides pour les exemples
        for recording in recordings {
            _ = URL(fileURLWithPath: recording.filePath)
            if !fileManager.fileExists(atPath: recording.filePath) {
                fileManager.createFile(atPath: recording.filePath, contents: Data())
            }
        }
    }
    
    private func getDocumentsDirectory() -> String {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].path
    }
    
    // MARK: - Fonctions utilitaires
    
    func getRecordingStats() -> RecordingStats {
        let totalCount = allRecordings.count
        let totalDuration = allRecordings.reduce(0) { $0 + $1.duration }
        
        var countByType: [GameType: Int] = [:]
        var durationByType: [GameType: TimeInterval] = [:]
        
        for type in GameType.allCases {
            let recordings = getRecordingsForType(type)
            countByType[type] = recordings.count
            durationByType[type] = recordings.reduce(0) { $0 + $1.duration }
        }
        
        return RecordingStats(
            totalCount: totalCount,
            totalDuration: totalDuration,
            countByType: countByType,
            durationByType: durationByType
        )
    }
    
    func exportRecording(_ recording: Recording, to destination: URL, completionHandler: @escaping (Result<URL, Error>) -> Void) {
        let sourceURL = URL(fileURLWithPath: recording.filePath)
        
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
            completionHandler(.success(destination))
        } catch {
            completionHandler(.failure(error))
        }
    }
}

// MARK: - Structures auxiliaires

struct RecordingStats {
    let totalCount: Int
    let totalDuration: TimeInterval
    let countByType: [GameType: Int]
    let durationByType: [GameType: TimeInterval]
}
