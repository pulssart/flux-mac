// NewsletterScheduleSheet.swift
import SwiftUI

struct NewsletterScheduleSheet: View {
    @Environment(FeedService.self) private var feedService
    @Binding var isPresented: Bool
    private let lm = LocalizationManager.shared

    @State private var slots: [(enabled: Bool, time: Date)] = {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let times = [(9,0), (12,0), (19,0)].compactMap { h, m in
            cal.date(bySettingHour: h, minute: m, second: 0, of: base)
        }
        return times.map { (true, $0) }
    }()

    private func defaultTimes() -> [Date] {
        let cal = Calendar.current
        let now = Date()
        let base = cal.startOfDay(for: now)
        let hms = [(9,0), (12,0), (19,0)]
        return hms.compactMap { h, m in cal.date(bySettingHour: h, minute: m, second: 0, of: base) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lm.localizedString(.scheduleNewsletter)).font(.title3).bold()
            Text(lm.localizedString(.scheduleNewsletterDescription))
                .font(.callout).foregroundStyle(.secondary)
            ForEach(0..<3, id: \.self) { idx in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(get: { slots[idx].enabled }, set: { slots[idx].enabled = $0 }))
                        .labelsHidden()
                    DatePicker("", selection: Binding(get: { slots[idx].time }, set: { slots[idx].time = $0 }), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(!slots[idx].enabled)
                }
            }
            Text(lm.localizedString(.scheduleNewsletterNotification))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(lm.localizedString(.cancel)) { isPresented = false }
                Button(lm.localizedString(.save)) { save() }.buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(18)
        .frame(width: 420)
        .onAppear { load() }
    }

    private func load() {
        let cal = Calendar.current
        func dcToDate(_ dc: DateComponents) -> Date {
            let base = cal.startOfDay(for: Date())
            return cal.date(bySettingHour: dc.hour ?? 9, minute: dc.minute ?? 0, second: 0, of: base) ?? base
        }
        // FeedService n'expose pas directement les heures; on lit UserDefaults comme lui
        let d = UserDefaults.standard
        if let arr = d.array(forKey: "newsletter.schedule") as? [[String: Int]], !arr.isEmpty {
            let times = arr.compactMap { dict -> Date? in
                guard let h = dict["h"], let m = dict["m"] else { return nil }
                var c = DateComponents(); c.hour = h; c.minute = m
                return dcToDate(c)
            }
            slots = times.prefix(3).map { (true, $0) }
        }
        if slots.isEmpty {
            slots = defaultTimes().map { (true, $0) }
        }
        // Remplir jusqu'à 3
        while slots.count < 3 { slots.append((false, defaultTimes()[slots.count])) }
    }

    private func save() {
        let cal = Calendar.current
        let enabled = slots.filter { $0.enabled }.prefix(3)
        let components: [DateComponents] = enabled.map { dateTuple in
            let comps = cal.dateComponents([.hour, .minute], from: dateTuple.time)
            return comps
        }
        feedService.updateNewsletterSchedule(times: components)
        isPresented = false
    }
}


