import Foundation

struct AudioDetectorConfiguration: Equatable {
    var soundThresholdDB: Float
    var clapPeakThresholdDB: Float = -18
    var clapRiseDB: Float = 6
    var clapPeakRiseDB: Float = 8
    var clapRefractoryInterval: TimeInterval = 1.5
    var soundAttackDuration: TimeInterval = 0.12
}

struct AudioDetection: Equatable {
    let clapDetected: Bool
    let soundBegan: Bool
    let isAboveSoundThreshold: Bool
}

enum SleepSoundKind: String, Equatable {
    case snore
    case sleepTalk
    case movement
    case other
}

struct SleepSoundFeatures: Equatable {
    let rmsDB: Float
    let peakDB: Float
    let zeroCrossingRate: Double
    let lowFrequencyRatio: Double
    let duration: TimeInterval
}

struct SleepSoundClassification: Equatable {
    let kind: SleepSoundKind
    let confidence: Double
    let duration: TimeInterval
}

enum SleepSoundRecordingPolicy {
    static func shouldKeep(_ classification: SleepSoundClassification) -> Bool {
        switch classification.kind {
        case .snore:
            classification.confidence >= 0.58
        case .sleepTalk:
            classification.confidence >= 0.60
        case .movement, .other:
            false
        }
    }
}

enum SleepSoundWakePolicy {
    static func shouldWake(_ classification: SleepSoundClassification) -> Bool {
        classification.kind == .movement && classification.confidence >= 0.55
    }
}

struct SleepSoundClassifier {
    private let releaseDuration: TimeInterval
    private var isCollecting = false
    private var soundDuration: TimeInterval = 0
    private var silenceDuration: TimeInterval = 0
    private var weightedCrestDB: Double = 0
    private var weightedZeroCrossingRate: Double = 0
    private var weightedLowFrequencyRatio: Double = 0
    private var minimumRMSDB: Float = .infinity
    private var maximumRMSDB: Float = -.infinity

    init(releaseDuration: TimeInterval = 0.18) {
        self.releaseDuration = releaseDuration
    }

    mutating func analyze(
        features: SleepSoundFeatures,
        detection: AudioDetection
    ) -> SleepSoundClassification? {
        if detection.soundBegan, !isCollecting {
            isCollecting = true
        }
        guard isCollecting else { return nil }

        if detection.isAboveSoundThreshold {
            silenceDuration = 0
            soundDuration += features.duration
            let crestDB = Double(features.peakDB - features.rmsDB)
            weightedCrestDB += crestDB * features.duration
            weightedZeroCrossingRate += features.zeroCrossingRate * features.duration
            weightedLowFrequencyRatio += features.lowFrequencyRatio * features.duration
            minimumRMSDB = min(minimumRMSDB, features.rmsDB)
            maximumRMSDB = max(maximumRMSDB, features.rmsDB)
            return nil
        }

        silenceDuration += features.duration
        guard silenceDuration >= releaseDuration else { return nil }
        let classification = classifyCurrentSound()
        reset()
        return classification
    }

    mutating func reset() {
        isCollecting = false
        soundDuration = 0
        silenceDuration = 0
        weightedCrestDB = 0
        weightedZeroCrossingRate = 0
        weightedLowFrequencyRatio = 0
        minimumRMSDB = .infinity
        maximumRMSDB = -.infinity
    }

    private func classifyCurrentSound() -> SleepSoundClassification {
        let duration = max(soundDuration, 0.001)
        let crestDB = weightedCrestDB / duration
        let zeroCrossingRate = weightedZeroCrossingRate / duration
        let lowFrequencyRatio = weightedLowFrequencyRatio / duration

        let movementScore = min(1, max(0,
            (1.4 - duration) / 1.4 * 0.35
            + max(0, crestDB - 7) / 14 * 0.25
            + zeroCrossingRate / 0.28 * 0.2
            + max(0, 0.5 - lowFrequencyRatio) / 0.5 * 0.2
        ))
        let snoreScore = min(1, max(0,
            min(1, duration / 1.2) * 0.35
            + lowFrequencyRatio * 0.4
            + max(0, 0.2 - zeroCrossingRate) / 0.2 * 0.15
            + max(0, 14 - crestDB) / 14 * 0.1
        ))

        if duration <= 1.5, movementScore >= 0.55, movementScore > snoreScore {
            return SleepSoundClassification(kind: .movement, confidence: movementScore, duration: soundDuration)
        }
        if duration >= 0.45, lowFrequencyRatio >= 0.45, snoreScore >= 0.58 {
            return SleepSoundClassification(kind: .snore, confidence: snoreScore, duration: soundDuration)
        }

        let rmsRange = Double(maximumRMSDB - minimumRMSDB)
        let sleepTalkScore = min(1, max(0,
            min(1, max(0, (duration - 0.55) / 1.45)) * 0.35
            + min(1, max(0, 1 - abs(zeroCrossingRate - 0.11) / 0.11)) * 0.25
            + min(1, max(0, 1 - abs(lowFrequencyRatio - 0.43) / 0.32)) * 0.25
            + min(1, max(0, (18 - crestDB) / 10)) * 0.15
        ))
        let isSpeechLike = duration >= 0.70
            && duration <= 30
            && crestDB <= 18
            && (0.025...0.24).contains(zeroCrossingRate)
            && (0.18...0.72).contains(lowFrequencyRatio)
            && rmsRange >= 3.5
        if isSpeechLike, sleepTalkScore >= 0.60 {
            return SleepSoundClassification(
                kind: .sleepTalk,
                confidence: sleepTalkScore,
                duration: soundDuration
            )
        }
        return SleepSoundClassification(
            kind: .other,
            confidence: max(movementScore, snoreScore),
            duration: soundDuration
        )
    }
}

struct AudioEventDetector {
    var configuration: AudioDetectorConfiguration

    private(set) var previousRMSDB: Float = -90
    private(set) var previousPeakDB: Float = -90
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
            || peakDB - previousPeakDB >= configuration.clapPeakRiseDB
        let isSharpTransient = peakDB >= configuration.clapPeakThresholdDB
        let isOutsideRefractoryWindow = now - lastClapTime >= configuration.clapRefractoryInterval
        let clapDetected = roseQuickly && isSharpTransient && isOutsideRefractoryWindow

        if clapDetected {
            lastClapTime = now
        }
        previousRMSDB = rmsDB
        previousPeakDB = peakDB

        return AudioDetection(
            clapDetected: clapDetected,
            soundBegan: soundBegan,
            isAboveSoundThreshold: isAboveThreshold
        )
    }

    mutating func reset() {
        previousRMSDB = -90
        previousPeakDB = -90
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
