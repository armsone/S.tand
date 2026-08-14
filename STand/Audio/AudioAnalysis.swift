import Foundation

struct AudioDetectorConfiguration: Equatable {
    var soundThresholdDB: Float
    var clapPeakThresholdDB: Float = -18
    var clapRiseDB: Float = 6
    var clapPeakRiseDB: Float = 8
    var clapRefractoryInterval: TimeInterval = 1.5
    var soundAttackDuration: TimeInterval = 0.06
}

struct AudioDetection: Equatable {
    let clapDetected: Bool
    let soundBegan: Bool
    let isAboveSoundThreshold: Bool
}

struct AdaptiveNoiseState: Equatable {
    let noiseFloorDB: Float?
    let effectiveSoundThresholdDB: Float
    let effectiveClapPeakThresholdDB: Float
    let calibrationProgress: Double

    var isCalibrated: Bool { calibrationProgress >= 1 }
}

enum AdaptiveSoundThresholdPolicy {
    static let calibrationDuration: TimeInterval = 60
    static let quietestThresholdDB: Float = -58
    static let loudestThresholdDB: Float = -18

    static func soundThreshold(
        noiseFloorDB: Float?,
        userThresholdDB: Float = quietestThresholdDB
    ) -> Float {
        let adaptiveThreshold: Float
        if let noiseFloorDB {
            let margin: Float = switch noiseFloorDB {
            case ..<(-50): 10
            case ..<(-35): 12
            default: 14
            }
            adaptiveThreshold = clamped(noiseFloorDB + margin)
        } else {
            adaptiveThreshold = -50
        }

        // 자동 학습은 사용자가 선택한 감도보다 더 민감하게 만들 수 없다.
        return max(adaptiveThreshold, clamped(userThresholdDB))
    }

    static func clapPeakThreshold(
        noiseFloorDB: Float?,
        userThresholdDB: Float = quietestThresholdDB,
        configuredPeakThresholdDB: Float = -18
    ) -> Float {
        let soundThreshold = soundThreshold(
            noiseFloorDB: noiseFloorDB,
            userThresholdDB: userThresholdDB
        )
        let adaptivePeak = min(-8, max(-45, soundThreshold + 12))
        return max(adaptivePeak, min(-8, max(-45, configuredPeakThresholdDB)))
    }

    private static func clamped(_ value: Float) -> Float {
        min(loudestThresholdDB, max(quietestThresholdDB, value))
    }
}

enum AudioCalibrationPolicy {
    static func canReact(_ state: AdaptiveNoiseState) -> Bool {
        state.isCalibrated
    }
}

struct AdaptiveNoiseFloorTracker {
    private static let bucketDuration: TimeInterval = 1
    private static let adaptationWindowCount = 8

    private var totalObservedDuration: TimeInterval = 0
    private var currentBucketDuration: TimeInterval = 0
    private var currentBucketSamples: [Float] = []
    private var calibrationBuckets: [Float] = []
    private var adaptationBuckets: [Float] = []
    private var noiseFloorDB: Float?

    mutating func observe(
        rmsDB: Float,
        duration: TimeInterval
    ) -> AdaptiveNoiseState {
        let safeDuration = max(0, duration)
        totalObservedDuration += safeDuration
        currentBucketDuration += safeDuration
        currentBucketSamples.append(Self.sanitized(rmsDB))

        if currentBucketDuration >= Self.bucketDuration {
            finishCurrentBucket()
        }
        return state
    }

    var state: AdaptiveNoiseState {
        AdaptiveNoiseState(
            noiseFloorDB: noiseFloorDB,
            effectiveSoundThresholdDB: AdaptiveSoundThresholdPolicy.soundThreshold(
                noiseFloorDB: noiseFloorDB
            ),
            effectiveClapPeakThresholdDB: AdaptiveSoundThresholdPolicy.clapPeakThreshold(
                noiseFloorDB: noiseFloorDB
            ),
            calibrationProgress: min(
                1,
                totalObservedDuration / AdaptiveSoundThresholdPolicy.calibrationDuration
            )
        )
    }

    mutating func reset() {
        totalObservedDuration = 0
        currentBucketDuration = 0
        currentBucketSamples.removeAll(keepingCapacity: true)
        calibrationBuckets.removeAll(keepingCapacity: true)
        adaptationBuckets.removeAll(keepingCapacity: true)
        noiseFloorDB = nil
    }

    private mutating func finishCurrentBucket() {
        guard !currentBucketSamples.isEmpty else { return }
        // 한 번의 뒤척임이나 박수로 기준이 올라가지 않도록 각 1초의 낮은 35% 지점을 사용한다.
        let bucketFloor = Self.percentile(currentBucketSamples, fraction: 0.35)
        currentBucketDuration = 0
        currentBucketSamples.removeAll(keepingCapacity: true)

        if totalObservedDuration <= AdaptiveSoundThresholdPolicy.calibrationDuration {
            calibrationBuckets.append(bucketFloor)
            noiseFloorDB = Self.percentile(calibrationBuckets, fraction: 0.5)
            return
        }

        adaptationBuckets.append(bucketFloor)
        if adaptationBuckets.count > Self.adaptationWindowCount {
            adaptationBuckets.removeFirst(adaptationBuckets.count - Self.adaptationWindowCount)
        }
        let candidate = Self.percentile(adaptationBuckets, fraction: 0.5)
        guard let current = noiseFloorDB else {
            noiseFloorDB = candidate
            return
        }
        // 지속 소음이 생기면 약 10초, 조용해지면 약 5초 안에 다시 민감해진다.
        let rate: Float = candidate > current ? 0.12 : 0.22
        noiseFloorDB = current + (candidate - current) * rate
    }

    private static func sanitized(_ value: Float) -> Float {
        guard value.isFinite else { return -90 }
        return min(0, max(-90, value))
    }

    private static func percentile(_ values: [Float], fraction: Double) -> Float {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return -90 }
        let position = min(
            sorted.count - 1,
            max(0, Int((Double(sorted.count - 1) * fraction).rounded()))
        )
        return sorted[position]
    }
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
