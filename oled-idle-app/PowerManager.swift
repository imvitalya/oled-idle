import Foundation
import IOKit.pwr_mgt

final class PowerManager {
    private var assertions: [IOPMAssertionID] = []
    var isActive: Bool { !assertions.isEmpty }

    func setActive(_ active: Bool) throws {
        if !active { release(); return }
        guard !isActive else { return }
        for type in [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep] {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "OLED Idle - black OLED screens while work continues" as CFString, &id)
            guard result == kIOReturnSuccess else {
                release()
                throw NSError(domain: "OLEDIdle.Power", code: Int(result), userInfo: [
                    NSLocalizedDescriptionKey: "macOS rejected the keep-awake assertion (\(result))."
                ])
            }
            assertions.append(id)
        }
    }
    private func release() {
        for id in assertions { IOPMAssertionRelease(id) }
        assertions.removeAll()
    }
    deinit { release() }
}
