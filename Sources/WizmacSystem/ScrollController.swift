import ApplicationServices
import Foundation
import WizmacCore

public final class ScrollController: ScrollControlling {
    private let performer: any ScrollEventPerforming
    private(set) var focusedTargetID: String?
    private var activeSession: ScrollSession?

    init(performer: any ScrollEventPerforming = CGScrollEventPerformer()) {
        self.performer = performer
    }

    public func scrollTargets(from snapshot: TargetSnapshot) -> [TargetDescriptor] {
        snapshot.targets
            .compactMap { target -> (TargetDescriptor, Int, Double)? in
                guard let frame = target.frame else { return nil }
                let score = scrollAffinityScore(for: target, frame: frame)
                guard score > 0 else { return nil }
                return (target, score, frame.width * frame.height)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                if lhs.2 != rhs.2 {
                    return lhs.2 > rhs.2
                }
                return lhs.0.id.localizedCaseInsensitiveCompare(rhs.0.id) == .orderedAscending
            }
            .map(\.0)
    }

    public func focus(targetID: String) {
        focusedTargetID = targetID
    }

    public func startSession(targetID: String?, snapshot: TargetSnapshot) -> ScrollSession? {
        let candidate = targetID
            .flatMap { id in snapshot.targets.first(where: { $0.id == id }) }
            ?? scrollTargets(from: snapshot).first

        guard let candidate else { return nil }
        focusedTargetID = candidate.id
        let session = ScrollSession(targetID: candidate.id)
        activeSession = session
        return session
    }

    public func endSession() -> ScrollSession? {
        defer {
            activeSession = nil
            focusedTargetID = nil
        }
        return activeSession
    }

    public func currentSession() -> ScrollSession? {
        activeSession
    }

    @discardableResult
    public func step(direction: String, amount: Int, snapshot: TargetSnapshot) -> Bool {
        let targetID = activeSession?.targetID ?? focusedTargetID
        let candidate = snapshot.targets.first { $0.id == targetID }
            ?? scrollTargets(from: snapshot).first

        guard let target = candidate, let frame = target.frame else { return false }
        let success = performer.scroll(direction: direction, amount: amount, at: frame.center)
        focusedTargetID = target.id
        if success {
            if var session = activeSession, session.targetID == target.id {
                session.stepCount += 1
                session.lastStepAt = Date()
                activeSession = session
            } else {
                activeSession = ScrollSession(targetID: target.id, lastStepAt: Date(), stepCount: 1)
            }
        }
        return success
    }

    private func scrollAffinityScore(for target: TargetDescriptor, frame: TargetRect) -> Int {
        let loweredRole = target.role.lowercased()
        let loweredPath = target.path.joined(separator: " ").lowercased()
        var score = 0

        if loweredRole.contains("scroll") {
            score = max(score, 380)
        }
        if loweredRole.contains("table") {
            score = max(score, 340)
        }
        if loweredRole.contains("list") {
            score = max(score, 340)
        }
        if loweredRole.contains("outline") {
            score = max(score, 260)
        }

        if loweredPath.contains("axscrollarea") {
            score = max(score, 260)
        }
        if loweredPath.contains("axtable") {
            score = max(score, 240)
        }
        if loweredPath.contains("axlist") {
            score = max(score, frame.width >= 600 ? 360 : 230)
        }
        if loweredPath.contains("axoutline") {
            score = max(score, 220)
            if frame.width < 240 {
                score -= 48
            }
        }

        // Fallback: large AXGroup or AXWebArea elements (e.g. Electron/web
        // apps like Slack) that don't use explicit scroll roles but are still
        // scrollable content areas.
        if score == 0 {
            let isLargeContainer = frame.width >= 300 && frame.height >= 200
            if isLargeContainer {
                if loweredRole == "axwebarea" {
                    score = 140
                } else if loweredRole == "axgroup" || loweredRole == "axtabgroup" {
                    score = 80
                }
            }
        }

        guard score > 0 else { return 0 }

        if frame.width >= 600 {
            score += 90
        } else if frame.width >= 300 {
            score += 40
        } else if frame.width >= 180 {
            score += 8
        } else if frame.width < 220 {
            score -= 36
        }

        if frame.height >= 180 {
            score += 20
        }

        if frame.x >= 250 {
            score += 24
        } else if frame.x < 220 {
            score -= 18
        }

        return score
    }
}
