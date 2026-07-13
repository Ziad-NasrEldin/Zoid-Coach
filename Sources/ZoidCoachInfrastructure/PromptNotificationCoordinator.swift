import Foundation
import UserNotifications
import ZoidCoachCore

public enum PromptNotificationCategory: String, CaseIterable, Sendable {
    case planReady = "PLAN_READY"
    case meetingCandidate = "MEETING_CANDIDATE"
    case planChanged = "PLAN_CHANGED"
    case wakeIntervention = "WAKE_INTERVENTION"
    case onboardingTest = "ONBOARDING_TEST"
    case gamingDrift = "GAMING_DRIFT"

    public static func forPromptType(_ type: String) -> PromptNotificationCategory? {
        PromptNotificationCategory(rawValue: type)
    }
}

public final class PromptNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center: UNUserNotificationCenter?
    private let promptStore: PromptInboxStore
    private let notificationIdentity: RuntimeNotificationIdentity
    private let deliveryLedger: NotificationDeliveryLedger?
    private let fixtureAdapter: DeterministicOSFixtureAdapters?
    private let deliveryBoundary: @Sendable (Date) -> Date
    private let onResponse: @Sendable (PromptResponseResult) async -> Void

    public init(
        promptStore: PromptInboxStore,
        center: UNUserNotificationCenter = .current(),
        runtimeEnvironment: RuntimeEnvironment = .production(),
        deliveryBoundary: @escaping @Sendable (Date) -> Date = { $0 },
        onResponse: @escaping @Sendable (PromptResponseResult) async -> Void = { _ in }
    ) {
        self.promptStore = promptStore
        self.center = center
        fixtureAdapter = nil
        notificationIdentity = runtimeEnvironment.identity.notification
        deliveryLedger = try? NotificationDeliveryLedger(databaseURL: runtimeEnvironment.databaseURL)
        self.deliveryBoundary = deliveryBoundary
        self.onResponse = onResponse
        super.init()
    }

    public init(
        promptStore: PromptInboxStore,
        fixtureAdapter: DeterministicOSFixtureAdapters,
        runtimeEnvironment: RuntimeEnvironment,
        deliveryBoundary: @escaping @Sendable (Date) -> Date = { $0 },
        onResponse: @escaping @Sendable (PromptResponseResult) async -> Void = { _ in }
    ) {
        self.promptStore = promptStore
        center = nil
        self.fixtureAdapter = fixtureAdapter
        notificationIdentity = runtimeEnvironment.identity.notification
        deliveryLedger = try? NotificationDeliveryLedger(databaseURL: runtimeEnvironment.databaseURL)
        self.deliveryBoundary = deliveryBoundary
        self.onResponse = onResponse
        super.init()
    }

    public func activate() {
        guard let center else { return }
        center.delegate = self
        center.setNotificationCategories(Self.categories(notificationIdentity: notificationIdentity))
    }

    @discardableResult
    public func schedule(_ episode: PromptEpisode, deliveryDate: Date? = nil) async throws -> Bool {
        guard let category = PromptNotificationCategory.forPromptType(episode.type) else { return false }
        let now = Date()
        let boundedDeliveryDate = deliveryBoundary(deliveryDate ?? now)
        let effectiveDeliveryDate = boundedDeliveryDate > now ? boundedDeliveryDate : nil
        let requestIdentifier = notificationIdentity.promptRequestPrefix + episode.id
        if let fixtureAdapter {
            do {
                guard try fixtureAdapter.permission(.notifications) == .granted else {
                    recordDelivery(
                        requestIdentifier: requestIdentifier,
                        episode: episode,
                        category: category,
                        outcome: .authorizationUnavailable,
                        scheduledFor: effectiveDeliveryDate
                    )
                    return false
                }
                _ = try await fixtureAdapter.schedule(.init(
                    category: category.rawValue,
                    title: episode.title,
                    body: episode.summary,
                    promptID: episode.id,
                    deliveryDate: effectiveDeliveryDate
                ))
                _ = try fixtureAdapter.deliverDueNotifications()
                try await processFixtureActions()
                recordDelivery(
                    requestIdentifier: requestIdentifier,
                    episode: episode,
                    category: category,
                    outcome: .deliveredByFixture,
                    scheduledFor: effectiveDeliveryDate
                )
                return true
            } catch {
                recordDelivery(
                    requestIdentifier: requestIdentifier,
                    episode: episode,
                    category: category,
                    outcome: .schedulingFailed,
                    scheduledFor: effectiveDeliveryDate,
                    error: error
                )
                throw error
            }
        }
        guard let center else { return false }
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else {
            recordDelivery(
                requestIdentifier: requestIdentifier,
                episode: episode,
                category: category,
                outcome: .authorizationUnavailable,
                scheduledFor: effectiveDeliveryDate
            )
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = episode.title
        content.body = episode.summary
        content.categoryIdentifier = notificationIdentity.promptCategoryIdentifier(category.rawValue)
        content.sound = .default
        content.userInfo = ["promptID": episode.id]
        let trigger: UNNotificationTrigger?
        if let effectiveDeliveryDate {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, effectiveDeliveryDate.timeIntervalSinceNow), repeats: false)
        } else {
            trigger = nil
        }
        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
            center.removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
            try await center.add(request)
            recordDelivery(
                requestIdentifier: requestIdentifier,
                episode: episode,
                category: category,
                outcome: .acceptedBySystem,
                scheduledFor: effectiveDeliveryDate
            )
            return true
        } catch {
            recordDelivery(
                requestIdentifier: requestIdentifier,
                episode: episode,
                category: category,
                outcome: .schedulingFailed,
                scheduledFor: effectiveDeliveryDate,
                error: error
            )
            throw error
        }
    }

    public func scheduleAcceptedBreakEnd(
        taskID: String,
        taskTitle: String,
        startedAt: Date,
        deliveryDate: Date
    ) async throws -> Bool {
        let requestPrefix = acceptedBreakRequestPrefix(taskID: taskID)
        let requestIdentifier = requestPrefix + String(Int(startedAt.timeIntervalSince1970))
        let desired = NotificationDesiredState(
            category: "BREAK_END",
            title: "Break complete",
            body: "\(taskTitle) is ready when you are. Resume when it feels right.",
            promptID: requestIdentifier,
            deliveryDate: deliveryDate
        )

        if try deliveryLedger?.containsAcceptedDelivery(requestIdentifier: requestIdentifier) == true {
            return false
        }

        if let fixtureAdapter {
            let notifications = try fixtureAdapter.snapshot().notifications
            if notifications.contains(where: { $0.id == requestIdentifier }) {
                return false
            }
            guard try fixtureAdapter.permission(.notifications) == .granted else {
                return false
            }
            try fixtureAdapter.cancelNotifications(withPrefix: requestPrefix, keeping: requestIdentifier)
            _ = try await fixtureAdapter.schedule(desired)
            _ = try deliveryLedger?.record(
                requestIdentifier: requestIdentifier,
                promptID: requestIdentifier,
                category: desired.category,
                outcome: .deliveredByFixture,
                scheduledFor: deliveryDate
            )
            return true
        }

        guard let center else { return false }
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        if pending.contains(where: { $0.identifier == requestIdentifier })
            || delivered.contains(where: { $0.request.identifier == requestIdentifier }) {
            return false
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return false
        }

        let obsoletePending = pending.map(\.identifier).filter {
            $0.hasPrefix(requestPrefix) && $0 != requestIdentifier
        }
        let obsoleteDelivered = delivered.map(\.request.identifier).filter {
            $0.hasPrefix(requestPrefix) && $0 != requestIdentifier
        }
        center.removePendingNotificationRequests(withIdentifiers: obsoletePending)
        center.removeDeliveredNotifications(withIdentifiers: obsoleteDelivered)

        let content = UNMutableNotificationContent()
        content.title = desired.title
        content.body = desired.body
        content.categoryIdentifier = notificationIdentity.promptCategoryIdentifier(desired.category)
        content.userInfo = ["acceptedBreakTaskID": taskID]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, deliveryDate.timeIntervalSinceNow),
            repeats: false
        )
        try await center.add(UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: trigger
        ))
        _ = try deliveryLedger?.record(
            requestIdentifier: requestIdentifier,
            promptID: requestIdentifier,
            category: desired.category,
            outcome: .acceptedBySystem,
            scheduledFor: deliveryDate
        )
        return true
    }

    public func cancelAcceptedBreakEnds(taskID: String) async {
        let requestPrefix = acceptedBreakRequestPrefix(taskID: taskID)
        if let fixtureAdapter {
            try? fixtureAdapter.cancelNotifications(withPrefix: requestPrefix)
            return
        }
        guard let center else { return }
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter {
            $0.hasPrefix(requestPrefix)
        })
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter {
            $0.hasPrefix(requestPrefix)
        })
    }

    private func acceptedBreakRequestPrefix(taskID: String) -> String {
        notificationIdentity.actionRequestIdentifier("accepted-break.\(taskID).")
    }

    private func recordDelivery(
        requestIdentifier: String,
        episode: PromptEpisode,
        category: PromptNotificationCategory,
        outcome: NotificationDeliveryOutcome,
        scheduledFor: Date?,
        error: Error? = nil
    ) {
        _ = try? deliveryLedger?.record(
            requestIdentifier: requestIdentifier,
            promptID: episode.id,
            category: category.rawValue,
            outcome: outcome,
            scheduledFor: scheduledFor,
            error: error?.localizedDescription
        )
        _ = try? deliveryLedger?.enforceRetention()
    }

    public func processFixtureActions() async throws {
        guard let fixtureAdapter else { return }
        for notification in try fixtureAdapter.snapshot().notifications
            where notification.status == .responded {
            guard let identifier = notification.actionIdentifier,
                  let action = Self.fixtureActionKind(
                    identifier: identifier,
                    category: notification.desired.category,
                    notificationIdentity: notificationIdentity
                  ) else { continue }
            let result = try promptStore.respond(
                promptID: notification.desired.promptID,
                action: action,
                actionToken: PromptResponseToken.make(
                    promptID: notification.desired.promptID,
                    action: action
                ),
                surface: .notification
            )
            if result.wasApplied { await onResponse(result) }
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let promptID = response.notification.request.content.userInfo["promptID"] as? String,
              let action = Self.actionKind(
                identifier: response.actionIdentifier,
                notificationIdentity: notificationIdentity
              )
        else {
            completionHandler()
            return
        }
        do {
            let result = try promptStore.respond(
                promptID: promptID,
                action: action,
                actionToken: PromptResponseToken.make(promptID: promptID, action: action),
                surface: .notification
            )
            completionHandler()
            if result.wasApplied {
                Task { await onResponse(result) }
            }
        } catch {
            completionHandler()
        }
    }

    public static func actionIdentifier(_ action: PromptActionKind) -> String {
        actionIdentifier(action, notificationIdentity: RuntimeIdentity.production.notification)
    }

    public static func actionKind(identifier: String) -> PromptActionKind? {
        actionKind(identifier: identifier, notificationIdentity: RuntimeIdentity.production.notification)
    }

    public static func actionIdentifier(
        _ action: PromptActionKind,
        notificationIdentity: RuntimeNotificationIdentity
    ) -> String {
        notificationIdentity.promptActionPrefix + action.rawValue.uppercased()
    }

    public static func actionKind(
        identifier: String,
        notificationIdentity: RuntimeNotificationIdentity
    ) -> PromptActionKind? {
        guard identifier.hasPrefix(notificationIdentity.promptActionPrefix) else { return nil }
        return PromptActionKind(
            rawValue: String(identifier.dropFirst(notificationIdentity.promptActionPrefix.count)).lowercased()
        )
    }

    public static func fixtureActionKind(
        identifier: String,
        notificationIdentity: RuntimeNotificationIdentity
    ) -> PromptActionKind? {
        PromptActionKind(rawValue: identifier.lowercased())
            ?? actionKind(
                identifier: identifier,
                notificationIdentity: notificationIdentity
            )
    }

    public static func fixtureActionKind(
        identifier: String,
        category: String,
        notificationIdentity: RuntimeNotificationIdentity
    ) -> PromptActionKind? {
        guard let action = fixtureActionKind(
            identifier: identifier,
            notificationIdentity: notificationIdentity
        ), let category = PromptNotificationCategory(rawValue: category) else { return nil }
        let allowed: Set<PromptActionKind> = switch category {
        case .planReady: [.acceptPlan, .reviewPlan, .snoozePlanning, .dismissPlanning, .workUnplanned]
        case .meetingCandidate: [.addMeeting, .editMeeting, .ignore]
        case .planChanged: [.reviewPlan, .undoPlanChange]
        case .wakeIntervention: []
        case .onboardingTest: [.continueIntentionally, .ignore]
        case .gamingDrift: [.returnToActiveTask, .fiveMoreMinutes, .startBreak, .continueIntentionally]
        }
        return allowed.contains(action) ? action : nil
    }

    private static func categories(
        notificationIdentity: RuntimeNotificationIdentity
    ) -> Set<UNNotificationCategory> {
        [
            UNNotificationCategory(
                identifier: notificationIdentity.promptCategoryIdentifier(PromptNotificationCategory.planReady.rawValue),
                actions: [
                    action(.acceptPlan, title: "Accept", notificationIdentity: notificationIdentity),
                    action(.reviewPlan, title: "Plan now", foreground: true, notificationIdentity: notificationIdentity),
                    action(.snoozePlanning, title: "Snooze 15 min", notificationIdentity: notificationIdentity),
                    action(.dismissPlanning, title: "Dismiss for now", notificationIdentity: notificationIdentity)
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: notificationIdentity.promptCategoryIdentifier(PromptNotificationCategory.meetingCandidate.rawValue),
                actions: [
                    action(.addMeeting, title: "Add", notificationIdentity: notificationIdentity),
                    action(.editMeeting, title: "Edit", foreground: true, notificationIdentity: notificationIdentity),
                    action(.ignore, title: "Ignore", notificationIdentity: notificationIdentity)
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: notificationIdentity.promptCategoryIdentifier(PromptNotificationCategory.planChanged.rawValue),
                actions: [
                    action(.reviewPlan, title: "Review", foreground: true, notificationIdentity: notificationIdentity),
                    action(.undoPlanChange, title: "Undo", notificationIdentity: notificationIdentity)
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: notificationIdentity.promptCategoryIdentifier(PromptNotificationCategory.wakeIntervention.rawValue),
                actions: [],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: notificationIdentity.promptCategoryIdentifier(PromptNotificationCategory.onboardingTest.rawValue),
                actions: [
                    action(.continueIntentionally, title: "Continue Setup", foreground: true, notificationIdentity: notificationIdentity),
                    action(.ignore, title: "Use Today", foreground: true, notificationIdentity: notificationIdentity)
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: notificationIdentity.promptCategoryIdentifier(PromptNotificationCategory.gamingDrift.rawValue),
                actions: [
                    action(.returnToActiveTask, title: "Return to task", foreground: true, notificationIdentity: notificationIdentity),
                    action(.fiveMoreMinutes, title: "Five more minutes", notificationIdentity: notificationIdentity),
                    action(.startBreak, title: "Take a break", notificationIdentity: notificationIdentity),
                    action(.continueIntentionally, title: "Continue intentionally", notificationIdentity: notificationIdentity)
                ],
                intentIdentifiers: []
            )
        ]
    }

    private static func action(
        _ kind: PromptActionKind,
        title: String,
        foreground: Bool = false,
        notificationIdentity: RuntimeNotificationIdentity
    ) -> UNNotificationAction {
        UNNotificationAction(
            identifier: actionIdentifier(kind, notificationIdentity: notificationIdentity),
            title: title,
            options: foreground ? [.foreground] : []
        )
    }
}

extension PromptNotificationCoordinator: AcceptedBreakReminderScheduling {}
