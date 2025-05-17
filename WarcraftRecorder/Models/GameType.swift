//
//  GameType.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//

import Foundation

public enum GameType: String, Codable, CaseIterable, Identifiable {
    case arena2v2 = "2v2"
    case arena3v3 = "3v3"
    case arena5v5 = "5v5"
    case skirmish = "Skirmish"
    case soloShuffle = "Solo Shuffle"
    case mythicPlus = "Mythic+"
    case raid = "Raids"
    case battleground = "Battlegrounds"
    case clip = "Clips"
    
    public var id: String { rawValue }
}
