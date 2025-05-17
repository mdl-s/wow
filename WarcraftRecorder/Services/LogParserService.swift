//
//  LogParserService.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//

import Foundation

class LogParserService {
    enum LogEvent {
        case arenaStart(type: GameType, mapName: String)
        case arenaEnd(result: String)
        case mythicPlusStart(mapName: String, level: Int)
        case mythicPlusEnd(result: String, timeTaken: TimeInterval)
        case battlegroundStart(mapName: String)
        case battlegroundEnd(result: String)
        case raidStart(mapName: String, difficulty: Int)
        case raidEnd(result: String)
        case unknown(line: String)
    }
    
    private var logFilePath: String
    private var lastReadPosition: UInt64 = 0
    
    init(logFilePath: String) {
        self.logFilePath = logFilePath
    }
    
    // Détermine le type d'événement à partir d'une ligne de log
    func parseLogLine(_ line: String) -> LogEvent {
        // Entrée dans une arène
        if line.contains("ARENA_MATCH_START") || line.contains("Entering Arena:") {
            // Déterminer le type d'arène (2v2, 3v3, 5v5)
            let arenaType: GameType
            
            if line.contains("2v2") {
                arenaType = .arena2v2
            } else if line.contains("3v3") {
                arenaType = .arena3v3
            } else if line.contains("5v5") {
                arenaType = .arena5v5
            } else {
                // Essayer de déterminer d'après le nombre de joueurs
                if line.contains("players: 4") {
                    arenaType = .arena2v2
                } else if line.contains("players: 6") {
                    arenaType = .arena3v3
                } else if line.contains("players: 10") {
                    arenaType = .arena5v5
                } else {
                    arenaType = .arena2v2  // Par défaut
                }
            }
            
            // Déterminer le nom de l'arène
            var arenaName = "Unknown Arena"
            if line.contains("Nagrand") {
                arenaName = "Nagrand Arena"
            } else if line.contains("Blade's Edge") {
                arenaName = "Blade's Edge Arena"
            } else if line.contains("Ruins of Lordaeron") {
                arenaName = "Ruins of Lordaeron"
            } else if line.contains("Dalaran Sewers") {
                arenaName = "Dalaran Sewers"
            } else if line.contains("The Tiger's Peak") {
                arenaName = "The Tiger's Peak"
            } else if line.contains("Tol'viron Arena") {
                arenaName = "Tol'viron Arena"
            } else if line.contains("Black Rook Hold") {
                arenaName = "Black Rook Hold Arena"
            }
            
            return .arenaStart(type: arenaType, mapName: arenaName)
        }
        
        // Fin d'une arène
        else if line.contains("ARENA_MATCH_END") || line.contains("Arena match completed") {
            var result = "Unknown"
            
            if line.contains("victory") || line.contains("won") || line.contains("Victory") {
                result = "Win"
            } else if line.contains("defeat") || line.contains("lost") || line.contains("Defeat") {
                result = "Loss"
            }
            
            return .arenaEnd(result: result)
        }
        
        // Entrée dans un donjon mythique+
        else if line.contains("CHALLENGE_MODE_START") || line.contains("Mythic keystone run started") {
            var dungeonName = "Unknown Dungeon"
            var level = 0
            
            // Liste des noms de donjons
            let dungeons = [
                "Necrotic Wake",
                "Plaguefall",
                "Mists of Tirna Scithe",
                "Halls of Atonement",
                "Theater of Pain",
                "De Other Side",
                "Spires of Ascension",
                "Sanguine Depths"
            ]
            
            for dungeon in dungeons {
                if line.contains(dungeon) {
                    dungeonName = dungeon
                    break
                }
            }
            
            // Extraire le niveau du mythique+
            if let levelRange = line.range(of: #"level (\d+)"#, options: .regularExpression),
               let levelStr = line[levelRange].split(separator: " ").last,
               let extractedLevel = Int(levelStr) {
                level = extractedLevel
            } else if let levelRange = line.range(of: #"Mythic \+(\d+)"#, options: .regularExpression),
                      let levelStr = line[levelRange].split(separator: "+").last,
                      let extractedLevel = Int(levelStr) {
                level = extractedLevel
            }
            
            return .mythicPlusStart(mapName: dungeonName, level: level)
        }
        
        // Fin d'un donjon mythique+
        else if line.contains("CHALLENGE_MODE_END") || line.contains("Mythic keystone run completed") {
            var result = "Unknown"
            var timeTaken: TimeInterval = 0
            
            if line.contains("completed in time") || line.contains("keystone upgrade") {
                result = "Completed in time"
            } else if line.contains("not completed in time") {
                result = "Not in time"
            }
            
            // Extraire le temps pris
            if let timeRange = line.range(of: #"time: (\d+:\d+)"#, options: .regularExpression),
               let timeStr = line[timeRange].split(separator: " ").last {
                let components = timeStr.split(separator: ":")
                if components.count == 2,
                   let minutes = Int(components[0]),
                   let seconds = Int(components[1]) {
                    timeTaken = TimeInterval(minutes * 60 + seconds)
                }
            }
            
            return .mythicPlusEnd(result: result, timeTaken: timeTaken)
        }
        
        // Événements champs de bataille
        else if line.contains("BATTLEFIELD_MATCH_START") || line.contains("Entering Battleground:") {
            var bgName = "Unknown Battleground"
            
            // Liste des champs de bataille
            let battlegrounds = [
                "Warsong Gulch",
                "Arathi Basin",
                "Alterac Valley",
                "Eye of the Storm",
                "Strand of the Ancients",
                "Isle of Conquest",
                "Deepwind Gorge",
                "Twin Peaks"
            ]
            
            for bg in battlegrounds {
                if line.contains(bg) {
                    bgName = bg
                    break
                }
            }
            
            return .battlegroundStart(mapName: bgName)
        }
        
        // Fin de champ de bataille
        else if line.contains("BATTLEFIELD_MATCH_END") || line.contains("Battleground match complete") {
            var result = "Unknown"
            
            if line.contains("victory") || line.contains("won") {
                result = "Win"
            } else if line.contains("defeat") || line.contains("lost") {
                result = "Loss"
            }
            
            return .battlegroundEnd(result: result)
        }
        
        // Événements de raid
        else if line.contains("ENCOUNTER_START") || line.contains("Raid encounter started") {
            var raidName = "Unknown Raid"
            var difficulty = 0
            
            // Liste des raids
            let raids = [
                "Castle Nathria",
                "Sanctum of Domination",
                "Sepulcher of the First Ones",
                "Vault of the Incarnates",
                "Aberrus, the Shadowed Crucible"
            ]
            
            for raid in raids {
                if line.contains(raid) {
                    raidName = raid
                    break
                }
            }
            
            // Extraire la difficulté
            if line.contains("Normal") {
                difficulty = 0
            } else if line.contains("Heroic") {
                difficulty = 1
            } else if line.contains("Mythic") {
                difficulty = 2
            }
            
            return .raidStart(mapName: raidName, difficulty: difficulty)
        }
        
        // Fin de raid
        else if line.contains("ENCOUNTER_END") || line.contains("Raid encounter complete") {
            var result = "Unknown"
            
            if line.contains("success") || line.contains("kill") {
                result = "Success"
            } else if line.contains("wipe") || line.contains("failure") {
                result = "Wipe"
            }
            
            return .raidEnd(result: result)
        }
        
        // Événement inconnu
        else {
            return .unknown(line: line)
        }
    }
    
    // Lire les nouvelles lignes de log depuis la dernière lecture
    func readNewLogLines() -> [String] {
        guard FileManager.default.fileExists(atPath: logFilePath) else {
            return []
        }
        
        do {
            // Ouvrir le fichier
            let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: logFilePath))
            defer { fileHandle.closeFile() }
            
            // Obtenir la taille du fichier
            let fileSize = try FileManager.default.attributesOfItem(atPath: logFilePath)[.size] as? UInt64 ?? 0
            
            // Si aucune nouvelle donnée n'est disponible
            if lastReadPosition >= fileSize {
                return []
            }
            
            // Lire à partir de la dernière position
            fileHandle.seek(toFileOffset: lastReadPosition)
            let newData = fileHandle.readDataToEndOfFile()
            
            // Mettre à jour la dernière position
            lastReadPosition = fileSize
            
            // Convertir en texte et séparer par lignes
            if let text = String(data: newData, encoding: .utf8) {
                return text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            }
        } catch {
            print("Error reading log file: \(error.localizedDescription)")
        }
        
        return []
    }
    
    // Analyser les nouvelles lignes de log et détecter les événements
    func detectEvents() -> [LogEvent] {
        let newLines = readNewLogLines()
        return newLines.map { parseLogLine($0) }.filter {
            if case .unknown = $0 {
                return false
            }
            return true
        }
    }
}
