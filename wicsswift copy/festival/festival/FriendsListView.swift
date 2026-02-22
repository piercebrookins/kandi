import SwiftUI

struct FriendsListView: View {
    let engine: FriendsEngine

    var body: some View {
        List {
            if engine.friends.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Friends Nearby",
                        systemImage: "person.2.slash",
                        description: Text("Friends running Festival Assistant will appear here automatically via Bluetooth.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Immediate") {
                    ForEach(engine.friends.filter { $0.proximityBand == .immediate }) { friend in
                        FriendRow(friend: friend)
                    }
                }

                Section("Nearby") {
                    ForEach(engine.friends.filter { $0.proximityBand == .near }) { friend in
                        FriendRow(friend: friend)
                    }
                }

                Section("In Area") {
                    ForEach(engine.friends.filter { $0.proximityBand == .area || $0.proximityBand == .weak }) { friend in
                        FriendRow(friend: friend)
                    }
                }
            }

            Section {
                HStack(spacing: 8) {
                    Circle()
                        .fill(engine.isScanning ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(engine.isScanning ? "Scanning for friends" : "Scanner inactive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if engine.isAdvertising {
                        Label("Broadcasting", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
    }
}
