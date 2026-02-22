import CoreBluetooth
import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class FriendsEngine: NSObject {
    var friends: [FriendProximity] = []
    var fakeFriends: [FriendProximity] = []
    var isScanning: Bool = false
    var isAdvertising: Bool = false
    private(set) var isEventModeEnabled: Bool = false

    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var discoveredPeers: [String: PeerRecord] = [:]
    private var cleanupTimer: Timer?
    private var rotationTimer: Timer?

    private let serviceUUID = CBUUID(string: "FE5A1234-A5B3-93A7-E044-BC5F61D36FC0")
    private var localEphemeralID: String = UUID().uuidString.prefix(8).lowercased()
    private var displayName: String = UserDefaults.standard.string(forKey: "friendDisplayName") ?? UIDevice.current.name
    private let stableDeviceID: String = {
        let key = "friendStableDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString.prefix(12).lowercased()
        UserDefaults.standard.set(created, forKey: key)
        return created
    }()

    private static let displayNameKey = "friendDisplayName"
    private var cleanupInterval: TimeInterval = 5
    private var stalePeerSeconds: TimeInterval = 15
    private let rotationInterval: TimeInterval = 30

    private struct PeerRecord {
        var displayName: String
        var rssiHistory: [Int]
        var lastSeen: Date
    }

    private let fakeNames = [
        "Sarah", "Jason", "Mia", "Noah", "Ava", "Liam", "Zoe", "Ethan", "Kai", "Nora"
    ]

    func start(name: String? = nil) {
        if let name {
            setDisplayName(name)
        }

        rotateEphemeralID()

        centralManager = CBCentralManager(delegate: self, queue: .main)
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)

        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.cleanupStalePeers()
            }
        }

        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: rotationInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.rotateEphemeralID()
                self.refreshAdvertisingPayload()
            }
        }
    }

    func stop() {
        centralManager?.stopScan()
        peripheralManager?.stopAdvertising()
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        rotationTimer?.invalidate()
        rotationTimer = nil
        isScanning = false
        isAdvertising = false
        discoveredPeers.removeAll()
        fakeFriends.removeAll()
        friends.removeAll()
    }

    func rotateEphemeralID() {
        localEphemeralID = UUID().uuidString.prefix(8).lowercased()
    }

    func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.displayNameKey)
        refreshAdvertisingPayload()
    }

    func currentDisplayName() -> String {
        displayName
    }

    func spawnFakeFriend() {
        let name = nextFakeName()
        let rssi = [-38, -47, -55, -63, -75, -88].randomElement() ?? -60
        let band = proximityBand(for: rssi)

        let fake = FriendProximity(
            id: "fake-\(UUID().uuidString.prefix(8))",
            displayName: name,
            proximityBand: band,
            rssi: rssi,
            estimatedMeters: estimateMeters(from: rssi),
            directionHint: randomDirectionHint(),
            confidence: Double.random(in: 0.55...0.95),
            lastSeen: .now
        )

        fakeFriends.insert(fake, at: 0)
        rebuildFriendsList()
    }

    func deleteFakeFriend(id: String) {
        fakeFriends.removeAll { $0.id == id }
        rebuildFriendsList()
    }

    func clearFakeFriends() {
        fakeFriends.removeAll()
        rebuildFriendsList()
    }

    private func startScanning() {
        guard let cm = centralManager, cm.state == .poweredOn else { return }
        cm.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    private func startAdvertising() {
        guard let pm = peripheralManager, pm.state == .poweredOn else { return }
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "\(stableDeviceID)|\(localEphemeralID)|\(displayName)"
        ]
        pm.startAdvertising(advertisementData)
        isAdvertising = true
    }

    private func refreshAdvertisingPayload() {
        guard let pm = peripheralManager, pm.state == .poweredOn else { return }
        pm.stopAdvertising()
        isAdvertising = false
        startAdvertising()
    }

    private func processPeer(identifier: String, name: String, rssi: Int) {
        let parts = name.split(separator: "|")
        let peerID = parts.count > 0 ? String(parts[0]) : identifier
        let peerEphemeral = parts.count > 1 ? String(parts[1]) : ""
        let peerName = parts.count > 2 ? String(parts[2]) : (parts.count > 1 ? String(parts[1]) : "Friend")

        guard peerID != stableDeviceID else { return }
        guard peerEphemeral != localEphemeralID else { return }

        if var existing = discoveredPeers[peerID] {
            existing.rssiHistory.append(rssi)
            if existing.rssiHistory.count > 10 {
                existing.rssiHistory.removeFirst()
            }
            existing.lastSeen = .now
            existing.displayName = peerName
            discoveredPeers[peerID] = existing
        } else {
            discoveredPeers[peerID] = PeerRecord(
                displayName: peerName,
                rssiHistory: [rssi],
                lastSeen: .now
            )
        }

        rebuildFriendsList()
    }

    private func rebuildFriendsList() {
        let realFriends = discoveredPeers.map { id, record in
            let avgRSSI = record.rssiHistory.reduce(0, +) / max(1, record.rssiHistory.count)
            let band = proximityBand(for: avgRSSI)
            let confidence = confidenceForStability(record.rssiHistory)

            return FriendProximity(
                id: id,
                displayName: record.displayName,
                proximityBand: band,
                rssi: avgRSSI,
                estimatedMeters: estimateMeters(from: avgRSSI),
                directionHint: estimateDirectionHint(from: record.rssiHistory),
                confidence: confidence,
                lastSeen: record.lastSeen
            )
        }

        friends = (realFriends + fakeFriends).sorted { $0.rssi > $1.rssi }
    }

    private func proximityBand(for rssi: Int) -> ProximityBand {
        switch rssi {
        case -40...0: return .immediate
        case -60...(-41): return .near
        case -90...(-61): return .area
        default: return .weak
        }
    }

    private func confidenceForStability(_ history: [Int]) -> Double {
        guard history.count > 1 else { return 0.4 }
        let avg = Double(history.reduce(0, +)) / Double(history.count)
        let variance = history.reduce(0.0) { partial, value in
            let diff = Double(value) - avg
            return partial + diff * diff
        } / Double(history.count)

        let normalized = max(0.0, min(1.0, 1.0 - sqrt(variance) / 20.0))
        return normalized
    }

    private func cleanupStalePeers() {
        let cutoff = Date.now.addingTimeInterval(-stalePeerSeconds)
        discoveredPeers = discoveredPeers.filter { $0.value.lastSeen > cutoff }

        fakeFriends = fakeFriends.map { friend in
            let jitter = Int.random(in: -3...3)
            let nextRSSI = max(-95, min(-35, friend.rssi + jitter))
            return FriendProximity(
                id: friend.id,
                displayName: friend.displayName,
                proximityBand: proximityBand(for: nextRSSI),
                rssi: nextRSSI,
                estimatedMeters: estimateMeters(from: nextRSSI),
                directionHint: friend.directionHint,
                confidence: max(0.4, min(0.98, friend.confidence + Double.random(in: -0.05...0.05))),
                lastSeen: .now
            )
        }

        rebuildFriendsList()
    }

    func setEventMode(_ enabled: Bool) {
        isEventModeEnabled = enabled
        cleanupInterval = enabled ? 2 : 5
        stalePeerSeconds = enabled ? 10 : 15

        if isScanning || isAdvertising {
            start(name: displayName)
        }
    }

    private func estimateMeters(from rssi: Int) -> Double {
        let txPower = -59.0
        let ratio = (txPower - Double(rssi)) / 20.0
        return max(0.3, min(30.0, pow(10.0, ratio)))
    }

    private func estimateDirectionHint(from history: [Int]) -> DirectionHint {
        guard history.count >= 3 else { return .unknown }
        let tail = Array(history.suffix(3))
        guard let first = tail.first, let last = tail.last else { return .unknown }
        let delta = last - first

        if delta >= 3 { return .ahead }
        if delta <= -3 { return .behind }

        let hash = abs(tail.reduce(0, +))
        return hash.isMultiple(of: 2) ? .left : .right
    }

    private func nextFakeName() -> String {
        let used = Set(fakeFriends.map(\.displayName))
        if let available = fakeNames.first(where: { !used.contains($0) }) {
            return available
        }
        return "Friend \(fakeFriends.count + 1)"
    }

    private func randomDirectionHint() -> DirectionHint {
        [.left, .right, .ahead, .behind, .unknown].randomElement() ?? .unknown
    }
}

extension FriendsEngine: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                self.startScanning()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        let rssi = RSSI.intValue
        let identifier = peripheral.identifier.uuidString

        guard rssi > -100, rssi < 0 else { return }

        Task { @MainActor in
            self.processPeer(identifier: identifier, name: name, rssi: rssi)
        }
    }
}

extension FriendsEngine: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            if peripheral.state == .poweredOn {
                self.startAdvertising()
            }
        }
    }
}
