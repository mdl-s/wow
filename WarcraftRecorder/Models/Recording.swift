//
//  Recording.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//

import Foundation

public struct Recording: Identifiable, Codable {
    public var id: UUID
    public var type: GameType
    public var mapName: String
    public var date: Date
    public var duration: TimeInterval
    public var filePath: String
    public var result: String
    public var difficulty: Int
    public var players: [String]
    
    public init(id: UUID = UUID(), type: GameType, mapName: String, date: Date = Date(), duration: TimeInterval = 0, filePath: String = "", result: String = "", difficulty: Int = 0, players: [String] = []) {
        self.id = id
        self.type = type
        self.mapName = mapName
        self.date = date
        self.duration = duration
        self.filePath = filePath
        self.result = result
        self.difficulty = difficulty
        self.players = players
    }
}
