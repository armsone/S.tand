import SwiftUI
import WidgetKit

struct STandWidgetEntry: TimelineEntry {
    let date: Date
}

struct STandWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> STandWidgetEntry {
        STandWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (STandWidgetEntry) -> Void) {
        completion(STandWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<STandWidgetEntry>) -> Void) {
        completion(Timeline(entries: [STandWidgetEntry(date: .now)], policy: .never))
    }
}

struct STandLaunchWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
                .widgetLabel("S.tand 열기")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("S.tand")
                        .font(.headline)
                    Text("잠자리 케어 시작")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(.black, for: .widget)
        .widgetURL(URL(string: "stand://open"))
    }
}

struct STandLaunchWidget: Widget {
    let kind = "STandLaunchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: STandWidgetProvider()) { _ in
            STandLaunchWidgetView()
        }
        .configurationDisplayName("S.tand 바로 열기")
        .description("잠금화면에서 S.tand를 바로 실행합니다.")
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

@main
struct STandWidgetBundle: WidgetBundle {
    var body: some Widget {
        STandLaunchWidget()
    }
}
