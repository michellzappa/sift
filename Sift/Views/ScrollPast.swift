import Foundation

/// Scan: a row that scrolls off the top of the list counts as seen, as in
/// a feed reader's "mark as read on scroll". Rows report `appear` and
/// `disappear` with their place in the list. A row that leaves while rows
/// below it stay on screen has scrolled past. The check waits a moment, so
/// rows leaving because the whole list closes (`active` false) or because
/// the list scrolled back down do not count. Shared by the Mac and the
/// iPhone app (prototypes/ios-deck/project.yml lists this file).
@MainActor
final class ScrollPast {
    /// False while the list is off screen.
    var active = false
    private var visible: [String: Int] = [:]

    func appear(_ id: String, at index: Int) { visible[id] = index }

    func disappear(_ id: String, at index: Int, seen: @escaping @MainActor (String) -> Void) {
        visible[id] = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.active, self.visible[id] == nil,
                  let top = self.visible.values.min(), index < top else { return }
            seen(id)
        }
    }
}
