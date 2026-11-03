import Foundation

@main
enum OLEDIdlePolicyTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else {
            fputs("FAIL: \(label)\n", stderr)
            exit(1)
        }
        checks += 1
        print("PASS: \(label)")
    }

    static func main() {
        var policy = IdlePolicy()
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 899, blackoutRunning: false), "not before 15 minutes")
        expect(policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: false), "at exactly 15 minutes")
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 1800, blackoutRunning: false), "no repeated launch in the same idle interval")
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 0, blackoutRunning: false), "new input rearms without launching")
        expect(policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: false), "next idle interval can launch again")

        policy = IdlePolicy()
        expect(!policy.shouldLaunch(caffeineActive: false, idleSeconds: 900, blackoutRunning: false), "empty cup never launches")
        expect(policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: false), "active cup permits launch")

        policy = IdlePolicy()
        policy.toggle()
        expect(!policy.isEnabled, "first click pauses")
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: false), "paused application never launches")
        policy.toggle()
        expect(policy.isEnabled, "second click enables")
        expect(policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: false), "reenabled application applies the idle rule")

        policy = IdlePolicy()
        let oldGeneration = policy.generation
        policy.toggle()
        expect(!policy.acceptsSample(generation: oldGeneration), "pausing rejects in-flight results")
        policy.toggle()
        expect(!policy.acceptsSample(generation: oldGeneration), "reenabling still rejects the old result")
        expect(policy.acceptsSample(generation: policy.generation), "current enabled session accepts results")

        policy = IdlePolicy()
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: .nan, blackoutRunning: false), "NaN idle is rejected")
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: .infinity, blackoutRunning: false), "infinite idle is rejected")
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: -1, blackoutRunning: false), "negative idle is rejected")
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: true), "already running Blackout is skipped")
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: false), "closing Blackout without input does not reopen it")

        policy = IdlePolicy()
        let generation = policy.generation
        expect(policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: false), "initial launch requested")
        policy.launchFailed(generation: generation)
        expect(policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: false), "failed launch can retry")
        policy.toggle()
        policy.toggle()
        expect(policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: false), "new session launches")
        policy.launchFailed(generation: generation)
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: false), "stale failure cannot rearm the new session")

        expect(CaffeineState(scriptOutput: "true\n") == .active, "active AppleScript response recognized")
        expect(CaffeineState(scriptOutput: "false\n") == .inactive, "inactive response is distinct from active")
        expect(CaffeineState(scriptOutput: "stopped\n") == .stopped, "closed Caffeine recognized")
        expect(CaffeineState(scriptOutput: "error") == nil, "unreadable state is not treated as active")
        policy = IdlePolicy(threshold: 60)
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 59, blackoutRunning: false), "custom delay does not fire early")
        expect(policy.shouldLaunch(caffeineActive: true, idleSeconds: 60, blackoutRunning: false), "custom delay applies")
        let beforeRestart = policy.generation
        policy.restart(at: 1000)
        expect(!policy.acceptsSample(generation: beforeRestart), "manual dismissal invalidates pending samples")
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 5000, blackoutRunning: false, now: 1001), "manual exit starts a fresh interval even without hardware input")
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 10, blackoutRunning: false, now: 1060), "recent input wins over elapsed time since restart")
        expect(policy.shouldLaunch(caffeineActive: true, idleSeconds: 60, blackoutRunning: false, now: 1060), "full new idle interval can black out again")
        policy = IdlePolicy(threshold: .nan)
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 1, blackoutRunning: false), "invalid threshold falls back safely")
        policy = IdlePolicy()
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 900, blackoutRunning: false, targetsAvailable: false), "disconnected target cannot trigger automatic blackout or error window")
        expect(!policy.shouldLaunch(caffeineActive: true, idleSeconds: 910, blackoutRunning: false, targetsAvailable: false), "repeated automatic sample remains passive without targets")
        expect(policy.shouldLaunch(caffeineActive: true, idleSeconds: 920, blackoutRunning: false, targetsAvailable: true), "available target can launch after unavailable samples")
        print("All \(checks) policy checks passed.")
    }
}
