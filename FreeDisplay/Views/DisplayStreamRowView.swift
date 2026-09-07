import SwiftUI

/// "Show in Window" row for any display (physical or virtual): opens a floating
/// window on another screen streaming this display's live content.
struct DisplayStreamRowView: View {
    @ObservedObject var display: DisplayInfo
    @ObservedObject private var streamService = DisplayStreamService.shared
    @State private var isHovered = false

    private var isShowing: Bool { streamService.isShowing(display.displayID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MenuItemIcon(systemName: isShowing ? "macwindow.badge.plus" : "macwindow", color: .teal)
                Text(isShowing ? "Close Stream Window" : "Show in Window")
                    .font(.body)
                Spacer()
                if isShowing {
                    Text("Live")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.teal)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(isHovered ? 0.06 : 0))
            .onHover { isHovered = $0 }
            .contentShape(Rectangle())
            .onTapGesture {
                streamService.toggleWindow(for: display.displayID, title: display.name)
            }
            .help("Stream this display's content into a floating window on another screen (needs Screen Recording permission)")
            .accessibilityAddTraits(.isButton)

            if let err = streamService.lastError, !isShowing {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }
}
