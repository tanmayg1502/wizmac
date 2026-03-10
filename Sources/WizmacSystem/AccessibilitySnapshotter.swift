import AppKit
import ApplicationServices
import Foundation
import WizmacCore

public final class AccessibilitySnapshotter: AccessibilitySnapshotting {
    private struct CachedUISession {
        var id: String
        var processIdentifier: pid_t
        var scope: UISearchScope
        var includeMenus: Bool
        var snapshot: TargetSnapshot
        var targetIndex: [String: TargetDescriptor]
        var lastAccessedAt: Date
        var lastRefreshedAt: Date
        var cacheHits: Int
        var cacheMisses: Int
    }

    final class ObserverBridge {
        let pid: pid_t
        private let onInvalidation: (pid_t) -> Void

        init(pid: pid_t, onInvalidation: @escaping (pid_t) -> Void) {
            self.pid = pid
            self.onInvalidation = onInvalidation
        }

        func invalidate() {
            onInvalidation(pid)
        }
    }

    private final class ObserverRegistration {
        let observer: AXObserver
        let bridge: ObserverBridge
        var applicationElement: AXUIElement
        var focusedWindow: AXUIElement?

        init(
            observer: AXObserver,
            bridge: ObserverBridge,
            applicationElement: AXUIElement,
            focusedWindow: AXUIElement?
        ) {
            self.observer = observer
            self.bridge = bridge
            self.applicationElement = applicationElement
            self.focusedWindow = focusedWindow
        }
    }

    private let maxDepth = 8
    private let maxNodes = 400
    private let maxSessionCount = 5
    private let sessionTTL: TimeInterval = 10
    private let invalidationLock = NSLock()
    private let applicationObserverNotifications = [
        kAXFocusedWindowChangedNotification as String,
        kAXFocusedUIElementChangedNotification as String,
        kAXMainWindowChangedNotification as String,
        kAXWindowCreatedNotification as String,
    ]
    private let windowObserverNotifications = [
        kAXMovedNotification as String,
        kAXResizedNotification as String,
        kAXTitleChangedNotification as String,
        kAXValueChangedNotification as String,
        kAXSelectedTextChangedNotification as String,
    ]

    private var sessionsByID: [String: CachedUISession] = [:]
    private var sessionAccessOrder: [String] = []
    private var lastSessionID: String?
    private var observersByPID: [pid_t: ObserverRegistration] = [:]
    private var invalidatedPIDs = Set<pid_t>()

    public init() {}

    deinit {
        removeAllObservers()
    }

