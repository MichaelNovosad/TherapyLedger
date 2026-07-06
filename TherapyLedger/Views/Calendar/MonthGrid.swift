import SwiftUI

struct MonthGrid: View {
    let month: Date
    @Binding var selectedDate: Date
    let sessionsByDay: [Date: [TherapySession]]

    private var calendar: Calendar { .current }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Cells for a 6-row grid; `nil` for leading/trailing blanks.
    private var dayCells: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = monthInterval.start
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: day, to: firstDay))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                // veryShortWeekdaySymbols repeat ("S", "T"), so key by position.
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(dayCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(
                            date: day,
                            isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(day),
                            statuses: dayStatuses(for: day)
                        )
                        .onTapGesture {
                            selectedDate = day
                        }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }

    private func dayStatuses(for day: Date) -> [SessionStatus] {
        let sessions = sessionsByDay[calendar.startOfDay(for: day)] ?? []
        return sessions.prefix(4).map(\.status)
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let statuses: [SessionStatus]

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                .frame(width: 30, height: 30)
                .background {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else if isToday {
                        Circle().stroke(Color.accentColor, lineWidth: 1.5)
                    }
                }
            HStack(spacing: 2) {
                ForEach(Array(statuses.enumerated()), id: \.offset) { _, status in
                    Circle()
                        .fill(status.tint)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
    }
}
