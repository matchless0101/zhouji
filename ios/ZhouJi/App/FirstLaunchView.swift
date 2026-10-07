import SwiftUI

/// A one-time paper cover over the real, already loaded today page.
struct FirstLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var arrived = false
    @State private var turned = false
    let onBegin: () -> Void
    let onFinish: () -> Void

    var body: some View {
        GeometryReader { proxy in
            cover(size: proxy.size)
                .dynamicTypeSize(.large)
                .rotation3DEffect(.degrees(turned ? -104 : 0), axis: (x: 0, y: 1, z: 0),
                                  anchor: .leading, perspective: 0.35)
                .animation(.easeInOut(duration: 0.6), value: turned)
                .opacity(turned ? 0 : 1)
                .animation(.linear(duration: 0.1).delay(0.5), value: turned)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("一粥又一周")
        .accessibilityIdentifier("launch.cover")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            onBegin()
            await play()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, arrived { onFinish() }
        }
        .onChange(of: reduceMotion) { _, enabled in if enabled { onFinish() } }
        .onChange(of: voiceOver) { _, enabled in if enabled { onFinish() } }
        .onChange(of: dynamicTypeSize) { _, size in if size.isAccessibilitySize { onFinish() } }
    }

    private func cover(size: CGSize) -> some View {
        let width = size.width
        let height = size.height
        return ZStack(alignment: .topLeading) {
            ZJTheme.pageBackground
            ZJTheme.success.opacity(0.82).frame(width: width * 0.04)
            Rectangle()
                .fill(ZJTheme.success.opacity(0.3))
                .frame(width: 1)
                .offset(x: width * 0.04 + 5)
            OpeningBookmark()
                .fill(ZJTheme.accent.opacity(0.8))
                .overlay { ZJInkGrain(count: 45).clipShape(OpeningBookmark()) }
                .frame(width: width * 0.055, height: height * 0.13)
                .offset(x: width * 0.825)

            Text("一粥又一周")
                .font(ZJTheme.handwriting(width * 0.05, relativeTo: .subheadline))
                .tracking(2)
                .foregroundStyle(ZJTheme.secondaryInk)
                .frame(width: width)
                .offset(y: height * 0.17)
                .opacity(arrived ? 1 : 0)
                .animation(.easeOut(duration: 0.43).delay(0.1), value: arrived)

            Text("把今天，\n慢慢写好。")
                .font(ZJTheme.handwriting(width * 0.108, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .lineSpacing(width * 0.015)
                .foregroundStyle(ZJTheme.ink)
                .frame(width: width)
                .offset(y: height * 0.27 + (arrived ? 0 : 3))
                .opacity(arrived ? 1 : 0)
                .animation(.easeOut(duration: 0.43).delay(0.1), value: arrived)

            Capsule()
                .fill(Color(red: 0.847, green: 0.627, blue: 0.306))
                .overlay { ZJInkGrain(count: 28).clipShape(Capsule()) }
                .frame(width: width * 0.39, height: 4)
                .scaleEffect(x: arrived ? 1 : 0, y: 1, anchor: .leading)
                .rotationEffect(.degrees(-3))
                .offset(x: width * 0.31, y: height * 0.435)
                .animation(.easeOut(duration: 0.47).delay(0.35), value: arrived)

            Image(decorative: "LiuliWriting")
                .resizable()
                .scaledToFit()
                .frame(width: width * 0.96)
                .offset(x: width * 0.02, y: height * 0.46 + (arrived ? 0 : 7))
                .opacity(arrived ? 1 : 0)
                .animation(.easeOut(duration: 0.44), value: arrived)

            Text("从一件小事开始。")
                .font(ZJTheme.handwriting(width * 0.048, relativeTo: .subheadline))
                .foregroundStyle(ZJTheme.secondaryInk)
                .frame(width: width)
                .offset(y: height * 0.76)
                .opacity(arrived ? 1 : 0)
                .animation(.easeOut(duration: 0.32).delay(0.38), value: arrived)

            Text("A LITTLE EVERYDAY,\nA BETTER WEEK.")
                .font(.system(size: 11, design: .serif))
                .tracking(2)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .foregroundStyle(ZJTheme.secondaryInk)
                .frame(width: width)
                .offset(y: height * 0.865)
        }
        .frame(width: width, height: height)
        .clipped()
        .compositingGroup()
    }

    @MainActor private func play() async {
        guard !reduceMotion, !voiceOver, !dynamicTypeSize.isAccessibilitySize else {
            onFinish()
            return
        }
        arrived = true
        do {
            try await Task.sleep(for: .seconds(1.2))
            turned = true
            try await Task.sleep(for: .seconds(0.6))
            onFinish()
        } catch {
            // Removing the cover cancels its remaining animation steps.
        }
    }
}

private struct OpeningBookmark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLines([CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY),
                           CGPoint(x: rect.midX, y: rect.height * 0.88), CGPoint(x: rect.minX, y: rect.maxY)])
            path.closeSubpath()
        }
    }
}
