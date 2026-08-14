import Foundation
import VLCKit

@main
struct ConsumerSmoke {
    static func main() {
        _ = [VLCLibrary.self, VLCMedia.self, VLCMediaPlayer.self, VLCAudioEqualizer.self]
    }
}
