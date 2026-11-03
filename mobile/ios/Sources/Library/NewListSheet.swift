import SwiftUI

/// A new custom list (40): Name, Description (optional), who can see it. ✓ makes it and opens it.
struct NewListSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            NewListForm(item: nil, cancel: { model.sheet = nil }) { list in
                model.sheet = nil
                model.open(.customList(list.id))
            }
        }
        .presentationDetents([.medium])
    }
}

/// The new-list form, in its own sheet or pushed inside Add to list (26 → 40) with the title to put on it.
struct NewListForm: View {
    /// put on the new list straight away (POST lists' `item`)
    let item: Title?
    /// nil: the ✕ is the navigation stack's back button
    var cancel: (() -> Void)?
    let done: (CustomList) -> Void

    @Environment(AppModel.self) private var model
    @State private var draft = CustomListDraft()
    @State private var saving = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                label("Name")
                TextField("Name", text: $draft.name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .modifier(NewListField())
                label("Description (optional)").padding(.top, 18)
                TextField("What ties these together", text: $draft.description)
                    .modifier(NewListField())
                label("Who can see it").padding(.top, 18)
                Picker("Who can see it", selection: $draft.visibility) {
                    ForEach(Visibility.allCases) { v in
                        Text(v.label).tag(v)
                    }
                }
                .pickerStyle(.segmented)
                Text(draft.visibility.listFootnote)
                    .font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.sheet)
        .navigationTitle("New list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let cancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { cancel() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) { create() }
                    .disabled(!draft.isValid || saving)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            .padding(.bottom, 8)
    }

    private func create() {
        saving = true
        Task {
            if let list = await CustomListActions.create(draft, item: item, model: model) { done(list) }
            saving = false
        }
    }
}

/// the sheet's filled text field: 50 high, rounded 14 (40)
private struct NewListField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 17))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
