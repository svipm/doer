import Foundation

final class MessagesViewModel: DoerObservableObject {
    var messages: [DiscourseTopicList.Topic] = []
    var usersById: [Int: DiscourseTopicList.User] = [:]
    var selectedFilter: PrivateMessageFilter = .inbox
    var isLoading = false
    var errorMessage: String?
    var requiresLogin = false

    private let api: DiscourseAPI

    init(api: DiscourseAPI) {
        self.api = api
    }

    private var loadGeneration = 0

    func loadMessages(username: String, filter: PrivateMessageFilter? = nil) async {
        if let filter {
            selectedFilter = filter
        }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        requiresLogin = false
        notifyChanged()
        do {
            let result = try await api.fetchPrivateMessages(username: username, filter: selectedFilter)
            // A newer filter/load superseded this one — a stale response must
            // not overwrite the fresh list (or "已发送" would show inbox data).
            guard generation == loadGeneration else { return }
            messages = result.topicList.topics
            usersById = Dictionary(uniqueKeysWithValues: (result.users ?? []).map { ($0.id, $0) })
        } catch {
            guard generation == loadGeneration else { return }
            if AuthSessionInvalidationPolicy.shouldInvalidateWebSession(error: error, baseURL: api.baseURL) {
                requiresLogin = true
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
        notifyChanged()
    }

    func avatarURL(for topic: DiscourseTopicList.Topic, baseURL: String) -> URL? {
        guard let userId = topic.posters?.first?.userId,
              let template = usersById[userId]?.avatarTemplate else { return nil }
        return AvatarImageLoader.url(from: template, baseURL: baseURL, size: AvatarImageLoader.primaryAvatarPixelSize)
    }
}
