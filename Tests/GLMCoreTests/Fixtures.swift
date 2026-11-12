import Foundation

/// Frames captured from a GLM 50 C on 2026-11-12 (docs/research/glm50c-ble-capture.log),
/// plus area frames published in lz1asl/CaveSurvey#150.
enum Fixtures {
    static let ack = "00 10 02 09 b8 01 00 00 00 00 00 00 00 00 00 00 00 00 ce"
    static let length1 = "c0 55 10 06 08 ba 01 b4 59 11 40 00 00 00 00 00 00 00 00 12"
    static let length2 = "c0 55 10 06 08 bb 01 09 f9 0e 40 00 00 00 00 00 00 00 00 30"
    static let continuous = "c0 55 10 0a 08 bc 01 b7 d1 e8 3f 4a 0c 82 3f b7 d1 e8 3f 8a"
    static let modeLength = "c0 55 10 f2 08 b9 01 00 00 80 3f 00 00 00 00 00 00 00 00 6a"
    static let modeContinuous = "c0 55 10 f2 08 bb 01 00 00 00 40 00 00 00 00 00 00 00 00 fe"
    static let laser = "c0 55 10 02 09 ba 01 00 00 00 00 00 00 00 00 00 00 00 00 68"
    static let wallAreaHeight = "c0 55 10 3a 09 b9 01 00 00 00 00 73 46 08 40 00 00 00 00 f8"
    static let wallArea1 = "c0 55 10 3e 09 b9 01 1b b0 97 40 0f 7a 0e 40 0f 7a 0e 40 c0"
    static let wallArea2 = "c0 55 10 3e 09 b9 01 89 32 16 41 43 ad 0b 40 a9 13 8d 40 5c"
    static let area = "c0 55 10 12 00 dc 00 95 ec b6 3f 78 0b 94 3f 24 28 9e 3f da"
    static let areaPartial = "c0 55 10 0e 01 dc 00 00 00 00 00 78 0b 94 3f 00 00 00 00 0e"
}
