// Private IOKit and IOHID readers, adapted from ChargeSpeed (https://github.com/cbowns/ios-charging-monitor),
// Copyright (c) 2026 Greg Wilson, MIT License: Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
// following conditions: The above copyright notice and this permission notice shall be included in all copies or
// substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED.
//
// IOKit is private on iOS, so its functions are looked up at runtime. That's fine for a build signed for one's own
// phone and never passes App Store review. What the sandbox refuses on iOS 26 and 27 is listed in ChargeSpeed's
// CLAUDE.md; nothing here asks for it.

import Foundation
import notify

/// powerd's view of the battery and the charger.
nonisolated final class PowerD: @unchecked Sendable {
    private typealias CopyInfo = @convention(c) () -> Unmanaged<CFTypeRef>?
    private typealias CopyList = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias Describe = @convention(c) (CFTypeRef, CFTypeRef) -> Unmanaged<CFDictionary>?
    private typealias CopyAdapter = @convention(c) () -> Unmanaged<CFDictionary>?

    private let copyInfo: CopyInfo
    private let copyList: CopyList
    private let describe: Describe
    private let copyAdapter: CopyAdapter?

    init?() {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let info = dlsym(iokit, "IOPSCopyPowerSourcesInfo"),
              let list = dlsym(iokit, "IOPSCopyPowerSourcesList"),
              let describe = dlsym(iokit, "IOPSGetPowerSourceDescription")
        else { return nil }
        copyInfo = unsafeBitCast(info, to: CopyInfo.self)
        copyList = unsafeBitCast(list, to: CopyList.self)
        self.describe = unsafeBitCast(describe, to: Describe.self)
        copyAdapter = dlsym(iokit, "IOPSCopyExternalPowerAdapterDetails").map { unsafeBitCast($0, to: CopyAdapter.self) }
    }

    /// The internal battery's description: "Current Capacity", "Is Charging", "Power Source State", "Time to Full
    /// Charge", "LPM Active" and so on.
    func battery() -> [String: Any]? {
        guard let blob = copyInfo()?.takeRetainedValue(),
              let list = copyList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        return list.lazy.compactMap { self.describe(blob, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { ($0["Type"] as? String) == "InternalBattery" } ??
            list.first.flatMap { self.describe(blob, $0)?.takeUnretainedValue() as? [String: Any] }
    }

    /// The charger: "Description", "Watts", "AdapterVoltage" (mV), "Current" (mA).
    func adapter() -> [String: Any]? {
        copyAdapter?()?.takeRetainedValue() as? [String: Any]
    }
}

/// The charger, battery and temperature sensors, through IOHIDEventSystemClient. One client per process works; more
/// read NaN. Each read takes about a millisecond, so `Reader` keeps it off the main thread.
nonisolated final class Sensors: @unchecked Sendable {
    struct Service {
        let ref: CFTypeRef
        let name: String
        let usage: Int
        let event: Int64
    }

    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias FloatValue = @convention(c) (CFTypeRef, Int32) -> Double

    private let client: CFTypeRef
    private let setMatching: SetMatching
    private let copyServices: CopyServices
    private let copyProperty: CopyProperty
    private let copyEvent: CopyEvent
    private let floatValue: FloatValue
    private(set) var power: [Service] = []
    private(set) var temperatures: [Service] = []

    init?() {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        func symbol<T>(_ name: String, _: T.Type) -> T? { dlsym(iokit, name).map { unsafeBitCast($0, to: T.self) } }
        guard let create = symbol("IOHIDEventSystemClientCreate", Create.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", SetMatching.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", CopyServices.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", CopyProperty.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", CopyEvent.self),
              let floatValue = symbol("IOHIDEventGetFloatValue", FloatValue.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else { return nil }
        self.client = client
        self.setMatching = setMatching
        self.copyServices = copyServices
        self.copyProperty = copyProperty
        self.copyEvent = copyEvent
        self.floatValue = floatValue
        rescan()
    }

    /// Charger input (VQ0u, IQ0u), into the battery (IQ0B), battery voltage (VQ0l or VP0u) and the wireless coil (VQ1u).
    static let powerNames: Set<String> = ["Charger VQ0u", "Charger IQ0u", "Charger IQ0B", "Charger VQ0l", "PMU VP0u", "Charger VQ1u"]

    func rescan() {
        // Apple's power sensors: usage 2 is amps, 3 volts. Temperatures: page 0xff00, usage 5.
        power = discover(["PrimaryUsagePage": 0xff08], event: 25).filter { Self.powerNames.contains($0.name) }
        temperatures = discover(["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5], event: 15)
    }

    private func discover(_ matching: [String: Int], event: Int64) -> [Service] {
        setMatching(client, matching as CFDictionary)
        let refs = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] ?? []
        return refs.map { ref in
            Service(ref: ref,
                    name: copyProperty(ref, "Product" as CFString)?.takeRetainedValue() as? String ?? "?",
                    usage: (copyProperty(ref, "PrimaryUsage" as CFString)?.takeRetainedValue() as? NSNumber)?.intValue ?? 0,
                    event: event)
        }
    }

    func read(_ service: Service) -> Double? {
        guard let event = copyEvent(service.ref, service.event, 0, 0)?.takeRetainedValue() else { return nil }
        let value = floatValue(event, Int32(service.event << 16))
        return value.isFinite ? value : nil
    }

    /// Readings of the power sensors by name ("Charger VQ0u" and so on).
    func readPower() -> [String: Double] {
        var values: [String: Double] = [:]
        for service in power { values[service.name] = read(service) }
        return values
    }

    /// The hottest battery sensor and the hottest chip die.
    func readTemperatures() -> (battery: Double?, chip: Double?) {
        var battery: Double?, chip: Double?
        for service in temperatures {
            guard let value = read(service), value > -20, value < 120 else { continue }
            if service.name.localizedCaseInsensitiveContains("battery") {
                battery = max(battery ?? value, value)
            } else if service.name.hasPrefix("PMU tdie") || service.name.hasPrefix("SOC") {
                chip = max(chip ?? value, value)
            }
        }
        return (battery, chip)
    }
}

/// The finer thermal level behind ProcessInfo.thermalState, 0 (nominal) to 4.
nonisolated enum ThermalPressure {
    private static let token: Int32? = {
        var token: Int32 = 0
        return notify_register_check("com.apple.system.thermalpressurelevel", &token) == NOTIFY_STATUS_OK ? token : nil
    }()

    static func current() -> Int? {
        guard let token else { return nil }
        var state: UInt64 = 0
        return notify_get_state(token, &state) == NOTIFY_STATUS_OK ? Int(state) : nil
    }
}
