import Foundation
import VLCKit

@main
struct ConsumerSmoke {
    static func main() {
        _ = [VLCLibrary.self, VLCMedia.self, VLCMediaPlayer.self, VLCAudioEqualizer.self]
    }

    static func verifyAudioPlaybackAPI(_ player: VLCMediaPlayer) {
        player.rate = 1
        player.audio?.volume = 100
        player.audio?.isMuted = false
    }
}
