public enum ExitCode: Int32, Sendable {
    case success = 0
    case unknown = 1
    case configuration = 2
    case microphone = 3
    case providerAuth = 4
    case providerNetwork = 5
    case providerProtocol = 6
}
