public struct NoteCandidate: Equatable, Sendable {
    public let id: String
    public let attachments: Int
    public let body: String

    public init(id: String, attachments: Int, body: String) {
        self.id = id
        self.attachments = attachments
        self.body = body
    }
}
