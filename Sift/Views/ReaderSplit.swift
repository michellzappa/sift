import SwiftUI

/// The list and the reading pane side by side, as in Mail: a divider the
/// user drags, the pane on the content background. The minimum widths reach
/// the window, so the window cannot get narrower than sidebar + list + pane
/// (the sidebar never slides out of the window). The pane width is kept.
struct ReaderSplit<List: View, Pane: View>: View {
    let showing: Bool
    @ViewBuilder var list: () -> List
    @ViewBuilder var pane: () -> Pane
    @AppStorage("reader.width") private var width: Double = 560
    @State private var dragStart: Double?

    static var listMin: CGFloat { 300 }
    static var paneMin: CGFloat { 360 }

    var body: some View {
        HStack(spacing: 0) {
            list()
                .frame(minWidth: Self.listMin, maxWidth: .infinity)
            if showing {
                Divider()
                    .overlay {
                        Color.clear
                            .frame(width: 8)
                            .contentShape(Rectangle())
                            .onHover { inside in inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
                            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { value in
                                    let start = dragStart ?? width
                                    dragStart = start
                                    width = min(max(start - value.translation.width, Self.paneMin), 1400)
                                }
                                .onEnded { _ in dragStart = nil })
                    }
                pane()
                    .frame(minWidth: Self.paneMin, idealWidth: width, maxWidth: width)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}
