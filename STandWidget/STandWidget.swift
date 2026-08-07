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
    var body: some View {
        accessoryIcon
            .widgetLabel("S.tand 열기")
            .containerBackground(.clear, for: .widget)
            .widgetURL(URL(string: "stand://open"))
    }

    private var accessoryIcon: some View {
        ZStack {
            AccessoryWidgetBackground()

            // Lock Screen accessory widgets are rendered in vibrant mode.
            // This dedicated asset has a transparent canvas and preserves the
            // app icon's lamp/waveform as a WidgetKit-safe template glyph.
            Image("STandWidgetGlyph")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(3)
                .widgetAccentable()
                .unredacted()
        }
        .unredacted()
        .accessibilityLabel("S.tand 열기")
    }
}

struct STandLaunchWidget: Widget {
    // Keep this identifier distinct from the legacy widget so WidgetKit
    // doesn't reuse its cached placeholder in the gallery.
    let kind = "com.armsone.stand.launch.v2"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: STandWidgetProvider()) { _ in
            STandLaunchWidgetView()
        }
        .configurationDisplayName("S.tand 바로 열기")
        .description("잠금화면에서 S.tand를 바로 실행합니다.")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct STandWidgetBundle: WidgetBundle {
    var body: some Widget {
        STandLaunchWidget()
    }
}
