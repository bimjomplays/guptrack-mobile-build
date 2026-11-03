import SwiftUI

/// The calendar (09, 10), pushed from Home's calendar button. Week: past days folded to one line, today tinted with
/// a now line, the days ahead in full. Month: a grid with a dot per status airing that day; tap a day to list it.
/// GET calendar answers a month at a time (only titles you follow, and sequels to them); statuses come from the
/// offline library, else the list entries the answer came with.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: AiringSchedule.Mode = .week
    @State private var anchor: Date = Clock.now
    /// the month view's tapped day
    @State private var selected: Date = Clock.now
    @State private var filter = AiringSchedule.Filter()
    /// loaded months ("2026-11") and their answers
    @State private var months: [String: CalendarData] = [:]
    @State private var failed: String?
    /// past days opened in the week view (day keys)
    @State private var opened: Set<String> = []

    private var neededMonths: [Date] { AiringSchedule.monthsToLoad(anchor, mode: mode) }
    private var needed: [String] { neededMonths.map { AiringSchedule.monthKey($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                controls
                Hairline()
                page
            }
            .padding(.bottom, 40)
        }
        .pageBackground()
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { goToday() }
            }
        }
        .task(id: needed.joined(separator: ",")) { await load(neededMonths) }
        .refreshable {
            months = [:]
            await load(neededMonths)
        }
    }

    // MARK: the controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("View", selection: $mode) {
                ForEach(AiringSchedule.Mode.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.pad)
            .padding(.top, 8)
            pager.padding(.top, 14)
            CalendarFilters(filter: $filter).padding(.top, 10).padding(.bottom, 14)
        }
    }

    private var pager: some View {
        HStack(spacing: 8) {
            Text(mode == .week ? AiringSchedule.weekLabel(AiringSchedule.weekStart(anchor)) : AiringSchedule.monthLabel(anchor))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .numbers()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            PagerButton(symbol: "chevron.left", label: mode == .week ? "Previous week" : "Previous month") { move(-1) }
            PagerButton(symbol: "chevron.right", label: mode == .week ? "Next week" : "Next month") { move(1) }
        }
        .padding(.horizontal, Theme.pad)
        .frame(height: 36)
    }

    // MARK: the page under them

    @ViewBuilder
    private var page: some View {
        if needed.allSatisfy({ months[$0] != nil }) {
            let data = CalendarData.merged(needed.compactMap { months[$0] })
            let rows = AiringSchedule.rows(data, library: model.library, filter: filter)
            if mode == .week {
                WeekList(days: AiringSchedule.days(rows, on: AiringSchedule.weekDays(AiringSchedule.weekStart(anchor))),
                         opened: $opened)
            } else {
                MonthPanel(month: anchor, rows: rows, selected: $selected)
            }
        } else if let failed {
            ContentUnavailableView {
                Label("Couldn't load the calendar", systemImage: "wifi.exclamationmark")
            } description: {
                Text(failed)
            } actions: {
                Button("Try again") { Task { await load(neededMonths) } }.buttonStyle(.capsule(.tone, .small))
            }
            .padding(.top, 30)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
        }
    }

    // MARK: actions

    private func move(_ n: Int) {
        anchor = AiringSchedule.shift(anchor, mode: mode, by: n)
        if mode == .month {
            selected = AiringSchedule.monthKey(Clock.now) == AiringSchedule.monthKey(anchor) ? Clock.now : anchor
        }
    }

    private func goToday() {
        anchor = Clock.now
        selected = Clock.now
    }

    private func load(_ starts: [Date]) async {
        for m in starts where months[AiringSchedule.monthKey(m)] == nil {
            switch await model.fetch({ try await $0.calendar(month: m) }) {
            case .loaded(let s):
                months[AiringSchedule.monthKey(m)] = s
                failed = nil
            case .failed(let why):
                failed = why
            case .loading:
                break
            }
        }
    }
}

