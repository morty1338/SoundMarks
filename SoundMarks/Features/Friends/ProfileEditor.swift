import PhotosUI
import SwiftUI

/// Profile fields: avatar (photo or initials with a color) and nickname.
/// Used when creating a profile and in settings.
struct ProfileEditorFields: View {
    @Binding var nickname: String
    @Binding var colorHex: String
    @Binding var avatarData: Data?

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                AvatarView(nickname: nickname, colorHex: colorHex, imageData: avatarData, size: 96)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(DS.Colors.accent, in: Circle())
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("profile.avatar.pick", comment: "Choose avatar photo"))

            if avatarData != nil {
                Button(role: .destructive) {
                    avatarData = nil
                } label: {
                    Text("profile.avatar.remove", comment: "Remove avatar photo")
                        .font(.footnote)
                }
            } else {
                HStack(spacing: DS.Spacing.s) {
                    ForEach(AvatarPalette.hexes, id: \.self) { hex in
                        Button {
                            Haptics.select()
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(AvatarPalette.color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if hex == colorHex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 36, height: DS.Size.tapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("profile.color", comment: "Avatar color"))
                        .accessibilityAddTraits(hex == colorHex ? .isSelected : [])
                    }
                }
            }

            TextField(text: $nickname) {
                Text("profile.nickname.placeholder", comment: "Nickname field hint")
            }
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
            .padding(.horizontal, DS.Spacing.m)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.small))
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    avatarData = AvatarPalette.avatarJPEG(from: data)
                }
                pickerItem = nil
            }
        }
    }
}

/// First opening of the friends screen: create a profile.
struct ProfileSetupView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var nickname = ""
    @State private var colorHex = AvatarPalette.random()
    @State private var avatarData: Data?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                VStack(spacing: DS.Spacing.s) {
                    Text("profile.setup.title", comment: "Profile creation title")
                        .font(.title2.weight(.bold))
                    Text("profile.setup.message", comment: "Explanation: the profile lives only on the phone")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                ProfileEditorFields(nickname: $nickname, colorHex: $colorHex, avatarData: $avatarData)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(DS.Colors.accent)
                }

                Button(action: create) {
                    Text("profile.setup.create", comment: "Create profile")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(trimmedNickname.isEmpty)
            }
            .padding(DS.Spacing.l)
        }
    }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        do {
            try environment.profiles.createMe(nickname: trimmedNickname, avatarColorHex: colorHex,
                                              avatarData: avatarData)
            Haptics.success()
            environment.nearby.start()
        } catch let error as AppError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
