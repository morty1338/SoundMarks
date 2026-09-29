import SwiftUI

/// Raised card: a backing with a shadow and a light edge on top.
/// Used in the add-place sheet so it does not look like a flat form.
struct RaisedCard<Content: View>: View {
    var title: LocalizedStringKey?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        }
        .overlay {
            // A light edge on top and a dark one at the bottom give a sense of depth.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .clear, .black.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
    }
}

/// The sheet's raised primary button.
struct RaisedPrimaryButton: View {
    let title: LocalizedStringKey
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Color.accentColor.opacity(0.95), Color.accentColor],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 12, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
