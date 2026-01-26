import SwiftUI

final class NotchRecordingState: ObservableObject {
    @Published var isRecording = false
    @Published var isExpanded = false
    @Published var layout = NotchRecordingLayout.placeholder
    @Published var toastMessage: String?
    @Published var action: NotchRecordingAction?
}

struct NotchRecordingAction {
    let title: String
    let handler: () -> Void
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
                        VIndicator()
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(state.isExpanded ? 1 : 0)
                    .animation(.easeInOut(duration: 0.12), value: state.isExpanded)
                } else if state.toastMessage != nil || state.action != nil {
                    NotchToastView(message: state.toastMessage, action: state.action)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(state.isExpanded ? 1 : 0)
                        .animation(.easeInOut(duration: 0.12), value: state.isExpanded)
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

struct VIndicator: View {
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

struct NotchToastView: View {
    let message: String?
    let action: NotchRecordingAction?

    var body: some View {
        HStack(spacing: 8) {
            if let message {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }

            if let action {
                NotchActionButton(title: action.title, action: action.handler)
            }
        }
    }
}

struct NotchActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.18)),
                )
        }
        .buttonStyle(.plain)
    }
}
