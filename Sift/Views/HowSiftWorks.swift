import SwiftUI
import WebKit

/// Settings > How It Works: the concept diagram
/// (docs/images/how-sift-works.svg, shipped in Resources). The same file
/// is in the README and on the website, so there is one copy to keep
/// current. It follows light and dark mode by itself.
struct HowSiftWorksPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved links and feed items come in. Sift adds their text, transcripts, summaries and themes on this Mac. You review your Library and discover in Today, in Scan, Watch or Read, then act.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DiagramView()
                .aspectRatio(1200.0 / 760.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
    }
}

private struct DiagramView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.setValue(false, forKey: "drawsBackground")
        if let url = Bundle.main.url(forResource: "how-sift-works", withExtension: "svg"),
           let svg = try? String(contentsOf: url, encoding: .utf8) {
            let html = "<html><head><meta name='color-scheme' content='light dark'><style>html,body{margin:0;background:transparent}svg{width:100%;height:auto;display:block}</style></head><body>\(svg)</body></html>"
            web.loadHTMLString(html, baseURL: nil)
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}
}
