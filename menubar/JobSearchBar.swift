// JobSearchBar — a macOS menu bar indicator for the scheduled job search.
//
// Reads the same files the runner writes:
//   config.env   schedule and report naming
//   .last-run    epoch seconds of the last completed slot
//   .run.lock    a directory that exists only while a search is in flight
//   .attempts    "<slot-epoch> <failure-count>" while a slot is being retried
//
// The project directory comes from the JOBSEARCH_DIR environment variable, which
// the launchd plist sets. No third-party dependencies — plain AppKit, built with
// swiftc by menubar/build.sh.

import AppKit
import Foundation

let projectDir: String = {
    if let d = ProcessInfo.processInfo.environment["JOBSEARCH_DIR"], !d.isEmpty {
        return (d as NSString).expandingTildeInPath
    }
    return ("~/Projects/job-search" as NSString).expandingTildeInPath
}()

// MARK: - config

struct Config {
    var slots: [(weekday: Int, hour: Int, minute: Int)] = [(1, 8, 0), (4, 15, 0)]
    var reportsDir = "reports"
    var reportPrefix = "job-search"
    var maxAttempts = 3
}

// config.env is KEY="value" lines; only the handful of keys used here are read.
func loadConfig() -> Config {
    var c = Config()
    guard let raw = try? String(contentsOfFile: projectDir + "/config.env", encoding: .utf8) else {
        return c
    }
    var values: [String: String] = [:]
    for line in raw.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
        let key = String(t[t.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
        var value = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        values[key] = value
    }

    // Calendar weekdays are 1-based from Sunday.
    let days = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
    if let schedule = values["SCHEDULE"] {
        let parsed = schedule.split(separator: ",").compactMap {
            part -> (weekday: Int, hour: Int, minute: Int)? in
            let f = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard f.count == 2, let weekday = days[f[0].lowercased()] else { return nil }
            let hm = f[1].split(separator: ":")
            guard let h = Int(hm.first ?? ""), let m = Int(hm.count > 1 ? hm[1] : "0") else { return nil }
            return (weekday, h, m)
        }
        if !parsed.isEmpty { c.slots = parsed }
    }
    if let d = values["REPORTS_DIR"], !d.isEmpty { c.reportsDir = d }
    if let p = values["REPORT_PREFIX"], !p.isEmpty { c.reportPrefix = p }
    if let a = values["MAX_ATTEMPTS"], let n = Int(a) { c.maxAttempts = n }
    return c
}

let config = loadConfig()

// MARK: - status

enum RunState {
    case running
    case retrying(attempt: Int)
    case dueNow
    case idle
}

struct Status {
    var state: RunState
    var lastRun: Date?
    var nextRun: Date?
    var latestReport: String?
}

func readStatus() -> Status {
    let fm = FileManager.default
    let dir = projectDir

    var lastRun: Date?
    if let s = try? String(contentsOfFile: dir + "/.last-run", encoding: .utf8),
       let epoch = TimeInterval(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
        lastRun = Date(timeIntervalSince1970: epoch)
    }

    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    let now = Date()

    func occurrence(_ slot: (weekday: Int, hour: Int, minute: Int),
                    direction: Calendar.SearchDirection) -> Date? {
        var c = DateComponents()
        c.weekday = slot.weekday
        c.hour = slot.hour
        c.minute = slot.minute
        c.second = 0
        return cal.nextDate(after: now, matching: c, matchingPolicy: .nextTime, direction: direction)
    }

    let nextRun = config.slots.compactMap { occurrence($0, direction: .forward) }.min()
    let mostRecentSlot = config.slots.compactMap { occurrence($0, direction: .backward) }.max()

    var state: RunState = .idle
    if fm.fileExists(atPath: dir + "/.run.lock") {
        state = .running
    } else if let a = try? String(contentsOfFile: dir + "/.attempts", encoding: .utf8) {
        let parts = a.split(separator: " ")
        state = .retrying(attempt: parts.count > 1 ? (Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1) : 1)
    } else if let slot = mostRecentSlot, (lastRun == nil || slot > lastRun!) {
        state = .dueNow
    }

    // Newest report. The name must match the full dated form <prefix>-YYYY-MM-DD.md:
    // a shorter variant such as <prefix>-2026-07.md would otherwise sort last
    // ('.' > '-' in ASCII) and masquerade as the newest report.
    let pattern = "^\(NSRegularExpression.escapedPattern(for: config.reportPrefix))-\\d{4}-\\d{2}-\\d{2}\\.md$"
    let datedReport = try! NSRegularExpression(pattern: pattern)
    let reports = ((try? fm.contentsOfDirectory(atPath: dir + "/" + config.reportsDir)) ?? [])
        .filter { name in
            let r = NSRange(name.startIndex..., in: name)
            return datedReport.firstMatch(in: name, range: r) != nil
        }
        .sorted()

    return Status(state: state, lastRun: lastRun, nextRun: nextRun, latestReport: reports.last)
}

func shortFormat(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.dateFormat = "EEE HH:mm"
    return f.string(from: d)
}

func longFormat(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.dateFormat = "EEE d MMM, HH:mm"
    return f.string(from: d)
}

func relative(_ d: Date) -> String {
    let secs = Int(d.timeIntervalSinceNow)
    let a = abs(secs)
    let days = a / 86400, hours = (a % 86400) / 3600, mins = (a % 3600) / 60
    var s = ""
    if days > 0 { s = "\(days)d \(hours)h" }
    else if hours > 0 { s = "\(hours)h \(mins)m" }
    else { s = "\(mins)m" }
    return secs >= 0 ? "in \(s)" : "\(s) ago"
}

// MARK: - app

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc func refresh() {
        let st = readStatus()

        // --- menu bar title ---
        var title: String
        switch st.state {
        case .running:              title = "⌛︎ searching…"
        case .retrying(let a):      title = "⚠︎ retry \(a)/\(config.maxAttempts)"
        case .dueNow:               title = "◎ due now"
        case .idle:
            title = st.nextRun.map { "◷ \(shortFormat($0))" } ?? "◷ —"
        }
        if let button = statusItem.button {
            button.title = title
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }

        // --- dropdown ---
        let menu = NSMenu()

        let header: String
        switch st.state {
        case .running:          header = "Search running now"
        case .retrying(let a):  header = "Last run failed — attempt \(a) of \(config.maxAttempts)"
        case .dueNow:           header = "A run is due; starts at the next heartbeat"
        case .idle:             header = "Idle"
        }
        let h = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        h.isEnabled = false
        menu.addItem(h)
        menu.addItem(.separator())

        if let next = st.nextRun {
            menu.addItem(disabled("Next run:  \(longFormat(next))  (\(relative(next)))"))
        }
        if let last = st.lastRun {
            menu.addItem(disabled("Last run:  \(longFormat(last))  (\(relative(last)))"))
        } else {
            menu.addItem(disabled("Last run:  never"))
        }
        menu.addItem(.separator())

        if let rep = st.latestReport {
            let label = rep.replacingOccurrences(of: config.reportPrefix + "-", with: "")
                           .replacingOccurrences(of: ".md", with: "")
            let item = NSMenuItem(title: "Open latest report  (\(label))",
                                  action: #selector(openReport), keyEquivalent: "o")
            item.target = self
            item.representedObject = rep
            menu.addItem(item)
        }
        menu.addItem(action("Open project folder", #selector(openFolder), "f"))
        menu.addItem(action("Open today's log", #selector(openLog), "l"))
        menu.addItem(.separator())
        menu.addItem(action("Run search now…", #selector(runNow), "r"))
        menu.addItem(.separator())
        menu.addItem(action("Quit", #selector(quit), "q"))

        statusItem.menu = menu
    }

    func disabled(_ t: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }
    func action(_ t: String, _ s: Selector, _ k: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: s, keyEquivalent: k)
        i.target = self
        return i
    }

    @objc func openReport(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: projectDir + "/" + config.reportsDir + "/" + name))
    }
    @objc func openFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: projectDir))
    }
    @objc func openLog() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let p = projectDir + "/logs/search-\(f.string(from: Date())).log"
        if FileManager.default.fileExists(atPath: p) {
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: projectDir + "/logs"))
        }
    }

    @objc func runNow() {
        // A real search costs usage allowance, so confirm before forcing one.
        let alert = NSAlert()
        alert.messageText = "Run the job search now?"
        alert.informativeText = "This starts a full headless search immediately, outside the normal schedule. It uses your Claude usage allowance."
        alert.addButton(withTitle: "Run now")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [projectDir + "/run-search.sh", "--force"]
        try? p.run()
        refresh()
    }

    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
