import Foundation

/// A model call that turns text into text (Refine, Translate, Ask).
public protocol TextRefining: AnyObject {
    func refine(_ text: String) async throws -> String
    func dispose()
}

public extension TextRefining {
    func dispose() {}
}
