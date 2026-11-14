import Foundation

/// Safari's Reading List, through Safari's own scripting command.
struct ReadingListSender: Sender {
    let kind = "reading-list"
    let label = "Reading List"
    let symbol = "eyeglasses"

    func send(_ item: SendItem, to destination: Destination) async throws -> String? {
        let error = await MainActor.run {
            TabActions.addToReadingList(item.url, title: item.title, preview: item.summary)
        }
        if let error { throw SendFailure(message: error) }
        return nil
    }
}
