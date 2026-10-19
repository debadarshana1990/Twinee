import SwiftUI
import AppKit

struct Sticky: Codable, Identifiable, Equatable {
    var id = UUID()
    var x: Double
    var y: Double
    var width: Double = 190
    var height: Double = 170
    var text: String = ""
    var colorIndex: Int = 0
    var customHex: Int?

    static let colors: [(name: String, fill: Color, edge: Color)] = [
        ("Light red", Color(hex: 0xFFB3B3), Color(hex: 0xF08A8A)),
        ("Light blue", Color(hex: 0xB3DBFF), Color(hex: 0x82BDF0)),
        ("Light green", Color(hex: 0xB8F0C4), Color(hex: 0x86D69A)),
    ]

    // Older notes may carry a colour that no longer exists; they fall back to one of the three.
    var fill: Color { Self.colors[colorIndex % Self.colors.count].fill }
    var edge: Color { Self.colors[colorIndex % Self.colors.count].edge }
}

struct StickyView: View {
    @Binding var sticky: Sticky
    let bounds: CGSize
    let onDelete: () -> Void
    @State private var dragStart: CGPoint?
    @State private var resizeStart: CGSize?
    @State private var showingColors = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .bold))
                Spacer()
                Button { showingColors.toggle() } label: {
                    Circle().fill(sticky.fill).overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1)).frame(width: 13, height: 13)
                }.buttonStyle(.plain).help("Change colour")
                .popover(isPresented: $showingColors, arrowEdge: .bottom) { colorPicker }
                Button(action: onDelete) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).help("Delete sticky note")
            }
            .foregroundStyle(Color.black.opacity(0.55))
            .padding(.horizontal, 8).frame(height: 24)
            .background(sticky.edge.opacity(0.55))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? CGPoint(x: sticky.x, y: sticky.y)
                        dragStart = start
                        sticky.x = min(max(0, start.x + value.translation.width), max(0, bounds.width - sticky.width))
                        sticky.y = min(max(0, start.y + value.translation.height), max(0, bounds.height - 40))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            TextEditor(text: $sticky.text)
                .font(.system(size: 13, design: .rounded)).foregroundStyle(Color.black.opacity(0.82))
                .scrollContentBackground(.hidden).padding(.horizontal, 6).padding(.vertical, 4)
        }
        .frame(width: sticky.width, height: sticky.height)
        .background(sticky.fill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.4)).padding(4).contentShape(Rectangle())
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            let start = resizeStart ?? CGSize(width: sticky.width, height: sticky.height)
                            resizeStart = start
                            sticky.width = min(max(130, start.width + value.translation.width), 520)
                            sticky.height = min(max(100, start.height + value.translation.height), 520)
                        }
                        .onEnded { _ in resizeStart = nil }
                )
        }
        .shadow(color: .black.opacity(0.25), radius: 6, x: 2, y: 4)
        .rotationEffect(.degrees(sticky.colorIndex % 2 == 0 ? -0.8 : 0.8))
        .offset(x: sticky.x, y: sticky.y)
        .environment(\.colorScheme, .light)
    }

    private var colorPicker: some View {
        HStack(spacing: 12) {
            ForEach(Array(Sticky.colors.enumerated()), id: \.offset) { index, color in
                Button { sticky.colorIndex = index; showingColors = false } label: {
                    Circle().fill(color.fill).frame(width: 26, height: 26)
                        .overlay(Circle().stroke(color.edge, lineWidth: 1.5))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: sticky.colorIndex % Sticky.colors.count == index ? 2.5 : 0).padding(-3))
                }.buttonStyle(.plain).help(color.name)
            }
        }.padding(14)
    }
}
