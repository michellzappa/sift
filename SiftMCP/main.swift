import Foundation

// sift-mcp: a stdio MCP server that lets Claude Code and Claude Desktop
// search the user's Sift library. It ships inside Sift.app at
// Contents/MacOS/sift-mcp and only reads what the app writes.
//
// Transport: newline-delimited JSON-RPC 2.0 on stdin and stdout, one message
// per line. Only protocol messages go to stdout; logs go to stderr.

let server = MCPServer(version: MCPServer.appVersion())
Log.write("sift-mcp \(server.version) ready")
while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { continue }
    if let reply = server.handle(line: trimmed) {
        Output.send(reply)
    }
}
Log.write("stdin closed, exiting")
