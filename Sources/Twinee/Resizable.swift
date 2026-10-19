import SwiftUI
import AppKit

// A 1pt divider with a wider invisible grab area; dragging it resizes the pane on its leading side.
struct ResizeDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let palette: Palette
    var invert = false
    @State private var startWidth: Double?
    @State private var cursorPushed = false

    var body: some View {
        ZStack {
            Rectangle().fill(palette.border).frame(width: 1)
            Color.clear.frame(width: 9).contentShape(Rectangle())
        }
        .frame(width: 9)
        .padding(.horizontal, -4)
        .onHover { inside in
            if inside && !cursorPushed { NSCursor.resizeLeftRight.push(); cursorPushed = true }
            else if !inside && cursorPushed && startWidth == nil { NSCursor.pop(); cursorPushed = false }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let base = startWidth ?? width
                    startWidth = base
                    width = min(max(base + (invert ? -value.translation.width : value.translation.width), range.lowerBound), range.upperBound)
                }
                .onEnded { _ in startWidth = nil }
        )
        .onDisappear { if cursorPushed { NSCursor.pop(); cursorPushed = false } }
        .zIndex(1)
    }
}
