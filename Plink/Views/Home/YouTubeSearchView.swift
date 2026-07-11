// YouTubeSearchView.swift — simple URL input (v2, no extraction API)
import SwiftUI

struct YouTubeSearchView: View {
    var onSelect: (String, String, String?) -> Void
    @State private var urlText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "magnifyingglass.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)

                Text("Paste YouTube URL")
                    .font(.headline)

                TextField("https://www.youtube.com/watch?v=...", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Add Video") {
                    let videoId = extractVideoId(from: urlText) ?? urlText
                    let title = "YouTube: \(videoId)"
                    let thumb = "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg"
                    onSelect(urlText, title, thumb)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlText.isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func extractVideoId(from url: String) -> String? {
        if url.contains("youtu.be/") {
            return url.components(separatedBy: "youtu.be/").last?.components(separatedBy: "?").first
        }
        if let components = URLComponents(string: url),
           let item = components.queryItems?.first(where: { $0.name == "v" }) {
            return item.value
        }
        if url.count == 11 { return url }
        return nil
    }
}
