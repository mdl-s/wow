//
//  LogLine.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 14/05/2025.
//

import Foundation

// Une classe simplifiée pour extraire les arguments des lignes de log
class LogLine {
    private var args: [String] = []
    let original: String
    let timestamp: String
    
    init(_ line: String) {
        self.original = line
        
        // Extraire le timestamp et les arguments
        let components = line.components(separatedBy: "  ")
        if components.count >= 2 {
            self.timestamp = components[0]
            
            // Extraire les arguments
            if components.count > 1 {
                let eventPart = components[1]
                args = eventPart.components(separatedBy: ",")
            }
        } else {
            self.timestamp = ""
        }
    }
    
    // Nouvelle méthode pour obtenir un objet Date à partir du timestamp
    func date() -> Date {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yyyy HH:mm:ss.SSS" // Format: 5/14/2025 11:30:00.000
        
        // Si le timestamp ne contient pas d'année, on ajoute l'année actuelle
        var fullTimestamp = timestamp
        if !fullTimestamp.contains("/2") { // Vérifie si l'année est incluse
            let currentYear = Calendar.current.component(.year, from: Date())
            let components = fullTimestamp.components(separatedBy: " ")
            if components.count >= 2 {
                fullTimestamp = "\(components[0])/\(currentYear) \(components[1])"
            } else {
                print("Unexpected timestamp format: \(fullTimestamp)")
                return Date()
            }
        }
        if let date = dateFormatter.date(from: fullTimestamp) {
            return date
        } else {
            print("Failed to parse date from: \(fullTimestamp)")
            return Date() // Retourner la date actuelle en cas d'échec
        }
    }
    
    func eventType() -> String {
        return args.isEmpty ? "" : args[0]
    }
    
    func arg(_ index: Int) -> String? {
        guard index < args.count else { return nil }
        return args[index]
    }
}