    public func snapshotFrontmostApplication(labelAlphabet: String) -> TargetSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return snapshotApplication(pid: app.processIdentifier, labelAlphabet: labelAlphabet)
    }

    public func snapshotApplication(pid: pid_t, labelAlphabet: String) -> TargetSnapshot? {
        buildSnapshot(
            pid: pid,
            labelAlphabet: labelAlphabet,
            scope: .app,
            includeMenus: true,
            sessionID: nil,
            snapshotID: nil
        )
    }

    public func listApplications() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { app in
                RunningAppInfo(
                    pid: app.processIdentifier,
                    name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                    bundleIdentifier: app.bundleIdentifier,
                    isActive: app.isActive
                )
            }
    }

    public func search(query: String, labelAlphabet: String, limit: Int = 50) -> TargetSnapshot? {
        guard let searchResult = search(
            query: query,
            pid: nil,
            labelAlphabet: labelAlphabet,
            limit: limit,
            sessionID: nil,
            scope: .focusedWindow,
            includeMenus: false
        ) else {
            return nil
        }
        return searchResult.snapshot
    }

    public func search(query: String, pid: pid_t, labelAlphabet: String, limit: Int = 50) -> TargetSnapshot? {
        guard let searchResult = search(
            query: query,
            pid: pid,
            labelAlphabet: labelAlphabet,
            limit: limit,
            sessionID: nil,
            scope: .focusedWindow,
            includeMenus: false
        ) else {
            return nil
        }
        return searchResult.snapshot
    }

    func search(
        query: String,
        pid: pid_t?,
        labelAlphabet: String,
        limit: Int,
        sessionID: String?,
        scope: UISearchScope,
        includeMenus: Bool
    ) -> UISearchResult? {
        pruneExpiredSessions()

        guard let resolvedPID = resolvePID(pid) else { return nil }
        let currentWindowTitle = currentWindowTitle(for: resolvedPID)

        let cacheLookupStartedAt = Date()
        var cachedSession = loadCachedSession(
            sessionID: sessionID,
            pid: resolvedPID,
            scope: scope,
            includeMenus: includeMenus,
            currentWindowTitle: currentWindowTitle
        )
        let cacheLookupMs = Date().timeIntervalSince(cacheLookupStartedAt) * 1_000

        let snapshotStartedAt = Date()
        let cacheHit = cachedSession != nil
        if cachedSession == nil {
            cachedSession = refreshedSession(
                existingSessionID: sessionID,
                pid: resolvedPID,
                labelAlphabet: labelAlphabet,
                scope: scope,
                includeMenus: includeMenus
            )
        }
        let snapshotMs = cacheHit ? 0 : (Date().timeIntervalSince(snapshotStartedAt) * 1_000)

        guard var cachedSession else { return nil }
        if cacheHit {
            cachedSession.cacheHits += 1
        } else {
            cachedSession.cacheMisses += 1
        }
        cachedSession.lastAccessedAt = Date()

        let rankingStartedAt = Date()
        var filtered = filteringSnapshot(cachedSession.snapshot, query: query, labelAlphabet: labelAlphabet, limit: limit)
        let rankingMs = Date().timeIntervalSince(rankingStartedAt) * 1_000
        filtered.sessionID = cachedSession.id
        filtered.snapshotID = cachedSession.snapshot.snapshotID

        storeSession(cachedSession)

        return UISearchResult(
            snapshot: filtered,
            metrics: metrics(
                for: cachedSession,
                cacheHit: cacheHit,
                snapshotMs: snapshotMs,
                cacheLookupMs: cacheLookupMs,
                rankingMs: rankingMs
            )
        )
    }

    public func target(id: String, labelAlphabet: String) -> TargetDescriptor? {
        target(
            id: id,
            pid: nil,
            labelAlphabet: labelAlphabet,
            sessionID: nil,
            snapshotID: nil,
            scope: .focusedWindow,
            includeMenus: false
        )?.target
    }

    public func target(id: String, pid: pid_t, labelAlphabet: String) -> TargetDescriptor? {
        target(
            id: id,
            pid: pid,
            labelAlphabet: labelAlphabet,
            sessionID: nil,
            snapshotID: nil,
            scope: .focusedWindow,
            includeMenus: false
        )?.target
    }

    func target(
        id: String,
        pid: pid_t?,
        labelAlphabet: String,
        sessionID: String?,
        snapshotID: String?,
        scope: UISearchScope,
        includeMenus: Bool
    ) -> UITargetLookupResult? {
        pruneExpiredSessions()

        guard let resolvedPID = resolvePID(pid) else { return nil }
        let currentWindowTitle = currentWindowTitle(for: resolvedPID)
        let cacheLookupStartedAt = Date()
        var cachedSession = loadCachedSession(
            sessionID: sessionID,
            pid: resolvedPID,
            scope: scope,
            includeMenus: includeMenus,
            currentWindowTitle: currentWindowTitle
        )
        let cacheLookupMs = Date().timeIntervalSince(cacheLookupStartedAt) * 1_000

        var cacheHit = false
        var snapshotMs = 0.0

        if let snapshotID, cachedSession?.snapshot.snapshotID != snapshotID {
            cachedSession = nil
        }

        if cachedSession == nil || cachedSession?.targetIndex[id] == nil {
            let snapshotStartedAt = Date()
            cachedSession = refreshedSession(
                existingSessionID: cachedSession?.id ?? sessionID,
                pid: resolvedPID,
                labelAlphabet: labelAlphabet,
                scope: scope,
                includeMenus: includeMenus
            )
            snapshotMs = Date().timeIntervalSince(snapshotStartedAt) * 1_000
        } else {
            cacheHit = true
        }

        guard var cachedSession, let target = cachedSession.targetIndex[id] else { return nil }
        if cacheHit {
            cachedSession.cacheHits += 1
        } else {
            cachedSession.cacheMisses += 1
        }
        cachedSession.lastAccessedAt = Date()
        storeSession(cachedSession)

        return UITargetLookupResult(
            target: target,
            metrics: metrics(
                for: cachedSession,
                cacheHit: cacheHit,
                snapshotMs: snapshotMs,
                cacheLookupMs: cacheLookupMs,
                rankingMs: 0
            )
        )
    }

    func endSession(id: String?) -> UISessionMetrics? {
        pruneExpiredSessions()
        let sessionID = id ?? lastSessionID
        guard let sessionID, let removed = sessionsByID.removeValue(forKey: sessionID) else { return nil }
        sessionAccessOrder.removeAll { $0 == sessionID }
        if lastSessionID == sessionID {
            lastSessionID = sessionAccessOrder.last
        }
        pruneOrphanedObservers()
        return metrics(for: removed, cacheHit: false, snapshotMs: 0, cacheLookupMs: 0, rankingMs: 0)
    }

    func currentSession() -> UISessionMetrics? {
        pruneExpiredSessions()
        guard let lastSessionID, let cachedSession = sessionsByID[lastSessionID] else { return nil }
        return metrics(for: cachedSession, cacheHit: false, snapshotMs: 0, cacheLookupMs: 0, rankingMs: 0)
    }

    public func hintSession(query: String?, labelAlphabet: String, limit: Int = 50) -> UIHintSession? {
        guard let snapshot = buildSnapshot(
            pid: resolvePID(nil),
            labelAlphabet: labelAlphabet,
            scope: .focusedWindow,
            includeMenus: false,
            sessionID: nil,
            snapshotID: nil
        ) else {
            return nil
        }
        return buildHintSession(query: query, labelAlphabet: labelAlphabet, limit: limit, from: snapshot)
    }

    public func hintSession(query: String?, pid: pid_t, labelAlphabet: String, limit: Int = 50) -> UIHintSession? {
        guard let snapshot = buildSnapshot(
            pid: pid,
            labelAlphabet: labelAlphabet,
            scope: .focusedWindow,
            includeMenus: false,
            sessionID: nil,
            snapshotID: nil
        ) else {
            return nil
        }
        return buildHintSession(query: query, labelAlphabet: labelAlphabet, limit: limit, from: snapshot)
    }

    private func filteringSnapshot(_ snapshot: TargetSnapshot, query: String, labelAlphabet: String, limit: Int) -> TargetSnapshot {
        var result = snapshot
        let scored = snapshot.targets
            .map { ($0, FuzzyMatcher.score(query: query, in: $0)) }
            .filter { candidate, score in
                guard score > 0 else { return false }
                return candidate.frame == nil || isFrameActionable(candidate.frame?.cgRect)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
                }
                return lhs.1 > rhs.1
            }
            .prefix(limit)
            .map(\.0)

        let labels = LabelGenerator.labels(count: scored.count, alphabet: labelAlphabet)
        result.targets = zip(scored, labels).map { target, label in
            var updated = target
            updated.hint = label
            return updated
        }
        return result
    }

    private func buildHintSession(query: String?, labelAlphabet: String, limit: Int, from snapshot: TargetSnapshot) -> UIHintSession {
        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: TargetSnapshot
        if let normalizedQuery, normalizedQuery.isEmpty == false {
            filtered = filteringSnapshot(snapshot, query: normalizedQuery, labelAlphabet: labelAlphabet, limit: limit)
        } else {
            var copy = snapshot
            copy.targets = Array(snapshot.targets.prefix(limit))
            filtered = copy
        }
        return UIHintSession(query: normalizedQuery, alphabet: labelAlphabet, snapshot: filtered)
    }

    private func buildSnapshot(
        pid: pid_t?,
        labelAlphabet: String,
        scope: UISearchScope,
        includeMenus: Bool,
        sessionID: String?,
        snapshotID: String?
    ) -> TargetSnapshot? {
        guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let applicationElement = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(applicationElement, 0.05)

        let targets = collectTargets(
            applicationElement: applicationElement,
            appName: appName,
            labelAlphabet: labelAlphabet,
            scope: scope,
            includeMenus: includeMenus
        )
        let windowTitle = focusedWindowTitle(for: applicationElement)

        return TargetSnapshot(
            appName: appName,
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: windowTitle,
            sessionID: sessionID,
            snapshotID: snapshotID ?? UUID().uuidString,
            targets: targets
        )
    }

    private func collectTargets(
        applicationElement: AXUIElement,
        appName: String,
        labelAlphabet: String,
        scope: UISearchScope,
        includeMenus: Bool
    ) -> [TargetDescriptor] {
        let roots = rootElements(
            for: applicationElement,
            scope: scope,
            includeMenus: includeMenus
        )

        var results: [TargetDescriptor] = []
        var visitedKeys = Set<String>()

        for (root, rootLabel) in roots {
            var queue: [(AXUIElement, [String], Int)] = [(root, [rootLabel], 0)]

            while queue.isEmpty == false, results.count < maxNodes {
                let (element, path, depth) = queue.removeFirst()
                guard depth <= maxDepth else { continue }

                let attributes = attributeValues(
                    for: element,
                    attributes: [
                        kAXRoleAttribute,
                        kAXTitleAttribute,
                        kAXDescriptionAttribute,
                        kAXIdentifierAttribute,
                        kAXValueAttribute,
                        kAXHelpAttribute,
                        kAXChildrenAttribute,
                        kAXRowsAttribute,
                        kAXTabsAttribute,
                        kAXColumnsAttribute,
                        kAXContentsAttribute,
                        kAXVisibleChildrenAttribute,
                    ]
                )

                let role = stringValue(from: attributes[kAXRoleAttribute]) ?? "AXUnknown"
                let title = stringValue(from: attributes[kAXTitleAttribute])
                    ?? stringValue(from: attributes[kAXDescriptionAttribute])
                    ?? stringValue(from: attributes[kAXIdentifierAttribute])
                    ?? ""
                let value = stringValue(from: attributes[kAXValueAttribute])

                let stableKey = [role, title, value ?? "", path.joined(separator: "/")].joined(separator: "|")
                guard visitedKeys.insert(stableKey).inserted else { continue }

                if shouldInclude(role: role, title: title, value: value, includeMenus: includeMenus) {
                    let frame = rectValue(for: element)
                    if frame == nil || isFrameActionable(frame) {
                        results.append(
                            TargetDescriptor(
                                id: stableID(
                                    appName: appName,
                                    role: role,
                                    title: title,
                                    value: value,
                                    path: path,
                                    frame: frame
                                ),
                                appName: appName,
                                role: role,
                                title: title.isEmpty ? role : title,
                                subtitle: stringValue(from: attributes[kAXHelpAttribute]),
                                value: value,
                                frame: frame.map(TargetRect.init),
                                path: path
                            )
                        )
                    }
                }

                let childAttributes = [
                    kAXChildrenAttribute,
                    kAXRowsAttribute,
                    kAXTabsAttribute,
                    kAXColumnsAttribute,
                    kAXContentsAttribute,
                    kAXVisibleChildrenAttribute,
                ]

                var childrenToEnqueue: [(AXUIElement, String, Int)] = []
                for attribute in childAttributes {
                    for (index, child) in elements(from: attributes[attribute]).enumerated() {
                        childrenToEnqueue.append((child, "\(role)[\(index)]", depth + 1))
                    }
                }

                let sheets = childrenToEnqueue.filter {
                    (stringValue(for: $0.0, attribute: kAXRoleAttribute) ?? "") == "AXSheet"
                }
                let rest = childrenToEnqueue.filter {
                    (stringValue(for: $0.0, attribute: kAXRoleAttribute) ?? "") != "AXSheet"
                }
                for (child, label, nextDepth) in sheets + rest {
                    queue.append((child, path + [label], nextDepth))
                }
            }

            if results.count >= maxNodes { break }
        }

        let labels = LabelGenerator.labels(count: results.count, alphabet: labelAlphabet)
        return zip(results, labels).map { target, label in
            var updated = target
            updated.hint = label
            return updated
        }
    }

    private func rootElements(
        for applicationElement: AXUIElement,
        scope: UISearchScope,
        includeMenus: Bool
    ) -> [(AXUIElement, String)] {
        let focused = focusedWindow(for: applicationElement)
        let windows = children(for: applicationElement, attribute: kAXWindowsAttribute)
        var roots: [(AXUIElement, String)] = []

        if let focused {
            let focusedLabel = stringValue(for: focused, attribute: kAXRoleAttribute) ?? "AXWindow"
            roots.append((focused, focusedLabel))
            for (index, sheet) in children(for: focused, attribute: "AXSheets").enumerated() {
                roots.insert((sheet, "AXSheet[\(index)]"), at: 0)
            }
        }

        if scope == .app {
            for (index, window) in windows.enumerated() where focused.map({ CFEqual($0, window) }) != true {
                let label = stringValue(for: window, attribute: kAXRoleAttribute) ?? "AXWindow[\(index)]"
                roots.append((window, label))
            }
        }

        if roots.isEmpty {
            roots = windows.enumerated().map { index, window in
                let label = stringValue(for: window, attribute: kAXRoleAttribute) ?? "AXWindow[\(index)]"
                return (window, label)
            }
        }

        if includeMenus {
            if let menuBar = firstChild(for: applicationElement, attribute: kAXMenuBarAttribute) {
                roots.append((menuBar, "AXMenuBar"))
            } else {
                let appChildren = children(for: applicationElement, attribute: kAXChildrenAttribute)
                if let menuBar = appChildren.first(where: {
                    (stringValue(for: $0, attribute: kAXRoleAttribute) ?? "") == "AXMenuBar"
                }) {
                    roots.append((menuBar, "AXMenuBar"))
                }
            }
        }

        return roots.isEmpty ? [(applicationElement, "AXApplication")] : roots
    }

    private func refreshedSession(
        existingSessionID: String?,
        pid: pid_t,
        labelAlphabet: String,
        scope: UISearchScope,
        includeMenus: Bool
    ) -> CachedUISession? {
        let resolvedSessionID = existingSessionID ?? UUID().uuidString
        guard let snapshot = buildSnapshot(
            pid: pid,
            labelAlphabet: labelAlphabet,
            scope: scope,
            includeMenus: includeMenus,
            sessionID: resolvedSessionID,
            snapshotID: UUID().uuidString
        ) else {
            return nil
        }

        ensureObserver(for: pid)
        clearObserverInvalidation(for: pid)

        let now = Date()
        return CachedUISession(
            id: resolvedSessionID,
            processIdentifier: pid,
            scope: scope,
            includeMenus: includeMenus,
            snapshot: snapshot,
            targetIndex: Dictionary(uniqueKeysWithValues: snapshot.targets.map { ($0.id, $0) }),
            lastAccessedAt: now,
            lastRefreshedAt: now,
            cacheHits: 0,
            cacheMisses: 0
        )
    }

    private func loadCachedSession(
        sessionID: String?,
        pid: pid_t,
        scope: UISearchScope,
        includeMenus: Bool,
        currentWindowTitle: String?
    ) -> CachedUISession? {
        guard isInvalidated(pid: pid) == false else { return nil }

        if let sessionID, let cached = sessionsByID[sessionID] {
            guard cached.processIdentifier == pid else { return nil }
            guard cached.scope == scope, cached.includeMenus == includeMenus else { return nil }
            guard sessionIsFresh(cached, currentWindowTitle: currentWindowTitle) else { return nil }
            return cached
        }

        return sessionAccessOrder
            .reversed()
            .compactMap { sessionsByID[$0] }
            .first { cached in
                cached.processIdentifier == pid &&
                    cached.scope == scope &&
                    cached.includeMenus == includeMenus &&
                    sessionIsFresh(cached, currentWindowTitle: currentWindowTitle)
            }
    }

    private func sessionIsFresh(_ cached: CachedUISession, currentWindowTitle: String?) -> Bool {
        guard Date().timeIntervalSince(cached.lastRefreshedAt) <= sessionTTL else { return false }
        if cached.scope == .focusedWindow {
            return cached.snapshot.windowTitle == currentWindowTitle
        }
        return true
    }

    private func storeSession(_ session: CachedUISession) {
        sessionsByID[session.id] = session
        sessionAccessOrder.removeAll { $0 == session.id }
        sessionAccessOrder.append(session.id)
        lastSessionID = session.id

        while sessionAccessOrder.count > maxSessionCount {
            let oldest = sessionAccessOrder.removeFirst()
            sessionsByID.removeValue(forKey: oldest)
            if lastSessionID == oldest {
                lastSessionID = sessionAccessOrder.last
            }
        }

        pruneOrphanedObservers()
    }

    private func pruneExpiredSessions() {
        let now = Date()
        let expiredIDs = sessionsByID.values
            .filter { now.timeIntervalSince($0.lastAccessedAt) > sessionTTL }
            .map(\.id)

        for expiredID in expiredIDs {
            sessionsByID.removeValue(forKey: expiredID)
            sessionAccessOrder.removeAll { $0 == expiredID }
            if lastSessionID == expiredID {
                lastSessionID = sessionAccessOrder.last
            }
        }

        pruneOrphanedObservers()
    }

    private func metrics(
        for session: CachedUISession,
        cacheHit: Bool,
        snapshotMs: Double,
        cacheLookupMs: Double,
        rankingMs: Double
    ) -> UISessionMetrics {
        let totalRequests = max(1, session.cacheHits + session.cacheMisses)
        return UISessionMetrics(
            sessionID: session.id,
            snapshotID: session.snapshot.snapshotID ?? UUID().uuidString,
            appName: session.snapshot.appName,
            windowTitle: session.snapshot.windowTitle,
            targetCount: session.snapshot.targets.count,
            cacheHit: cacheHit,
            cacheHitRate: Double(session.cacheHits) / Double(totalRequests),
            lastRefreshedAt: session.lastRefreshedAt,
            snapshotMs: snapshotMs,
            cacheLookupMs: cacheLookupMs,
            rankingMs: rankingMs
        )
    }

    private func resolvePID(_ requestedPID: pid_t?) -> pid_t? {
        requestedPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private func ensureObserver(for pid: pid_t) {
        let applicationElement = AXUIElementCreateApplication(pid)
        let focusedWindow = focusedWindow(for: applicationElement)

        if let registration = observersByPID[pid] {
            refreshObserver(registration, applicationElement: applicationElement, focusedWindow: focusedWindow)
            return
        }

        var observerRef: AXObserver?
        let result = AXObserverCreate(pid, axObserverCallback, &observerRef)
        guard result == .success, let observerRef else { return }

        let bridge = ObserverBridge(pid: pid) { [weak self] pid in
            self?.markObserverInvalidated(pid: pid)
        }
        let registration = ObserverRegistration(
            observer: observerRef,
            bridge: bridge,
            applicationElement: applicationElement,
            focusedWindow: focusedWindow
        )
        observersByPID[pid] = registration
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observerRef), .defaultMode)
        registerObserverNotifications(for: registration)
    }

    private func refreshObserver(
        _ registration: ObserverRegistration,
        applicationElement: AXUIElement,
        focusedWindow: AXUIElement?
    ) {
        unregisterApplicationNotifications(for: registration)
        unregisterWindowNotifications(for: registration)
        registration.applicationElement = applicationElement
        registration.focusedWindow = focusedWindow
        registerObserverNotifications(for: registration)
    }

    private func registerObserverNotifications(for registration: ObserverRegistration) {
        let refcon = Unmanaged.passUnretained(registration.bridge).toOpaque()

        for notification in applicationObserverNotifications {
            _ = AXObserverAddNotification(
                registration.observer,
                registration.applicationElement,
                notification as CFString,
                refcon
            )
        }

        guard let focusedWindow = registration.focusedWindow else { return }
        for notification in windowObserverNotifications {
            _ = AXObserverAddNotification(
                registration.observer,
                focusedWindow,
                notification as CFString,
                refcon
            )
        }
    }

    private func unregisterApplicationNotifications(for registration: ObserverRegistration) {
        for notification in applicationObserverNotifications {
            _ = AXObserverRemoveNotification(
                registration.observer,
                registration.applicationElement,
                notification as CFString
            )
        }
    }

    private func unregisterWindowNotifications(for registration: ObserverRegistration) {
        guard let focusedWindow = registration.focusedWindow else { return }
        for notification in windowObserverNotifications {
            _ = AXObserverRemoveNotification(
                registration.observer,
                focusedWindow,
                notification as CFString
            )
        }
    }

    private func pruneOrphanedObservers() {
        let activePIDs = Set(sessionsByID.values.map(\.processIdentifier))
        let orphanedPIDs = observersByPID.keys.filter { activePIDs.contains($0) == false }
        for pid in orphanedPIDs {
            removeObserver(for: pid)
        }
    }

    private func removeObserver(for pid: pid_t) {
        guard let registration = observersByPID.removeValue(forKey: pid) else { return }
        unregisterApplicationNotifications(for: registration)
        unregisterWindowNotifications(for: registration)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(registration.observer), .defaultMode)
        clearObserverInvalidation(for: pid)
    }

    private func removeAllObservers() {
        for pid in Array(observersByPID.keys) {
            removeObserver(for: pid)
        }
    }

    private func markObserverInvalidated(pid: pid_t) {
        invalidationLock.lock()
        invalidatedPIDs.insert(pid)
        invalidationLock.unlock()
    }

    private func clearObserverInvalidation(for pid: pid_t) {
        invalidationLock.lock()
        invalidatedPIDs.remove(pid)
        invalidationLock.unlock()
    }

    private func isInvalidated(pid: pid_t) -> Bool {
        invalidationLock.lock()
        defer { invalidationLock.unlock() }
        return invalidatedPIDs.contains(pid)
    }

    private func currentWindowTitle(for pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        return focusedWindowTitle(for: app)
    }

    private func shouldInclude(role: String, title: String, value: String?, includeMenus: Bool) -> Bool {
        let loweredRole = role.lowercased()
        if includeMenus == false, loweredRole.contains("menu") {
            return false
        }

        let actionableRoleFragments = [
            "button", "link", "textfield", "textarea", "checkbox",
            "radiobutton", "scroll", "slider", "tab", "group",
        ]

        if actionableRoleFragments.contains(where: loweredRole.contains) {
            return true
        }

        return title.isEmpty == false || (value?.isEmpty == false)
    }

    private func attributeValues(for element: AXUIElement, attributes: [String]) -> [String: CFTypeRef] {
        var values: CFArray?
        let attributeNames = attributes.map { $0 as CFString } as CFArray
        if AXUIElementCopyMultipleAttributeValues(
            element,
            attributeNames,
            AXCopyMultipleAttributeOptions(),
            &values
        ) == .success,
           let array = values as? [Any]
        {
            var result: [String: CFTypeRef] = [:]
            for (attribute, value) in zip(attributes, array) {
                if value is NSNull { continue }
                result[attribute] = value as CFTypeRef
            }
            return result
        }

        var fallback: [String: CFTypeRef] = [:]
        for attribute in attributes {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value {
                fallback[attribute] = value
            }
        }
        return fallback
    }

    private func stringValue(for element: AXUIElement, attribute: String) -> String? {
        stringValue(from: attributeValues(for: element, attributes: [attribute])[attribute])
    }

    private func stringValue(from value: CFTypeRef?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSAttributedString:
            return value.string
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private func rectValue(for element: AXUIElement) -> CGRect? {
        let attributes = attributeValues(for: element, attributes: [kAXPositionAttribute, kAXSizeAttribute])
        guard
            let positionAttribute = attributes[kAXPositionAttribute],
            let sizeAttribute = attributes[kAXSizeAttribute]
        else {
            return nil
        }
        let positionValue = positionAttribute as! AXValue
        let sizeValue = sizeAttribute as! AXValue

        var point = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue, .cgPoint, &point),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: point, size: size)
    }

    private func isFrameActionable(_ frame: CGRect?) -> Bool {
        guard let frame, frame.width > 0, frame.height > 0 else { return false }
        return NSScreen.screens.isEmpty || NSScreen.screens.contains(where: { $0.frame.intersects(frame) })
    }

    private func children(for element: AXUIElement, attribute: String) -> [AXUIElement] {
        elements(from: attributeValues(for: element, attributes: [attribute])[attribute])
    }

    private func firstChild(for element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else {
            return nil
        }

        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return (value as! AXUIElement)
        }
        return nil
    }

    private func elements(from value: CFTypeRef?) -> [AXUIElement] {
        if let elements = value as? [AXUIElement] {
            return elements
        }
        return []
    }

    private func focusedWindow(for applicationElement: AXUIElement) -> AXUIElement? {
        firstChild(for: applicationElement, attribute: kAXFocusedWindowAttribute)
    }

    private func focusedWindowTitle(for applicationElement: AXUIElement) -> String? {
        guard let window = focusedWindow(for: applicationElement) else { return nil }
        return stringValue(for: window, attribute: kAXTitleAttribute)
    }

    private func stableID(
        appName: String,
        role: String,
        title: String,
        value: String?,
        path: [String],
        frame: CGRect?
    ) -> String {
        let frameString: String
        if let frame {
            frameString = "\(Int(frame.origin.x)):\(Int(frame.origin.y)):\(Int(frame.size.width)):\(Int(frame.size.height))"
        } else {
            frameString = "noframe"
        }

        let raw = [appName, role, title, value ?? "", path.joined(separator: "/"), frameString].joined(separator: "|")
        return Data(raw.utf8).base64EncodedString()
    }
}

private let axObserverCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let bridge = Unmanaged<AccessibilitySnapshotter.ObserverBridge>.fromOpaque(refcon).takeUnretainedValue()
    bridge.invalidate()
}
