import SwiftUI

/// Season chart (14): this anime season by format, each row with its airing line and your status (or Plan to Watch).
/// The seasons either side are a tap away; sort and "hide what's on my list" sit in the toolbar.
struct SeasonChartView: View {
    @Environment(AppModel.self) private var model
    @State private var season = SeasonChart.Ref.current
    @State private var kind: SeasonChart.Kind = .all
    @State private var order: SeasonChart.Order = .popularity
    @State private var hideListed = false

    var body: some View {
        ScrollView {
            PageLoader(id: season.slug, load: { [season] api in try await api.seasonChart(season) }) { chart in
                chartBody(chart)
            }
        }
        .pageBackground()
        .navigationTitle(season.label)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { sortMenu }
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
        }
        .onChange(of: season) { kind = .all }
    }

    private func chartBody(_ chart: SeasonChart) -> some View {
        let hide = hideListed ? Set(model.library.map(\.id)) : []
        let groups = chart.groups(kind, order: order, hide: hide)
        return VStack(alignment: .leading, spacing: 0) {
            Text(chart.subtitle)
                .font(.system(size: 15)).foregroundStyle(Theme.inkMuted).numbers()
                .padding(.horizontal, Theme.pad)
            seasonRow.padding(.top, 10)
            kindPicker(chart).padding(.top, 16)
            if groups.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "calendar",
                                       description: Text(hideListed ? "Everything here is on your list." : "No anime this season yet."))
                    .padding(.top, 40)
            }
            ForEach(groups) { g in
                group(g).padding(.top, 26)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 40)
    }

    private var seasonRow: some View {
        HStack {
            Button {
                season = season.previous
            } label: {
                Label(season.previous.label, systemImage: "chevron.left")
            }
            Spacer()
            Button {
                season = season.next
            } label: {
                HStack(spacing: 4) {
                    Text(season.next.label)
                    Image(systemName: "chevron.right")
                }
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Theme.brandSoft)
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pad)
    }

    private func kindPicker(_ chart: SeasonChart) -> some View {
        Picker("Format", selection: $kind) {
            ForEach(chart.kinds, id: \.0) { item in
                Text("\(item.0.label) \(item.1)").tag(item.0)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.pad)
    }

    private func group(_ g: SeasonChart.Group) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(g.label).font(.section).foregroundStyle(Theme.ink)
                Text(String(g.titles.count)).font(.system(size: 15)).foregroundStyle(Theme.inkMuted).numbers()
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
            LazyVStack(spacing: 0) {
                ForEach(Array(g.titles.enumerated()), id: \.element.id) { i, t in
                    BrowseTitleRow(title: t, separator: i < g.titles.count - 1)
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $order) {
                ForEach(SeasonChart.Order.allCases) { o in Text(o.label).tag(o) }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort")
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Hide what's on my list", isOn: $hideListed)
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("Filter")
    }
}
