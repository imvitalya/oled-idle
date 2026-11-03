import Foundation

enum CaffeineState: Equatable {
    case active, inactive, stopped

    init?(scriptOutput: String) {
        switch scriptOutput.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": self = .active
        case "false": self = .inactive
        case "stopped": self = .stopped
        default: return nil
        }
    }
}

struct IdlePolicy {
    private(set) var isEnabled = true
    private(set) var generation = 0
    private var fired = false
    var threshold: Double
    private var restartedAt: Double?

    init(threshold: Double = 900) {
        self.threshold = threshold.isFinite && threshold > 0 ? threshold : 900
    }

    mutating func restart(at uptime: Double = ProcessInfo.processInfo.systemUptime) {
        generation += 1
        fired = false
        restartedAt = uptime
    }

    mutating func toggle() {
        isEnabled.toggle()
        generation += 1
        fired = false
    }

    func acceptsSample(generation: Int) -> Bool {
        isEnabled && self.generation == generation
    }

    mutating func shouldLaunch(caffeineActive: Bool, idleSeconds: Double, blackoutRunning: Bool,
                               targetsAvailable: Bool = true,
                               now: Double = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard idleSeconds.isFinite, idleSeconds >= 0 else { return false }
        let effectiveIdle = min(idleSeconds, restartedAt.map { max(0, now - $0) } ?? idleSeconds)
        if effectiveIdle < threshold { fired = false }
        guard isEnabled, caffeineActive, targetsAvailable, effectiveIdle >= threshold, !fired else { return false }
        fired = true
        return !blackoutRunning
    }

    mutating func launchFailed(generation: Int) {
        if self.generation == generation { fired = false }
    }
}
