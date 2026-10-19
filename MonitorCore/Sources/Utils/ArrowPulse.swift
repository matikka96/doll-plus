import Foundation

public enum ArrowPulse {
    private static let keyframes: [(time: TimeInterval, scale: Double)] = [
        (0, 0.1), (0.3, 0.3), (0.6, 0.2), (0.9, 0.3), (1.3, 0.1),
    ]
    private static let last = keyframes[keyframes.count - 1]
    public static let duration = last.time

    public static func scale(at time: TimeInterval) -> Double {
        guard let end = keyframes.firstIndex(where: { $0.time > time }) else {
            return last.scale
        }
        guard end > 0 else {
            return keyframes[0].scale
        }
        let from = keyframes[end - 1], to = keyframes[end]
        let fraction = (time - from.time) / (to.time - from.time)
        return from.scale + (to.scale - from.scale) * easeInOut(fraction)
    }

    private static func easeInOut(_ fraction: Double) -> Double {
        (1 - cos(fraction * .pi)) / 2
    }
}
