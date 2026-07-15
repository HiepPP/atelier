import AppKit
import SwiftTerm

// Spike: nhúng LocalProcessTerminalView vào AppKit window, chạy $SHELL.
// Muc tieu: verify build, launch, spawn shell, resize, copy/paste, mau co ban.
// Chua tich hop vao main app.

final class TerminalWindowController {
    let window: NSWindow
    let terminal: LocalProcessTerminalView

    init() {
        let rect = NSRect(x: 0, y: 0, width: 900, height: 560)

        terminal = LocalProcessTerminalView(frame: rect)
        terminal.autoresizingMask = [.width, .height]

        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "SwiftTerm Spike"
        window.center()
        window.contentView = terminal
    }

    func start() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shell as NSString).lastPathComponent

        // Ke thua env hien tai, ep TERM de mau ANSI hoat dong.
        var env: [String] = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        env.removeAll { $0.hasPrefix("TERM=") }
        env.append("TERM=xterm-256color")

        // execName "-zsh" => login shell.
        terminal.startProcess(
            executable: shell,
            args: [],
            environment: env,
            execName: "-\(shellName)")

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: TerminalWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = TerminalWindowController()
        controller.start()
        self.controller = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// --- Self-test: verify resize + color + copy qua SwiftTerm API, khong can GUI ---
// Feed truc tiep vao Terminal model (dong bo), doc lai buffer -> bang chung that.
func runSelfTest() -> Never {
    _ = NSApplication.shared            // load AppKit, khong goi run()
    let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))
    let term = view.getTerminal()
    var pass = true
    func check(_ name: String, _ ok: Bool, _ detail: String) {
        print("[\(ok ? "PASS" : "FAIL")] \(name): \(detail)")
        if !ok { pass = false }
    }

    // 1. Mau ANSI: fg cua o mau khac defaultColor.
    term.feed(text: "\u{1b}c")                      // reset
    term.feed(text: "\u{1b}[31mR\u{1b}[0m")         // do
    let redFg = term.getCharData(col: 0, row: 0)?.attribute.fg
    term.feed(text: "\u{1b}c")
    term.feed(text: "P")                            // plain
    let plainFg = term.getCharData(col: 0, row: 0)?.attribute.fg
    check("mau ANSI",
          redFg != nil && redFg != .defaultColor && plainFg == .defaultColor,
          "red fg=\(String(describing: redFg)), plain fg=\(String(describing: plainFg))")

    // 2. Resize: doi frame -> cols/rows thay doi dong bo.
    view.setFrameSize(NSSize(width: 1400, height: 900))
    let (bigC, bigR) = (term.cols, term.rows)
    view.setFrameSize(NSSize(width: 480, height: 260))
    let (smallC, smallR) = (term.cols, term.rows)
    check("resize",
          bigC > smallC && bigR > smallR,
          "big=\(bigC)x\(bigR), small=\(smallC)x\(smallR)")

    // 3. Copy: selectAll -> getSelection -> pasteboard roundtrip.
    view.setFrameSize(NSSize(width: 900, height: 560))
    term.feed(text: "\u{1b}c")
    term.feed(text: "hello-clipboard")
    view.selectAll()
    let sel = (view.getSelection() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(sel, forType: .string)
    let readBack = pb.string(forType: .string) ?? ""
    check("copy (selection -> pasteboard)",
          sel.contains("hello-clipboard") && readBack == sel,
          "selection=\"\(sel)\"")

    print(pass ? "\nSELFTEST: ALL PASS" : "\nSELFTEST: SOME FAIL")
    exit(pass ? 0 : 1)
}

if CommandLine.arguments.contains("--selftest") {
    runSelfTest()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
