import IOKit

/// Controls the MacBook's private clamshell-sleep override.
/// Selector 12 is `kPMSetClamshellSleepState` in Apple's open-source XNU IOPMLibDefs.
enum ClamshellController {
    private static let setClamshellSleepStateSelector: UInt32 = 12

    @discardableResult
    static func setSleepDisabled(_ disabled: Bool) -> IOReturn {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else { return kIOReturnNotFound }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = IO_OBJECT_NULL
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == kIOReturnSuccess else { return openResult }
        defer { IOServiceClose(connection) }

        var input: UInt64 = disabled ? 1 : 0
        var outputCount: UInt32 = 0
        return IOConnectCallScalarMethod(
            connection,
            setClamshellSleepStateSelector,
            &input,
            1,
            nil,
            &outputCount
        )
    }
}
