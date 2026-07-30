// The job search section: whether a search is due, running, or retrying.
//
// Reads the same files the runner writes:
//   config.env   schedule and report naming
//   .last-run    epoch seconds of the last completed slot
//   .run.lock    a directory that exists only while a search is in flight
//   .attempts    "<slot-epoch> <failure-count>" while a slot is being retried
//
// The checkout is found through JOBSEARCH_DIR, then the `jobSearchDir`
// preference the installer writes, then ~/Projects/job-search. When none of them
// holds a checkout the section disappears rather than showing a broken reading —
// MacBar is then one section short, not one section wrong.
//
// Compiled two ways, from the same source — into MacBar alongside the other
// sections, or into JobSearchBar.app on its own. Both builds supply the host that
// defines BarSection; see build.sh.
//
// Everything lives inside the section type on purpose. Sections from different
// repositories are compiled into one module, so a top-level `Config` or `Status`
// here would be free to collide with a top-level type in a sibling.

import AppKit
import Foundation

final class JobSearchSection: NSObject, BarSection {
    let name = "Job search"
    let showKey = "showJobSearch"

    /// Where the installer records the checkout, since MacBar is launched by
    /// Finder rather than by the launchd agent that used to set JOBSEARCH_DIR:
    ///     defaults write local.macbar jobSearchDir /path/to/job-search
    static let dirKey = "jobSearchDir"

    private let projectDir: String?
    private var config = Config()
    private var status = Status(state: .idle, lastRun: nil, nextRun: nil, latestReport: nil)

    private var onUpdate: () -> Void = {}
    private var timer: Timer?

    var isAvailable: Bool { projectDir != nil }

    override init() {
        projectDir = Self.locate()
        super.init()
        if let dir = projectDir { config = Self.loadConfig(dir) }
    }

    /// A directory only counts when the runner is actually in it.
    private static func locate() -> String? {
        var candidates: [String] = []
        if let d = ProcessInfo.processInfo.environment["JOBSEARCH_DIR"], !d.isEmpty { candidates.append(d) }
        if let d = Defaults.string(dirKey), !d.isEmpty { candidates.append(d) }
        candidates.append("~/Projects/job-search")

        for candidate in candidates {
            let path = (candidate as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path + "/run-search.sh") { return path }
        }
        return nil
    }

    // MARK: - Config

    struct Config {
        var slots: [(weekday: Int, hour: Int, minute: Int)] = [(1, 8, 0), (4, 15, 0)]
        var reportsDir = "reports"
        var reportPrefix = "job-search"
        var maxAttempts = 3
    }

    /// config.env is KEY="value" lines; only the handful of keys used here are read.
    private static func loadConfig(_ dir: String) -> Config {
        var c = Config()
        guard let raw = try? String(contentsOfFile: dir + "/config.env", encoding: .utf8) else { return c }

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

    // MARK: - Status

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

    func activate(onUpdate: @escaping () -> Void) {
        self.onUpdate = onUpdate
        read()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.read()
        }
    }

    func refresh(force: Bool) { read() }

    private func read() {
        guard let dir = projectDir else { return }
        // config.env changes whenever setup.sh is re-run, so re-read it too.
        config = Self.loadConfig(dir)
        status = readStatus(dir)
        onUpdate()
    }

    private func readStatus(_ dir: String) -> Status {
        let fm = FileManager.default

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
            state = .retrying(attempt: parts.count > 1
                ? (Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1) : 1)
        } else if let slot = mostRecentSlot, (lastRun == nil || slot > lastRun!) {
            state = .dueNow
        }

        // Newest report. The name must match the full dated form
        // <prefix>-YYYY-MM-DD.md: a shorter variant such as <prefix>-2026-07.md
        // would otherwise sort last ('.' > '-' in ASCII) and masquerade as the
        // newest report.
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

    // MARK: - Menu bar

    func titleSegments(compact: Bool) -> [Segment] {
        switch status.state {
        case .running:
            return [.value("⌛︎ searching…")]
        case .retrying(let attempt):
            return [.value("⚠︎ retry \(attempt)/\(config.maxAttempts)", color: Palette.warning)]
        case .dueNow:
            return [.value("◎ due now")]
        case .idle:
            guard let next = status.nextRun else { return [.value("◷ —")] }
            return [.value("◷ \(Fmt.short(next))")]
        }
    }

    // MARK: - Dropdown

    func menuRows() -> [NSMenuItem] {
        var rows: [NSMenuItem] = []
        if case .retrying = status.state {
            rows.append(MenuKit.alert(headline))
        } else {
            rows.append(MenuKit.note(headline))
        }

        if let next = status.nextRun {
            rows.append(MenuKit.note("Next run:  \(Fmt.long(next))  (\(Fmt.relative(next)))"))
        }
        if let last = status.lastRun {
            rows.append(MenuKit.note("Last run:  \(Fmt.long(last))  (\(Fmt.relative(last)))"))
        } else {
            rows.append(MenuKit.note("Last run:  never"))
        }

        if let report = status.latestReport {
            let label = report.replacingOccurrences(of: config.reportPrefix + "-", with: "")
                              .replacingOccurrences(of: ".md", with: "")
            rows.append(MenuKit.action("Open latest report  (\(label))", #selector(openReport),
                                       key: "o", target: self, object: report))
        }
        rows.append(MenuKit.action("Open project folder", #selector(openFolder), key: "f", target: self))
        rows.append(MenuKit.action("Open today's log", #selector(openLog), key: "l", target: self))
        // No key equivalent: a real search costs usage allowance, so it should
        // take a deliberate click rather than a stray keystroke.
        rows.append(MenuKit.action("Run search now…", #selector(runNow), target: self))
        return rows
    }

    private var headline: String {
        switch status.state {
        case .running:              return "Search running now"
        case .retrying(let a):      return "Last run failed — attempt \(a) of \(config.maxAttempts)"
        case .dueNow:               return "A run is due; starts at the next heartbeat"
        case .idle:                 return "Idle"
        }
    }

    // MARK: - Terminal

    func snapshot(_ completion: @escaping ([String], Bool) -> Void) {
        guard projectDir != nil else {
            completion(["no job-search checkout found"], false)
            return
        }
        read()

        var lines = [headline]
        if let next = status.nextRun { lines.append("Next run:  \(Fmt.long(next))  (\(Fmt.relative(next)))") }
        lines.append(status.lastRun.map { "Last run:  \(Fmt.long($0))  (\(Fmt.relative($0)))" }
            ?? "Last run:  never")
        if let report = status.latestReport { lines.append("Latest:    \(report)") }
        completion(lines, true)
    }

    // MARK: - Actions

    @objc private func openReport(_ sender: NSMenuItem) {
        guard let dir = projectDir, let name = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: dir + "/" + config.reportsDir + "/" + name))
    }

    @objc private func openFolder() {
        guard let dir = projectDir else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    @objc private func openLog() {
        guard let dir = projectDir else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let path = dir + "/logs/search-\(f.string(from: Date())).log"
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: dir + "/logs"))
        }
    }

    @objc private func runNow() {
        guard let dir = projectDir else { return }

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
        p.arguments = [dir + "/run-search.sh", "--force"]
        try? p.run()
        read()
    }
}
