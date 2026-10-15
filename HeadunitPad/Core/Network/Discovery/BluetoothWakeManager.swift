//
//  BluetoothWakeManager.swift
//  HeadunitPad
//
//  Bluetooth peripheral advertising and central discovery for Android Auto wireless wakeup.
//  Advertises AA standard wireless projection service UUID: 4DE17A00-52CB-11E6-BDF4-0800200C9A66
//

import Foundation
import CoreBluetooth

public final class BluetoothWakeManager: NSObject {
    public static let shared = BluetoothWakeManager()

    public static let androidAutoServiceUUID = CBUUID(string: "4DE17A00-52CB-11E6-BDF4-0800200C9A66")

    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private let queue = DispatchQueue(label: "com.headunitpad.bluetooth.wake", qos: .utility)

    public private(set) var isAdvertising = false
    public private(set) var isScanning = false

    public var onDeviceWoken: ((String) -> Void)?

    private override init() {
        super.init()
    }

    public func start() {
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: queue)
        } else if peripheralManager?.state == .poweredOn && !isAdvertising {
            startAdvertising()
        }

        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: queue)
        } else if centralManager?.state == .poweredOn && !isScanning {
            startScanning()
        }
    }

    public func stop() {
        if isAdvertising {
            peripheralManager?.stopAdvertising()
            isAdvertising = false
        }
        if isScanning {
            centralManager?.stopScan()
            isScanning = false
        }
    }

    private func startAdvertising() {
        guard let pm = peripheralManager, pm.state == .poweredOn, !isAdvertising else { return }
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [Self.androidAutoServiceUUID],
            CBAdvertisementDataLocalNameKey: "HeadunitPad"
        ]
        pm.startAdvertising(advertisementData)
        isAdvertising = true
        print("BluetoothWakeManager: Started advertising Android Auto service UUID \(Self.androidAutoServiceUUID.uuidString)")
    }

    private func startScanning() {
        guard let cm = centralManager, cm.state == .poweredOn, !isScanning else { return }
        cm.scanForPeripherals(withServices: [Self.androidAutoServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        print("BluetoothWakeManager: Started scanning for Android Auto peripherals with UUID \(Self.androidAutoServiceUUID.uuidString)")
    }
}

extension BluetoothWakeManager: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            startAdvertising()
        } else {
            isAdvertising = false
        }
    }
}

extension BluetoothWakeManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            isScanning = false
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Android Auto Device"
        print("BluetoothWakeManager: Discovered AA Bluetooth peripheral: \(name), RSSI: \(RSSI)")
        onDeviceWoken?(name)
    }
}