/// a round chevron button beside the week or month label (content, so a plain fill rather than glass)
private struct PagerButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Theme.fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// All types (a menu), then a chip per status; the mockups start on Watching + Planning.
private struct CalendarFilters: View {
    @Binding var filter: AiringSchedule.Filter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Type", selection: $filter.media) {
                        Text("All types").tag(MediaKind?.none)
                        ForEach(AiringSchedule.Filter.kinds) { k in
                            Label(k.plural, systemImage: k.symbol).tag(MediaKind?.some(k))
                        }
                    }
                } label: {
                    ChipLabel(text: filter.mediaLabel, on: filter.media != nil, menu: true,
                              symbol: "square.3.layers.3d")
                }
                .buttonStyle(.plain)
                ForEach(AiringSchedule.Show.allCases) { s in
                    let on = filter.shows.contains(s)
                    Button {
                        filter.toggle(s)
                    } label: {
                        ChipLabel(text: s.label, on: on)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: week

/// The week's seven days: past ones folded (tap to open), today tinted with the now line, the rest in full.
private struct WeekList: View {
    let days: [AiringSchedule.Day]
    @Binding var opened: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(days) { day in
                if AiringSchedule.isPast(day.date) && !opened.contains(day.id) {
                    FoldedDay(day: day) { opened.insert(day.id) }
                } else if AiringSchedule.isToday(day.date) {
                    TodayBlock(day: day).padding(.top, 8).padding(.bottom, 8)
                } else {
                    FullDay(day: day, past: AiringSchedule.isPast(day.date)) {
                        if AiringSchedule.isPast(day.date) { opened.remove(day.id) }
                    }
                }
            }
        }
    }
}

/// a finished day on one line: the day, up to four overlapping covers, the count, a chevron
private struct FoldedDay: View {
    let day: AiringSchedule.Day
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Text(AiringSchedule.dayLabel(day.date))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 96, alignment: .leading)
                HStack(spacing: -6) {
                    ForEach(day.rows.prefix(4)) { r in
                        Poster(url: r.item.cover, width: 20, radius: 4, flat: true)
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Theme.sheet, lineWidth: 1.5))
                    }
                }
                Spacer(minLength: 8)
                Text(AiringSchedule.countLabel(day.rows))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkFaint)
                    .numbers()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, Theme.pad)
            .frame(height: 44)
            .overlay(alignment: .bottom) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows this day")
    }
}

/// a day's heading: "Tue, Nov 3" (today in brand with a Today tag), the count on the right
private struct DayHead: View {
    let label: String
    let rows: [AiringSchedule.Row]
    var today = false
    var past = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(today ? Theme.brandSoft : past ? Theme.inkMuted : Theme.ink)
            if today {
                Text("Today")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Theme.brand, in: Capsule())
            }
            Spacer(minLength: 8)
            Text(AiringSchedule.countLabel(rows))
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .numbers()
        }
        .padding(.horizontal, Theme.pad)
        .frame(height: 38)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// a day ahead (or an opened past day; tapping its heading folds it again)
private struct FullDay: View {
    let day: AiringSchedule.Day
    var past = false
    let fold: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DayHead(label: AiringSchedule.dayLabel(day.date), rows: day.rows, past: past)
                .contentShape(Rectangle())
                .onTapGesture { fold() }
            ForEach(Array(day.rows.enumerated()), id: \.element.id) { i, r in
                AirRow(row: r, separator: i < day.rows.count - 1)
            }
        }
        .padding(.bottom, 8)
    }
}

/// today: a faint brand tint with a brand bar on the left, Out on what has aired, the now line in its place
private struct TodayBlock: View {
    let day: AiringSchedule.Day

    var body: some View {
        let split = AiringSchedule.nowIndex(day.rows)
        VStack(alignment: .leading, spacing: 0) {
            DayHead(label: AiringSchedule.dayLabel(day.date), rows: day.rows, today: true)
            ForEach(Array(day.rows.enumerated()), id: \.element.id) { i, r in
                if i == split { NowLine() }
                AirRow(row: r, out: AiringSchedule.isOut(r), separator: i < day.rows.count - 1 && i + 1 != split)
            }
            if split == day.rows.count && !day.rows.isEmpty { NowLine() }
        }
        .padding(.bottom, 4)
        .background(Theme.brand.opacity(0.06))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.brand).frame(width: 3) }
    }
}

/// the red line at the current time: "9:41 AM", a dot, a hairline to the edge
private struct NowLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Text(Format.time(Clock.now))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.danger)
                .numbers()
                .lineLimit(1)
                .fixedSize()
                .frame(width: 70, alignment: .leading)
            Circle().fill(Theme.danger).frame(width: 8, height: 8)
            Rectangle().fill(Theme.danger).frame(height: 1)
        }
        .padding(.horizontal, Theme.pad)
        .frame(height: 8)
        .padding(.vertical, -4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, \(Format.time(Clock.now))")
    }
}

