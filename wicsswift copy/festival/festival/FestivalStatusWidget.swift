import SwiftUI
import WidgetKit

struct FestivalStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct FestivalStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FestivalStatusEntry {
        FestivalStatusEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (FestivalStatusEntry) -> Void) {
        completion(FestivalStatusEntry(date: .now, snapshot: .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FestivalStatusEntry>) -> Void) {
        Task {
            let client = WidgetAPIClient()
            let snapshot = (try? await client.fetchSnapshot()) ?? .empty
            let entry = FestivalStatusEntry(date: .now, snapshot: snapshot)
            let refresh = Calendar.current.date(byAdding: .minute, value: 5, to: .now) ?? .now.addingTimeInterval(300)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }
}

struct FestivalStatusWidgetEntryView: View {
    var entry: FestivalStatusProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.pink)
                Text("Festival Status")
                    .font(.headline)
                Spacer()
            }

            if entry.snapshot.hasSafetyAlert {
                Text("🚨 Safety Alert Active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.12))
                    .clipShape(.capsule)
            }

            if !entry.snapshot.isConfigured {
                Text("Configure app URL/session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let session = entry.snapshot.selectedSession {
                Text(session.sessionId)
                    .font(.caption2.monospaced())
                    .lineLimit(1)

                HStack {
                    Label("\(session.friendCount)", systemImage: "person.2.fill")
                    Label(session.hasHearing ? "On" : "Off", systemImage: "ear.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let safety = entry.snapshot.latestSafetyMessage,
                   !safety.isEmpty {
                    Text(safety)
                        .font(.caption2)
                        .lineLimit(2)
                        .foregroundStyle(.red)
                }
            } else {
                Text("No active sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .containerBackground(.background, for: .widget)
    }
}

struct FestivalStatusWidget: Widget {
    let kind: String = "FestivalStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FestivalStatusProvider()) { entry in
            FestivalStatusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Festival Status")
        .description("Shows session, friend count, hearing status, and latest safety alert.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
