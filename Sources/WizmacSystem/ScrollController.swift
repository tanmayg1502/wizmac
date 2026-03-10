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
        snapshot.targets.filter { target in
            let loweredRole = target.role.lowercased()
            return loweredRole.contains("scroll")
                || loweredRole.contains("table")
                || loweredRole.contains("list")
                || loweredRole.contains("outline")
        }
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
}
