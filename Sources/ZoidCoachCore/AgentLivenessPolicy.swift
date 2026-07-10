public struct AgentLivenessPolicy: Equatable, Sendable {
    public let maximumStallDuration: Duration

    public init(maximumStallDuration: Duration = .seconds(180)) {
        self.maximumStallDuration = max(.seconds(30), maximumStallDuration)
    }

    public func requiresRestart(elapsedSinceProgress: Duration) -> Bool {
        elapsedSinceProgress > maximumStallDuration
    }
}
