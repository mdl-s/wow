//
//  ArenaDetector.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 14/05/2025.
//

import Foundation

// Un détecteur simplifié pour les événements d'arène
class ArenaDetector {
    // Callbacks
    var onArenaStart: ((GameType, String) -> Void)?
    var onArenaEnd: (() -> Void)?
    
    // État
    private var arenaInProgress = false
    private var combatIntensity = 0
    private var playerCount = Set<String>()
    private var lastArenaEvent: Date?
    private var arenaPreparationDetected = false
    
    // Pour la compatibilité avec le code existant
    func isArenaLikelyActive() -> Bool {
        return arenaInProgress
    }
    
    // Analyser un ensemble de lignes pour détecter une arène
    func analyzeBatch(_ lines: [String]) -> Bool {
        var hasArenaData = false
        var hasArenaPreparation = false
        var pvpRelatedLines = 0
        var damageEvents = 0
        
        let tempPlayers = Set<String>()
        
        // Première passe - chercher explicitement les événements d'arène
        for line in lines where !line.isEmpty {
            // Événements clés d'arène
            if line.contains("ARENA_MATCH_START") {
                print("BATCH: Found ARENA_MATCH_START!")
                let logLine = LogLine(line)
                handleArenaStart(logLine)
                hasArenaData = true
            }
            else if line.contains("ARENA_PREPARATION") {
                print("BATCH: Found ARENA_PREPARATION!")
                hasArenaPreparation = true
            }
            
            // Compter les événements PVP et les joueurs
            if line.lowercased().contains("pvp") || line.contains("arena") {
                pvpRelatedLines += 1
            }
            
            // Dégâts et soins
            if line.contains("SPELL_DAMAGE") || line.contains("SPELL_HEAL") {
                damageEvents += 1
                playerCount.formUnion(extractPlayerNames(from: line))
            }
        }
        
        // Si une arène n'a pas été explicitement détectée mais qu'il y a des signes
        if !hasArenaData && !arenaInProgress && (hasArenaPreparation || (playerCount.count >= 3 && damageEvents >= 10 && pvpRelatedLines >= 2)) {
            print("BATCH: Arena detected via heuristics - \(playerCount.count) players, \(damageEvents) damage events")
            startArena(.arena2v2, "Arena (Detected)")
            hasArenaData = true
        }
        
        return hasArenaData
    }
    
    // Traiter une ligne de log
    func processLine(_ line: String) {
        // 1. Chercher les événements clés d'arène
        if line.contains("ARENA_MATCH_START") {
            let logLine = LogLine(line)
            handleArenaStart(logLine)
            return
        }
        
        if line.contains("ARENA_MATCH_END") {
            handleArenaEnd()
            return
        }
        
        // 2. Détecter l'aura de préparation
        if line.contains("ARENA_PREPARATION") {
            print("LINE: Arena preparation detected")
            handleArenaPreparation()
        }
        
        // 3. Accumuler des données de combat pour détection
        if !line.isEmpty && (line.contains("SPELL_DAMAGE") || line.contains("SPELL_HEAL")) {
            combatIntensity += 1
            playerCount.formUnion(extractPlayerNames(from: line))
            
            // Si beaucoup de combat sans détection explicite
            if !arenaInProgress && combatIntensity > 15 && playerCount.count >= 3 && arenaPreparationDetected {
                print("COMBAT: Arena detected via combat analysis - \(playerCount.count) players")
                startArena(.arena2v2, "Arena (Combat)")
            }
        }
    }
    
    // Gérer le début d'une arène via ARENA_MATCH_START
    private func handleArenaStart(_ logLine: LogLine) {
        let arenaType: GameType
        
        if let typeStr = logLine.arg(3), !typeStr.isEmpty {
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
        
        let mapID = logLine.arg(1) ?? "0"
        let arenaName = getArenaNameFromID(mapID)
        
        print("ARENA DETECTED: Start via ARENA_MATCH_START")
        startArena(arenaType, arenaName)
    }
    
    // Démarrer une arène
    private func startArena(_ type: GameType, _ mapName: String) {
        if !arenaInProgress {
            arenaInProgress = true
            lastArenaEvent = Date()
            onArenaStart?(type, mapName)
        }
    }
    
    // Gérer la fin d'une arène
    private func handleArenaEnd() {
        print("ARENA ENDED: via ARENA_MATCH_END")
        arenaInProgress = false
        lastArenaEvent = nil
        arenaPreparationDetected = false
        combatIntensity = 0
        playerCount.removeAll()
        onArenaEnd?()
    }
    
    // Gérer la détection de l'aura de préparation
    private func handleArenaPreparation() {
        arenaPreparationDetected = true
        lastArenaEvent = Date()
        
        // Si pas d'arène détectée, on suppose que c'est le début
        if !arenaInProgress {
            print("ARENA DETECTED: Start via ARENA_PREPARATION")
            startArena(.arena2v2, "Arena (Preparation)")
        }
    }
    
    // Extraire les noms des joueurs d'une ligne de log
    // Changé de private à public
    public func extractPlayerNames(from line: String) -> Set<String> {
        var names = Set<String>()
        
        let components = line.components(separatedBy: ",")
        
        for (index, component) in components.enumerated() {
            if component.contains("Player-") && index + 1 < components.count {
                if let playerName = extractNameFromComponent(components[index + 1]) {
                    names.insert(playerName)
                }
            }
        }
        
        return names
    }
    
    // Extraire le nom d'un composant entre guillemets
    private func extractNameFromComponent(_ component: String) -> String? {
        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            let startIndex = trimmed.index(after: trimmed.startIndex)
            let endIndex = trimmed.index(before: trimmed.endIndex)
            return String(trimmed[startIndex..<endIndex])
        }
        return nil
    }
    
    // Obtenir le nom de l'arène à partir de l'ID
    private func getArenaNameFromID(_ id: String) -> String {
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
            "2620": "Empyrean Domain",
            "2563": "Enigma Crucible" // 🆕 Arena ajoutée
        ]

        return arenaMap[id] ?? "Unknown Arena (ID: \(id))"
    }

    
    // Réinitialiser l'état du détecteur
    func reset() {
        arenaInProgress = false
        combatIntensity = 0
        playerCount.removeAll()
        lastArenaEvent = nil
        arenaPreparationDetected = false
    }
}
