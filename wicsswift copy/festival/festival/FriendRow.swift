import SwiftUI

struct FriendRow: View {
    let friend: FriendProximity

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(bandColor.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(bandColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.subheadline.weight(.medium))
                Text("\(bandLabel) • ~\(friend.estimatedMeters, specifier: "%.1f")m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(directionLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            signalBars
        }
    }

    private var bandColor: Color {
        switch friend.proximityBand {
        case .immediate: return .green
        case .near: return .blue
        case .area: return .orange
        case .weak: return .secondary
        }
    }

    private var bandLabel: String {
        switch friend.proximityBand {
        case .immediate: return "Right here"
        case .near: return "Nearby"
        case .area: return "In the area"
        case .weak: return "Weak signal"
        }
    }

    private var directionLabel: String {
        switch friend.directionHint {
        case .left: return "Rough direction: left"
        case .right: return "Rough direction: right"
        case .ahead: return "Rough direction: ahead"
        case .behind: return "Rough direction: behind"
        case .unknown: return "Rough direction: unknown"
        }
    }

    private var signalBars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < signalLevel ? bandColor : Color(.tertiarySystemFill))
                    .frame(width: 4, height: CGFloat(6 + i * 4))
            }
        }
    }

    private var signalLevel: Int {
        switch friend.proximityBand {
        case .immediate: return 4
        case .near: return 3
        case .area: return 2
        case .weak: return 1
        }
    }
}
