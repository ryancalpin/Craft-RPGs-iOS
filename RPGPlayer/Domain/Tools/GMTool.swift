import Foundation

public enum GMTool: String, CaseIterable, Codable, Equatable, Sendable {
    case readRecord
    case searchRecords
    case patchRecord
    case requestRoll
    case updateScene
    case updateClock
    case suggestVoice
    case attachAsset

    public var name: String { rawValue }
}

public enum GMVoiceStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case warm
    case calm
    case cautious
    case commanding
    case eerie
    case playful
    case stern
}
