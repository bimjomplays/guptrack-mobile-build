import SwiftUI

/// The page for a route on any tab's stack.
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .notifications: NotificationsView()
        case .calendar: CalendarView()
        case .seasonChart: SeasonChartView()
        case .search(let q): SearchResultsView(query: q)
        case .title(let id): TitleView(id: id)
        case .season(let id, let n): SeasonView(titleId: id, number: n)
        case .reviews(let id): ReviewsView(titleId: id)
        case .review(let id): ReviewView(id: id)
        case .character(let id): CharacterView(id: id)
        case .person(let id): PersonView(id: id)
        case .studio(let id): StudioView(id: id)
        case .author(let id): AuthorView(id: id)
        case .list(let media): LibraryListView(media: media)
        case .customList(let id): CustomListView(id: id)
        case .stats: StatsView()
        case .user(let name): UserProfileView(username: name)
        case .compare(let name): CompareView(username: name)
        case .friends: FriendsView()
        case .activity(let id): ActivityView(id: id)
        case .conversation(let id): ConversationView(id: id)
        case .messageRequest(let id): MessageRequestView(id: id)
        case .settings: SettingsView()
        case .settingsPage(let page): SettingsPageView(page: page)
        }
    }
}

/// The sheet for a sheet route.
struct SheetView: View {
    let route: SheetRoute

    var body: some View {
        switch route {
        case .editor(let id, let expanded): EditorSheet(titleId: id, expanded: expanded)
        case .addToList(let id): AddToListSheet(titleId: id)
        case .writeReview(let id): WriteReviewSheet(titleId: id)
        case .sendTo(let id): SendToSheet(titleId: id)
        case .browseFilters(let media): BrowseFiltersSheet(media: media)
        case .newList: NewListSheet()
        case .editList(let id): EditListSheet(id: id)
        case .addFriend: AddFriendSheet()
        case .bioEditor: BioEditorSheet()
        case .newMessage: NewMessageSheet()
        }
    }
}
