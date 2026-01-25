import SwiftUI

final class NotchRecordingState: ObservableObject {
    @Published var isRecording = false
    @Published var isExpanded = false
    @Published var layout = NotchRecordingLayout.placeholder
}

struct NotchRecordingLayout: Equatable {
    let closedWidth: CGFloat
    let openWidth: CGFloat
    let height: CGFloat

    var cornerRadius: CGFloat { height / 2 }

    static let placeholder = NotchRecordingLayout(
        closedWidth: 185,
        openWidth: 405,
        height: 28,
    )
}

struct NotchRecordingView: View {
    @ObservedObject var state: NotchRecordingState

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear

            RoundedRectangle(cornerRadius: state.layout.cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.95))
                .frame(
                    width: state.isExpanded ? state.layout.openWidth : state.layout.closedWidth,
                    height: state.layout.height,
                )
                .overlay(alignment: .trailing) {
                    if state.isRecording {
                        HStack(spacing: 6) {
                            PulsingDot()
                            Text("REC")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 12)
                        .frame(maxHeight: .infinity)
                        .opacity(state.isExpanded ? 1 : 0)
                        .animation(.easeInOut(duration: 0.12), value: state.isExpanded)
                    }
                }
                .animation(.snappy(duration: 0.22), value: state.isExpanded)
        }
        .frame(width: state.layout.openWidth, height: state.layout.height, alignment: .topTrailing)
    }
}

struct PulsingDot: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = (sin(context.date.timeIntervalSinceReferenceDate * 2.0 * .pi / 1.2) + 1) / 2
            let scale = 0.6 + (0.4 * phase)
            let opacity = 0.5 + (0.5 * phase)

            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(scale)
                .opacity(opacity)
        }
    }
}
