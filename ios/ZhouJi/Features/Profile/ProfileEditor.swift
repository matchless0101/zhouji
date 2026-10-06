import SwiftUI

// Only stable preset identifiers are sent to the server; no remote image URLs.
enum ProfileAvatar: String, CaseIterable, Identifiable {
    // Keep the existing default identifier so saved profiles and the API stay compatible.
    case liuli = "sunrise"
    case leaf, moon, ocean, flower, mountain
    var id: Self { self }

    var title: String {
        switch self {
        case .liuli: "榴榴"
        case .leaf: "新芽"
        case .moon: "月夜"
        case .ocean: "海浪"
        case .flower: "花开"
        case .mountain: "远山"
        }
    }

    var assetName: String {
        switch self {
        case .liuli: "LiuliHeart"
        case .leaf: "AvatarLeaf"
        case .moon: "AvatarMoon"
        case .ocean: "AvatarOcean"
        case .flower: "AvatarFlower"
        case .mountain: "AvatarMountain"
        }
    }

}

struct ProfileAvatarView: View {
    let avatar: ProfileAvatar
    var size: CGFloat = 72

    var body: some View {
        Image(decorative: avatar.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

}

struct ProfileEditor: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var nickname: String
    @State private var avatar: ProfileAvatar
    @FocusState private var nicknameFocused: Bool
    private let accountID: String

    init(profile: AppAccount) {
        accountID = profile.id
        _nickname = State(initialValue: profile.displayName)
        _avatar = State(initialValue: ProfileAvatar(rawValue: profile.avatar ?? "") ?? .liuli)
    }

    private var normalizedName: String {
        ProfileNickname.normalize(nickname)
    }

    private var nameIsValid: Bool {
        ProfileNickname.isValid(normalizedName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ZJPaperHeader(title: "个人资料", identifier: "profile.editorHeading")
                    VStack(spacing: 8) {
                        ProfileAvatarView(avatar: avatar, size: dynamicTypeSize.isAccessibilitySize ? 72 : 100)
                        Text(normalizedName.isEmpty ? "粥记用户" : normalizedName)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("昵称")
                            .font(ZJTheme.handwriting(22, relativeTo: .headline).weight(.bold))
                        TextField("怎么称呼你", text: $nickname)
                            .font(.body)
                            .textContentType(.nickname)
                            .submitLabel(.done)
                            .focused($nicknameFocused)
                            .onSubmit { nicknameFocused = false }
                            .padding(16)
                            .frame(minHeight: 48)
                            .zjPaperCard()
                            .accessibilityLabel("昵称")
                            .accessibilityIdentifier("profile.nickname")
                        Text("1–20 个字符")
                            .font(ZJTheme.handwriting(14, relativeTo: .footnote))
                            .foregroundStyle(ZJTheme.secondaryInk)
                        if !nameIsValid {
                            Text(AccountError.invalidProfile.localizedDescription)
                                .font(.footnote)
                                .foregroundStyle(ZJTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("profile.nicknameValidation")
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("选择头像")
                            .font(ZJTheme.handwriting(22, relativeTo: .headline).weight(.bold))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 2 : 3), spacing: 10) {
                            ForEach(ProfileAvatar.allCases) { option in
                                Button {
                                    nicknameFocused = false
                                    avatar = option
                                } label: {
                                    VStack(spacing: 4) {
                                        ProfileAvatarView(avatar: option, size: 72)
                                        Text(option.title)
                                            .font(ZJTheme.handwriting(17, relativeTo: .caption))
                                            .foregroundStyle(ZJTheme.secondaryInk)
                                    }
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .zjPaperCard()
                                    .overlay {
                                        if avatar == option {
                                            RoundedRectangle(cornerRadius: ZJTheme.cornerRadius)
                                                .stroke(ZJTheme.success, lineWidth: 1.5)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        if avatar == option {
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(ZJTheme.onAccent, ZJTheme.success)
                                                .font(.system(size: 20))
                                                .padding(6)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .contentShape(RoundedRectangle(cornerRadius: ZJTheme.cornerRadius))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.title)
                                .accessibilityAddTraits(avatar == option ? .isSelected : [])
                                .accessibilityIdentifier("profile.avatar.\(option.rawValue)")
                            }
                        }
                    }
                    Text("昵称和头像保存在你的粥记账户中。")
                        .font(ZJTheme.handwriting(14, relativeTo: .footnote))
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = account.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(ZJTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("profile.saveMessage")
                    }
                }
                .padding(.horizontal, ZJTheme.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 18)
                .disabled(account.isBusy)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                ZJBackButton(label: "取消", action: dismiss.callAsFunction)
                    .disabled(account.isBusy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ZJTheme.pagePadding - 6)
                    .padding(.top, 6)
                    .background(ZJTheme.pageBackground)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: saveProfile) {
                    HStack(spacing: 12) {
                        Text("保存")
                        if account.isBusy { ProgressView().tint(ZJTheme.onAccent) }
                    }
                }
                .buttonStyle(ZJPrintedButtonStyle())
                .disabled(account.isBusy || !nameIsValid)
                .accessibilityIdentifier("profile.save")
                .padding(.horizontal, ZJTheme.pagePadding)
                .padding(.vertical, 10)
                .background(ZJTheme.pageBackground)
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .foregroundStyle(ZJTheme.ink)
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(account.isBusy)
            .onChange(of: account.account?.id) { _, id in
                if id != accountID { dismiss() }
            }
        }
    }

    private func saveProfile() {
        nicknameFocused = false
        Task {
            if await account.updateProfile(nickname: normalizedName, avatar: avatar.rawValue, accountID: accountID) {
                dismiss()
            }
        }
    }
}
