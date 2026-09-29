import SwiftUI

/// Profile editing in settings. The code does not change.
struct ProfileEditView: View {
    @Environment(AppEnvironment.self) private var environment

    let profile: Profile

    @State private var nickname = ""
    @State private var colorHex = ""
    @State private var avatarData: Data?
    @State private var isLoaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                ProfileEditorFields(nickname: $nickname, colorHex: $colorHex, avatarData: $avatarData)

                VStack(spacing: DS.Spacing.xs) {
                    Text("friends.myCode", comment: "Label: my code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(profile.uniqueCode ?? "")
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                    Text("profile.code.footer", comment: "The code does not change")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(DS.Spacing.l)
        }
        .navigationTitle(Text("profile.title", comment: "Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !isLoaded else { return }
            nickname = profile.nickname ?? ""
            colorHex = profile.avatarColorHex ?? AvatarPalette.random()
            avatarData = profile.avatarData
            isLoaded = true
        }
        // Saved right away, without a "Done" button: an empty nickname is not written.
        .onChange(of: nickname) { _, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isLoaded, !trimmed.isEmpty else { return }
            try? environment.profiles.updateMe(nickname: trimmed)
        }
        .onChange(of: colorHex) { _, value in
            guard isLoaded else { return }
            try? environment.profiles.updateMe(avatarColorHex: value)
        }
        .onChange(of: avatarData) { _, value in
            guard isLoaded else { return }
            try? environment.profiles.updateMe(avatarData: .some(value))
        }
    }
}