/// One airing: time (All day when TMDB knows only the day), cover, title, "Episode 5 · Finale · ● Watching", Out
/// once it has aired. A tap opens the title.
private struct AirRow: View {
    let row: AiringSchedule.Row
    var out = false
    var separator = true

    @Environment(AppModel.self) private var model

    var body: some View {
        let item = row.item
        HStack(spacing: 12) {
            Text(AiringSchedule.timeLabel(item))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(out ? Theme.inkFaint : Theme.inkSoft)
                .numbers()
                .lineLimit(1)
                .frame(width: 62, alignment: .leading)
            Poster(url: item.cover, width: 36, radius: 6, flat: true)
                .padding(.vertical, 6)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    caption
                }
                Spacer(minLength: 0)
                if out {
                    Label("Out", systemImage: "checkmark")
                        .labelStyle(TightOutLabel())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.color(.current))
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.horizontal, Theme.pad)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture { model.open(.title(item.titleId)) }
        .contextMenu {
            if let e = model.entry(item.titleId) { EntryMenu(entry: e) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var caption: some View {
        HStack(spacing: 6) {
            Text(AiringSchedule.detail(row.item))
            Text("·")
            if let s = row.status {
                StatusDot(status: s, size: 6)
            } else {
                Circle().fill(Theme.inkFaint).frame(width: 6, height: 6)
            }
            Text(AiringSchedule.statusLabel(row.status, media: row.item.titleKind))
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.inkMuted)
        .lineLimit(1)
    }
}

/// the check and "Out" 3pt apart
private struct TightOutLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: month

/// The month grid (S M T W T F S), a legend of the statuses that air, then the tapped day's list.
private struct MonthPanel: View {
    let month: Date
    let rows: [AiringSchedule.Row]
    @Binding var selected: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let day = AiringSchedule.days(rows, on: [selected])[0]
        VStack(alignment: .leading, spacing: 0) {
            grid.padding(.horizontal, 14).padding(.top, 10)
            legend.padding(.horizontal, Theme.pad).padding(.top, 8).padding(.bottom, 12)
            Hairline()
            DayHead(label: AiringSchedule.longDayLabel(selected), rows: day.rows)
            ForEach(Array(day.rows.enumerated()), id: \.element.id) { i, r in
                AirRow(row: r, out: AiringSchedule.isToday(selected) && AiringSchedule.isOut(r),
                       separator: i < day.rows.count - 1)
            }
        }
    }

    private var grid: some View {
        let cells = AiringSchedule.monthGrid(month)
        let byDay = Dictionary(grouping: rows) { Format.day($0.item.date) }
        return VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(AiringSchedule.weekdayLetters.enumerated()), id: \.offset) { _, w in
                    Text(w).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                        .frame(height: 22)
                }
            }
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, d in
                    if let d {
                        DayCell(date: d, dots: AiringSchedule.dots(byDay[Format.day(d)] ?? []),
                                selected: Format.day(d) == Format.day(selected)) { selected = d }
                    } else {
                        Color.clear.frame(height: 52)
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(Array(AiringSchedule.legend(rows).enumerated()), id: \.offset) { _, s in
                HStack(spacing: 5) {
                    if let s { StatusDot(status: s, size: 6) } else { Circle().fill(Theme.inkFaint).frame(width: 6, height: 6) }
                    Text(AiringSchedule.statusLabel(s, media: .anime))
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.inkMuted)
        .lineLimit(1)
    }
}

/// one day of the grid: the number (today in brand, the tapped day in a white circle), its status dots
private struct DayCell: View {
    let date: Date
    let dots: [ListStatus?]
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        let today = AiringSchedule.isToday(date)
        let past = AiringSchedule.isPast(date)
        Button(action: tap) {
            VStack(spacing: 4) {
                Text("\(Clock.calendar.component(.day, from: date))")
                    .font(.system(size: 17, weight: selected || today ? .bold : .medium))
                    .numbers()
                    .foregroundStyle(selected ? Color.black : today ? Theme.brandSoft : past ? Theme.inkMuted : Theme.ink)
                    .frame(width: 34, height: 34)
                    .background { if selected { Circle().fill(Color.white) } }
                HStack(spacing: 3) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, s in
                        Circle().fill(s.map { Theme.color($0) } ?? Theme.inkFaint).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 52, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ScheduleWords.format("MMMM d", date))
        .accessibilityValue(dots.isEmpty ? "Nothing airing" : "\(dots.count) statuses airing")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
