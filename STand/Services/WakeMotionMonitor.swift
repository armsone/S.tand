import CoreMotion
import Foundation

struct WakeMotionPolicy {
    static let accelerationThreshold = 0.16
    static let rotationThreshold = 1.4

    static func detectsMovement(
        accelerationMagnitude: Double,
        rotationMagnitude: Double
    ) -> Bool {
        accelerationMagnitude >= accelerationThreshold || rotationMagnitude >= rotationThreshold
    }
}

final class WakeMotionMonitor {
    var onMovement: (() -> Void)?

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.armsone.stand.wake-motion"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var lastWakeTime: TimeInterval = -.infinity

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 0.2
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let acceleration = motion.userAcceleration
            let rotation = motion.rotationRate
            let accelerationMagnitude = sqrt(
                acceleration.x * acceleration.x
                    + acceleration.y * acceleration.y
                    + acceleration.z * acceleration.z
            )
            let rotationMagnitude = sqrt(
                rotation.x * rotation.x
                    + rotation.y * rotation.y
                    + rotation.z * rotation.z
            )
            guard WakeMotionPolicy.detectsMovement(
                accelerationMagnitude: accelerationMagnitude,
                rotationMagnitude: rotationMagnitude
            ) else { return }

            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastWakeTime >= 2 else { return }
            lastWakeTime = now
            DispatchQueue.main.async { self.onMovement?() }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
