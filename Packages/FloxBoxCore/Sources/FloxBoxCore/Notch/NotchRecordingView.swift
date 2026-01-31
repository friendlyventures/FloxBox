import SwiftUI

private enum NotchIndicatorStyle {
    static let size: CGFloat = 20
    static let trailingPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 4
    static let spinnerTint = Color.white.opacity(0.85)
}

final class NotchRecordingState: ObservableObject {
    @Published var isRecording = false
    @Published var isExpanded = false
    @Published var isAwaitingNetwork = false
    @Published var isFormatting = false
    @Published var showNetworkSpinner = false
    @Published var layout = NotchRecordingLayout.placeholder
    var onCancel: (() -> Void)?
}

struct NotchRecordingLayout: Equatable {
    let closedWidth: CGFloat
    let openWidth: CGFloat
    let containerWidth: CGFloat
    let height: CGFloat

    var cornerRadius: CGFloat { height / 2 }

    static let placeholder = NotchRecordingLayout(
        closedWidth: 185,
        openWidth: 249,
        containerWidth: 313,
        height: 28,
    )
}

struct NotchRecordingView: View {
    @ObservedObject var state: NotchRecordingState

    var body: some View {
        let shapeWidth = state.isExpanded ? state.layout.openWidth : state.layout.closedWidth
        let topRadius = min(state.layout.height / 2, 6)
        let bottomRadius = min(state.layout.height / 2, 14)

        ZStack(alignment: .top) {
            Color.clear

            NotchShape(
                topCornerRadius: topRadius,
                bottomCornerRadius: bottomRadius,
            )
            .fill(Color.black.opacity(0.95))
            .frame(width: shapeWidth, height: state.layout.height)
            .overlay(alignment: .center) {
                if state.isRecording {
                    HStack(spacing: 8) {
                        FakeWaveformView()
                        Spacer(minLength: 8)
                        RightIcon()
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(state.isExpanded ? 1 : 0)
                    .animation(.easeInOut(duration: 0.12), value: state.isExpanded)
                }
            }
            .overlay(alignment: .trailing) {
                if state.isAwaitingNetwork, state.showNetworkSpinner {
                    NetworkIndicatorView(onCancel: { state.onCancel?() })
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, NotchIndicatorStyle.trailingPadding)
                        .padding(.vertical, NotchIndicatorStyle.verticalPadding)
                } else if state.isFormatting {
                    FormattingIndicatorView()
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, NotchIndicatorStyle.trailingPadding)
                        .padding(.vertical, NotchIndicatorStyle.verticalPadding)
                }
            }
            .animation(.interpolatingSpring(stiffness: 260, damping: 18), value: state.isExpanded)
        }
        .frame(width: state.layout.containerWidth, height: state.layout.height, alignment: .top)
    }
}

struct FakeWaveformView: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: 2) {
                ForEach(0 ..< 6, id: \.self) { index in
                    let phase = time * 2.2 + Double(index) * 0.55
                    let normalized = (sin(phase) + 1) / 2
                    let height = 4 + (normalized * 10)

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 2.5, height: height)
                }
            }
            .frame(height: 14, alignment: .center)
        }
    }
}

struct RightIcon: View {
    var body: some View {
        Image(systemName: "text.word.spacing")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12)),
            )
    }
}

private struct NetworkIndicatorView: View {
    let onCancel: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onCancel) {
            if isHovering {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NotchIndicatorStyle.spinnerTint)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(NotchIndicatorStyle.spinnerTint)
            }
        }
        .buttonStyle(.plain)
        .frame(width: NotchIndicatorStyle.size, height: NotchIndicatorStyle.size)
        .onHover { isHovering = $0 }
    }
}

private struct FormattingIndicatorView: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.small)
            .tint(NotchIndicatorStyle.spinnerTint)
            .frame(width: NotchIndicatorStyle.size, height: NotchIndicatorStyle.size)
    }
}
