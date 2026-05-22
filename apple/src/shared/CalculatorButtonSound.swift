import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public enum CalculatorButtonSound {
    private enum Kind {
        case button
        case enter
    }

    private static let buttonPlayerPool = ButtonSoundPlayerPool(resourceName: "button-click")
    private static let enterPlayerPool = ButtonSoundPlayerPool(resourceName: "enter-click", fallbackResourceName: "button-click")

    public static func playClick() {
        play(kind: .button)
    }

    public static func playEnterClick() {
        play(kind: .enter)
    }

    private static func play(kind: Kind) {
        playerPool(for: kind).play(volume: playbackVolume)
    }

    private static var playbackVolume: Float {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? 0.15 : 0.105
        #else
        return 0.15
        #endif
    }

    private static func playerPool(for kind: Kind) -> ButtonSoundPlayerPool {
        switch kind {
        case .button:
            return buttonPlayerPool
        case .enter:
            return enterPlayerPool
        }
    }
}

@MainActor
private final class ButtonSoundPlayerPool {
    private let players: [AVAudioPlayer]
    private var nextIndex: Int = 0

    init(resourceName: String, fallbackResourceName: String? = nil) {
        let soundURL = Bundle.enterCalcCore.url(forResource: resourceName, withExtension: "wav")
            ?? fallbackResourceName.flatMap { Bundle.enterCalcCore.url(forResource: $0, withExtension: "wav") }

        guard let soundURL else {
            self.players = []
            return
        }

        var createdPlayers: [AVAudioPlayer] = []
        createdPlayers.reserveCapacity(4)

        for _ in 0..<4 {
            guard let player = try? AVAudioPlayer(contentsOf: soundURL) else {
                continue
            }

            player.numberOfLoops = 0
            player.prepareToPlay()
            createdPlayers.append(player)
        }

        self.players = createdPlayers
    }

    func play(volume: Float) {
        guard !players.isEmpty else { return }

        let player = players[nextIndex]
        nextIndex = (nextIndex + 1) % players.count
        player.currentTime = 0
        player.volume = max(0, min(volume, 1))
        player.play()
    }
}