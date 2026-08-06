import Foundation

struct AudioDetectorConfiguration: Equatable {
    var soundThresholdDB: Float
    var clapPeakThresholdDB: Float = -5
    var clapRiseDB: Float = 13
    var clapRefractoryInterval: TimeInterval = 1.5
    var soundAttackDuration: TimeInterval = 0.12
}

struct AudioDetection: Equatable {
    let clapDetected: Bool
    let soundBegan: Bool
    let isAboveSoundThreshold: Bool
}

struct AudioEventDetector {
    var configuration: AudioDetectorConfiguration

    private(set) var previousRMSDB: Float = -90
    private var loudDuration: TimeInterval = 0
    private var lastClapTime: TimeInterval = -.infinity
    private var soundIsActive = false

    init(configuration: AudioDetectorConfiguration) {
        self.configuration = configuration
    }

    mutating func analyze(
        rmsDB: Float,
        peakDB: Float,
        bufferDuration: TimeInterval,
        now: TimeInterval
    ) -> AudioDetection {
        let isAboveThreshold = rmsDB >= configuration.soundThresholdDB
        loudDuration = isAboveThreshold ? loudDuration + bufferDuration : 0

        if !isAboveThreshold {
            soundIsActive = false
        }
        let soundBegan = !soundIsActive && loudDuration >= configuration.soundAttackDuration
        if soundBegan {
            soundIsActive = true
        }

        let roseQuickly = rmsDB - previousRMSDB >= configuration.clapRiseDB
        let isSharpTransient = peakDB >= configuration.clapPeakThresholdDB
        let isOutsideRefractoryWindow = now - lastClapTime >= configuration.clapRefractoryInterval
        let clapDetected = roseQuickly && isSharpTransient && isOutsideRefractoryWindow

        if clapDetected {
            lastClapTime = now
        }
        previousRMSDB = rmsDB

        return AudioDetection(
            clapDetected: clapDetected,
            soundBegan: soundBegan,
            isAboveSoundThreshold: isAboveThreshold
        )
    }

    mutating func reset() {
        previousRMSDB = -90
        loudDuration = 0
        lastClapTime = -.infinity
        soundIsActive = false
    }
}

struct LampEnvelope: Equatable {
    let activatedAt: TimeInterval
    let holdDuration: TimeInterval
    let fadeDuration: TimeInterval
    let maximumIntensity: Double

    func intensity(at time: TimeInterval) -> Double {
        let elapsed = max(0, time - activatedAt)

        if elapsed <= holdDuration {
            return maximumIntensity
        }

        guard fadeDuration > 0 else { return 0 }
        let fadeProgress = min(1, (elapsed - holdDuration) / fadeDuration)
        let easedProgress = fadeProgress * fadeProgress * (3 - (2 * fadeProgress))
        return maximumIntensity * (1 - easedProgress)
    }

    func isFinished(at time: TimeInterval) -> Bool {
        time >= activatedAt + holdDuration + max(0, fadeDuration)
    }
}
