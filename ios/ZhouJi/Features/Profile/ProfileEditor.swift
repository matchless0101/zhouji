import SwiftUI

// Only stable preset identifiers are sent to the server; no remote image URLs.
enum ProfileAvatar: String, CaseIterable, Identifiable {
    case sunrise, leaf, moon, ocean, flower, mountain
    var id: Self { self }

    var title: String {
        switch self {
        case .sunrise: "晨光"
        case .leaf: "新芽"
        case .moon: "月夜"
        case .ocean: "海浪"
        case .flower: "花开"
        case .mountain: "远山"
        }
    }

    var symbol: String {
        switch self {
        case .sunrise: "sun.max.fill"
        case .leaf: "leaf.fill"
        case .moon: "moon.stars.fill"
        case .ocean: "water.waves"
        case .flower: "camera.macro"
        case .mountain: "mountain.2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sunrise: .orange
        case .leaf: .green
        case .moon: .indigo
        case .ocean: .blue
        case .flower: .pink
        case .mountain: .teal
        }
    }
}

struct ProfileAvatarView: View {
    let avatar: ProfileAvatar
    var size: CGFloat = 72

    var body: some View {
        Image(systemName: avatar.symbol)
            .font(.system(size: size * 0.40, weight: .medium))
            .foregroundStyle(avatar.tint)
            .frame(width: size, height: size)
            .background {
                Circle().fill(LinearGradient(
                    colors: [avatar.tint.opacity(0.10), avatar.tint.opacity(0.24)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { Circle().stroke(avatar.tint.opacity(0.13), lineWidth: 1) }
            }
            .accessibilityHidden(true)
    }
}

struct ProfileEditor: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var avatar: ProfileAvatar
    @FocusState private var nicknameFocused: Bool
    private let accountID: String

    init(profile: AppAccount) {
        accountID = profile.id
        _nickname = State(initialValue: profile.displayName)
        _avatar = State(initialValue: ProfileAvatar(rawValue: profile.avatar ?? "") ?? .sunrise)
    }

    private var normalizedName: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    private var nameIsValid: Bool {
        (1...20).contains(normalizedName.unicodeScalars.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 12) {
                        ProfileAvatarView(avatar: avatar, size: 88)
                        Text(normalizedName.isEmpty ? "粥记用户" : normalizedName)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("昵称").font(.headline)
                        TextField("怎么称呼你", text: $nickname)
                            .textContentType(.nickname)
                            .submitLabel(.done)
                            .focused($nicknameFocused)
                            .onSubmit { nicknameFocused = false }
                            .padding(14)
                            .background(ZJTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("profile.nickname")
                        Text("1–20 个字符")
                            .font(.footnote)
                            .foregroundStyle(ZJTheme.secondaryInk)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("选择头像").font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 18) {
                            ForEach(ProfileAvatar.allCases) { option in
                                Button {
                                    nicknameFocused = false
                                    avatar = option
                                } label: {
                                    VStack(spacing: 7) {
                                        ProfileAvatarView(avatar: option, size: 64)
                                            .overlay(alignment: .bottomTrailing) {
                                                if avatar == option {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .symbolRenderingMode(.palette)
                                                        .foregroundStyle(.white, ZJTheme.accent)
                                                        .font(.title3)
                                                }
                                            }
                                        Text(option.title)
                                            .font(.caption)
                                            .foregroundStyle(ZJTheme.secondaryInk)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.title)
                                .accessibilityAddTraits(avatar == option ? .isSelected : [])
                                .accessibilityIdentifier("profile.avatar.\(option.rawValue)")
                            }
                        }
                    }
                    Text("昵称和头像保存在你的粥记账户中。")
                        .font(.footnote)
                        .foregroundStyle(ZJTheme.secondaryInk)
                    if let message = account.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(ZJTheme.secondaryInk)
                            .accessibilityIdentifier("profile.saveMessage")
                    }
                }
                .padding(24)
                .disabled(account.isBusy)
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .foregroundStyle(ZJTheme.ink)
            .navigationTitle("编辑个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(account.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        nicknameFocused = false
                        Task {
                            if await account.updateProfile(nickname: normalizedName, avatar: avatar.rawValue, accountID: accountID) {
                                dismiss()
                            }
                        }
                    } label: {
                        if account.isBusy { ProgressView() } else { Text("保存").bold() }
                    }
                    .disabled(account.isBusy || !nameIsValid)
                    .accessibilityIdentifier("profile.save")
                }
            }
            .interactiveDismissDisabled(account.isBusy)
            .onChange(of: account.account?.id) { _, id in
                if id != accountID { dismiss() }
            }
        }
    }
}
