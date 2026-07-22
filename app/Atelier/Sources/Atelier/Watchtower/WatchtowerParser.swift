import Foundation

// Pure Swift port of the Watchtower extension parser (src/parser.ts).
// Read-only: parses `watchtower/NEXT.md`, task spec files, and the archive.
// Never writes plan files. NSRegularExpression is documented as immutable and
// thread safe, so the cached instances are declared `nonisolated(unsafe)`.

nonisolated enum WatchtowerParser {

    // MARK: - Cached patterns

    // Spec cell may be a Markdown link: `[label](path)`. Capture the path.
    private static let linkRegex =
        try? NSRegularExpression(pattern: "\\]\\(([^)]+)\\)")

    // Task/spec id, e.g. TASK-001. Legacy TODO-NNN is still accepted.
    private static let taskIdRegex =
        try? NSRegularExpression(pattern: "^((?:TASK|TODO)-\\d+)")

    // Tracker TASK cell: leading id then the rest as the title.
    private static let taskCellRegex =
        try? NSRegularExpression(pattern: "^((?:TASK|TODO)-\\d+)\\s*(.*)$")

    // Single-word `## Heading` line used for task spec sections.
    private static let headingRegex =
        try? NSRegularExpression(pattern: "^##\\s+(\\w+)\\s*$")

    // `Status:` line inside an Outcome section.
    private static let statusLineRegex =
        try? NSRegularExpression(pattern: "^Status:\\s*(.+)$", options: [.caseInsensitive])

    private static let sectionNames: Set<String> = ["Brief", "Verify", "Outcome"]

    // MARK: - Public API

    static func parsePlanContent(_ content: String, manifestPath: String) -> WatchtowerPlan {
        let block = headerBlock(content)
        let baseDir = (manifestPath as NSString).deletingLastPathComponent
        let dir = tasksDir(for: baseDir)
        let tasks = parseTracker(content, tasksDir: dir)
        let doneCount = tasks.filter { $0.status == .done }.count

        return WatchtowerPlan(
            title: field(block, "Title"),
            slug: field(block, "Slug"),
            status: WatchtowerPlanStatus(label: field(block, "Status")),
            updated: field(block, "Updated"),
            manifestPath: manifestPath,
            tasks: tasks,
            doneCount: doneCount,
            totalCount: tasks.count
        )
    }

    static func parseTaskFile(_ content: String) -> (sections: [WatchtowerSection], outcomeStatus: WatchtowerTaskStatus?) {
        let allLines = splitLines(content)
        var sections: [WatchtowerSection] = []
        var outcomeLine = -1

        for (i, line) in allLines.enumerated() {
            if let name = firstGroup(headingRegex, line), sectionNames.contains(name) {
                sections.append(WatchtowerSection(name: name, line: i))
                if name == "Outcome" { outcomeLine = i }
            }
        }

        var outcomeStatus: WatchtowerTaskStatus? = nil
        if outcomeLine != -1 {
            var i = outcomeLine + 1
            while i < allLines.count {
                if allLines[i].hasPrefix("## ") { break }
                if let raw = firstGroup(statusLineRegex, allLines[i]) {
                    let parsed = WatchtowerTaskStatus(label: raw)
                    outcomeStatus = parsed == .unknown ? nil : parsed
                    break
                }
                i += 1
            }
        }

        return (sections, outcomeStatus)
    }

    static func readPlan(at manifestPath: String) -> WatchtowerPlan? {
        guard let content = readFileSafe(manifestPath) else { return nil }
        return parsePlanContent(content, manifestPath: manifestPath)
    }

    static func readPlan(rootDir: String) -> WatchtowerPlan? {
        readPlan(at: join(rootDir, "watchtower", "NEXT.md"))
    }

    static func readTaskFile(_ specPath: String) -> (sections: [WatchtowerSection], outcomeStatus: WatchtowerTaskStatus?) {
        guard let content = readFileSafe(specPath) else { return ([], nil) }
        return parseTaskFile(content)
    }

    static func listArchive(rootDir: String) -> [WatchtowerArchivePlan] {
        let fm = FileManager.default
        let archiveDir = join(rootDir, "watchtower", "archive")
        guard let entries = try? fm.contentsOfDirectory(atPath: archiveDir) else { return [] }

        var plans: [WatchtowerArchivePlan] = []
        for name in entries {
            let dir = (archiveDir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
            let manifest = (dir as NSString).appendingPathComponent("NEXT.md")
            if fm.fileExists(atPath: manifest) {
                plans.append(WatchtowerArchivePlan(slug: name, manifestPath: manifest))
            }
        }
        return plans.sorted { $0.slug > $1.slug }
    }

    // MARK: - Header + tracker slicing

    private static func headerBlock(_ content: String) -> String {
        guard let start = content.range(of: "## Current Active Plan") else { return "" }
        let rest = content[start.upperBound...]
        if let next = rest.range(of: "\n## ") {
            return String(rest[..<next.lowerBound])
        }
        return String(rest)
    }

    private static func trackerBlock(_ content: String) -> String {
        guard let start = content.range(of: "## Tracker") else { return content }
        let rest = content[start.lowerBound...]
        // Skip the "## Tracker" heading itself before finding the next section.
        let afterFirst = rest.index(after: rest.startIndex)
        if let next = rest.range(of: "\n## ", range: afterFirst..<rest.endIndex) {
            return String(rest[..<next.lowerBound])
        }
        return String(rest)
    }

    private static func field(_ block: String, _ name: String) -> String {
        let pattern = "^\\s*-?\\s*\(name):\\s*(.+)$"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .caseInsensitive]) else {
            return ""
        }
        return firstGroup(re, block)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Tracker rows

    private static func parseTracker(_ content: String, tasksDir dir: String) -> [WatchtowerTask] {
        let lines = splitLines(trackerBlock(content))
        guard let headerIdx = lines.firstIndex(where: { line in
            guard line.contains("|") else { return false }
            let cells = splitRow(line).map { $0.lowercased() }
            let hasItem = cells.contains("task") || cells.contains("todo")
            return cells.contains("order") && hasItem && cells.contains("status")
        }) else {
            return []
        }

        var tasks: [WatchtowerTask] = []
        var i = lines.index(after: headerIdx)
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("|") {
                if trimmed.isEmpty { i += 1; continue }
                break
            }
            let cells = splitRow(line)
            if isSeparatorRow(cells) { i += 1; continue }

            // Positional columns per the Watchtower tracker schema:
            // [0]=Order [1]=TASK [2]=Group [3]=Status [4]=Spec [5]=Deps [6]=Context(unused) [7]=Notes
            let orderCell = cell(cells, 0)
            let taskCell = cell(cells, 1)
            let groupCell = cell(cells, 2)
            let statusCell = cell(cells, 3)
            let specCell = cell(cells, 4)
            let depsCell = cell(cells, 5)
            let notesCell = cell(cells, 7)

            let order = Int(orderCell)
            let specPath = resolveSpec(dir, specCell)
            let fallbackOrder = order ?? (tasks.count + 1)
            let fallbackId = "TASK-\(String(format: "%03d", fallbackOrder))"

            let id: String
            let title: String
            if let match = firstTwoGroups(taskCellRegex, taskCell) {
                id = match.0
                title = match.1.trimmingCharacters(in: .whitespaces)
            } else {
                let fromSpec = taskId(fromSpec: specPath)
                id = fromSpec.isEmpty ? fallbackId : fromSpec
                title = taskCell
            }

            tasks.append(WatchtowerTask(
                order: fallbackOrder,
                id: id,
                title: title,
                group: groupCell,
                status: WatchtowerTaskStatus(label: statusCell),
                specPath: specPath,
                outcomePath: resolveOutcome(dir, taskId: id, specPath: specPath),
                deps: depsCell,
                notes: notesCell
            ))
            i += 1
        }
        return tasks
    }

    // MARK: - Spec + outcome resolution

    private static func tasksDir(for baseDir: String) -> String {
        let fm = FileManager.default
        let tasks = (baseDir as NSString).appendingPathComponent("tasks")
        if fm.fileExists(atPath: tasks) { return tasks }
        let legacy = (baseDir as NSString).appendingPathComponent("todos")
        if fm.fileExists(atPath: legacy) { return legacy }
        return tasks
    }

    private static func resolveSpec(_ tasksDir: String, _ cell: String) -> String? {
        if cell.isEmpty || cell == "-" { return nil }
        var raw = firstGroup(linkRegex, cell) ?? cell
        raw = raw.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty || raw == "-" { return nil }
        let base = (raw as NSString).lastPathComponent
        return (tasksDir as NSString).appendingPathComponent(base)
    }

    private static func resolveOutcome(_ tasksDir: String, taskId: String, specPath: String?) -> String? {
        if taskId.isEmpty { return nil }
        let dir = specPath.map { ($0 as NSString).deletingLastPathComponent } ?? tasksDir
        let fm = FileManager.default
        let exact = (dir as NSString).appendingPathComponent("\(taskId)-outcome.md")
        if fm.fileExists(atPath: exact) { return exact }

        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        let match = entries
            .filter { $0.hasPrefix("\(taskId)-") && $0.hasSuffix("-outcome.md") }
            .sorted()
            .first
        return match.map { (dir as NSString).appendingPathComponent($0) }
    }

    private static func taskId(fromSpec specPath: String?) -> String {
        guard let specPath else { return "" }
        let base = (specPath as NSString).lastPathComponent
        return firstGroup(taskIdRegex, base) ?? ""
    }

    // MARK: - String + regex helpers

    private static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }

    private static func splitRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        cells.allSatisfy { cell in
            cell.isEmpty || cell.range(of: "^:?-{1,}:?$", options: .regularExpression) != nil
        }
    }

    private static func cell(_ cells: [String], _ index: Int) -> String {
        index < cells.count ? cells[index] : ""
    }

    private static func join(_ components: String...) -> String {
        var result = components.first ?? ""
        for part in components.dropFirst() {
            result = (result as NSString).appendingPathComponent(part)
        }
        return result
    }

    private static func readFileSafe(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    private static func firstGroup(_ re: NSRegularExpression?, _ s: String) -> String? {
        guard let re else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2,
              m.range(at: 1).location != NSNotFound else {
            return nil
        }
        return ns.substring(with: m.range(at: 1))
    }

    private static func firstTwoGroups(_ re: NSRegularExpression?, _ s: String) -> (String, String)? {
        guard let re else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 3,
              m.range(at: 1).location != NSNotFound else {
            return nil
        }
        let group1 = ns.substring(with: m.range(at: 1))
        let group2 = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
        return (group1, group2)
    }
}
