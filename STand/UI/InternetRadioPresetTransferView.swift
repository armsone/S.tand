import SwiftUI
import UniformTypeIdentifiers

/// The exportable/importable JSON payload for the Android-compatible radio preset file.
struct InternetRadioPresetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = fileData
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Shows the parsed channels from an imported file before any settings change,
/// letting the user add non-duplicate channels or replace the whole list.
struct InternetRadioImportPreviewSheet: View {
    let preview: InternetRadioImportPreview
    let existingCount: Int
    let maximumCount: Int
    let accent: Color
    let onAdd: () -> Void
    let onReplace: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if preview.hasInsecureStreams {
                    Section {
                        Label(
                            "http:// 주소가 포함되어 있습니다. 암호화되지 않은 스트림입니다.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Section("가져올 채널 · \(preview.entries.count)개") {
                    ForEach(preview.entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(entry.channel.displayName)
                                    .font(.subheadline.weight(.semibold))
                                if entry.channel.isInsecureStream {
                                    Image(systemName: "lock.open.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                                if entry.isDuplicate {
                                    Text("중복")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.62))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.white.opacity(0.12), in: Capsule())
                                }
                            }
                            Text(entry.channel.urlString)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle("라디오 채널 가져오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        onCancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if preview.allDuplicates {
                        Text("모두 이미 등록된 채널입니다.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                        Button("확인") {
                            onCancel()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("현재 \(existingCount)/\(maximumCount)개 채널이 있습니다.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                        Button("채널 목록 전체 바꾸기", role: .destructive) {
                            onReplace()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        Button("빈 자리에 추가") {
                            onAdd()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .frame(maxWidth: .infinity)
                        .disabled(preview.newEntries.isEmpty || existingCount >= maximumCount)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
    }
}
