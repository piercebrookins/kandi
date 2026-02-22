import SwiftUI

struct DecibelBar: View {
    let level: Double
    let peak: Double

    private let maxDB: Double = 120

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))

                Capsule()
                    .fill(barGradient)
                    .frame(width: max(0, geo.size.width * levelFraction))
                    .animation(.easeOut(duration: 0.15), value: level)

                Circle()
                    .fill(.primary.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .offset(x: max(0, geo.size.width * peakFraction - 3))
                    .animation(.easeOut(duration: 0.3), value: peak)
            }
        }
    }

    private var levelFraction: Double {
        min(1, max(0, level / maxDB))
    }

    private var peakFraction: Double {
        min(1, max(0, peak / maxDB))
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
