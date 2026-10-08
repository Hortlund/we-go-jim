import Foundation

/// Pure, deterministic celebrations reconstructed from visible, completed history.
/// PRs remain separate from badges so badges never inflate record counts.
nonisolated enum JourneyCelebrationBuilder {
    static func milestones(workouts: [JourneyWorkout], exercises: [JourneyExercise],
                           existing: [JourneyMilestone], unit: WorkoutDistanceUnit,
                           calendar: Calendar, now: Date) -> [JourneyMilestone] {
        guard let first = workouts.first else { return existing }
        var events = existing
        let eventIndex = Dictionary(events.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var awarded = Set<String>()
        func add(_ id: String, _ workout: JourneyWorkout, _ title: @autoclosure () -> String, _ detail: @autoclosure () -> String,
                 _ meme: @autoclosure () -> String, unlockedAt: Date? = nil) {
            guard awarded.insert(id).inserted else { return }
            events.append(.init(id: "celebration-\(id)", sessionID: workout.id, date: workout.date,
                kind: .celebration, title: title(), detail: detail(), playfulTitle: meme(), unlockedAt: unlockedAt))
        }
        // Give existing achievements a playful caption instead of creating duplicate badges.
        for index in events.indices {
            switch events[index].id {
            case "beginning": events[index].playfulTitle = String(localized: "Achievement unlocked: showing up")
            case "workouts-100": events[index].playfulTitle = String(localized: "The warm-up became a lifestyle")
            case "consistency-10": events[index].playfulTitle = String(localized: "We go jim. Again.")
            case "consistency-52": events[index].playfulTitle = String(localized: "Rest days were part of the plan")
            case "training-hours-24": events[index].playfulTitle = String(localized: "A day invested in you")
            case "training-hours-168": events[index].playfulTitle = String(localized: "A week invested in you")
            default: break
            }
        }
        let records = existing.filter { $0.personalRecord != nil }.sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        }
        let recordsBySession = Dictionary(grouping: records, by: \.sessionID)
        var recordCount = 0
        var lastSessionByKey: [String: UUID] = [:]
        var previousRecordSessionByKey: [String: UUID] = [:]
        var keysBySession: [UUID: Set<String>] = [:]
        let visibleIDs = Set(workouts.map(\.id))
        for exercise in exercises {
            for point in exercise.performances where visibleIDs.contains(point.sessionID) && point.value.isFinite && point.value > 0 {
                keysBySession[point.sessionID, default: []].insert("strength-\(exercise.id)")
            }
        }
        var seenExercises = Set<String>()
        var seenYears = Set<Date>()
        var foot = 0.0
        var cycling = 0.0
        var rowing = 0.0
        var previous: JourneyWorkout?
        var firstWeightRecord = false
        var firstRepRecord = false
        let repsKeys = Set(exercises.filter(\.isReps).map { "strength-\($0.id)" })
        for workout in workouts {
            let year = calendar.dateInterval(of: .year, for: workout.date)?.start ?? workout.date
            if seenYears.insert(year).inserted, workout.id != first.id {
                add("new-year-\(year.timeIntervalSince1970)", workout, String(localized: "First workout of the year"),
                    workout.date.formatted(.dateTime.year()), String(localized: "The lore continues"))
            }
            if let previous, let returnDate = calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: previous.date)),
               calendar.startOfDay(for: workout.date) >= returnDate {
                add("comeback-\(workout.id)", workout, String(localized: "Welcome back"),
                    String(localized: "Your first workout after at least 30 days away. It's good to see you."),
                    String(localized: "Back at it"))
            }
            previous = workout
            for years in [1, 2, 3, 5, 10] {
                if let anniversary = calendar.date(byAdding: .year, value: years, to: calendar.startOfDay(for: first.date)),
                   calendar.startOfDay(for: workout.date) >= anniversary {
                    add("anniversary-\(years)", workout, String(localized: "\(years)-year training anniversary"),
                        String(localized: "Celebrated with a workout. Your story started \(first.date.formatted(date: .abbreviated, time: .omitted))."),
                        String(localized: "The gains have lore now"))
                }
            }
            if workout.hasStrength && workout.hasCardio {
                add("mixed", workout, String(localized: "Your first strength + cardio workout"),
                    String(localized: "Two ways to move, one session."), String(localized: "Strength meets stamina"))
            }
            if workout.completedExercises.contains(where: \.isLegExercise) {
                add("leg-day", workout, String(localized: "Your first recorded leg exercise"),
                    String(localized: "A completed strength exercise with legs or glutes as a primary muscle group."),
                    String(localized: "Leg day has entered the chat"))
            }
            seenExercises.formUnion(workout.completedExercises.map(\.id))
            seenExercises.formUnion(workout.activities.map(\.exerciseID))
            for count in [3, 5, 10] where seenExercises.count >= count {
                add("variety-\(count)", workout, String(localized: "\(count) different exercises tried"),
                    String(localized: "Across your completed workouts."), String(localized: "Mixing it up"))
            }
            for activity in workout.activities {
                let firstID = "first-cardio-\(activity.exerciseID)"
                if let index = eventIndex[firstID], events[index].sessionID == workout.id {
                    events[index].playfulTitle = String(localized: "Side quest unlocked")
                }
                guard activity.distanceMeters.isFinite, activity.distanceMeters > 0,
                      activity.trackingProfile != .timeOnly, activity.trackingProfile != .stairClimber else { continue }
                if activity.isWalkRun { foot += activity.distanceMeters }
                if activity.isCycling { cycling += activity.distanceMeters }
                if activity.trackingProfile == .rower { rowing += activity.distanceMeters }
                let baseKey = "cardio-\(activity.exerciseID)-\(activity.trackingProfile.rawValue)"
                keysBySession[workout.id, default: []].insert("\(baseKey)-distance")
                if activity.distanceMeters >= 1_000 && activity.durationSeconds > 0 {
                    keysBySession[workout.id, default: []].insert("\(baseKey)-speed")
                }
            }
            for (meters, name, meme) in [(21_097.5, String(localized: "A half marathon in total"), String(localized: "Half marathon. Full commitment.")),
                                        (42_195.0, String(localized: "A marathon in total"), String(localized: "That's a marathon!")),
                                        (100_000.0, String(localized: "100 km on foot in total"), String(localized: "You've walked into another postcode"))] where foot >= meters {
                // The ordinary 100 km milestone already represents this achievement in metric units.
                if meters == 100_000, unit != .miles,
                   let index = eventIndex["total-distance-kilometers-100.0"] {
                    events[index].playfulTitle = meme
                } else {
                    add("foot-\(Int(meters))", workout, name,
                        String(localized: "Accumulated walking and running across workouts, not a single outing."), meme)
                }
            }
            if cycling >= 100_000 {
                add("cycling-100km", workout, String(localized: "100 km of cycling in total"),
                    String(localized: "Accumulated across your cycling workouts."), String(localized: "Tour de You"))
            }
            if rowing >= 50_000 {
                add("rowing-50km", workout, String(localized: "50 km of rowing in total"),
                    String(localized: "Accumulated across your rowing workouts."), String(localized: "Oar-some behaviour"))
            }
            let sessionRecords = recordsBySession[workout.id, default: []]
            let distinct = Set(sessionRecords.compactMap(\.recordKey))
            if distinct.count >= 3 {
                add("pr-printer", workout, String(localized: "Three PRs in one workout"),
                    String(localized: "At least three distinct exercise and record-type bests in one session."), String(localized: "PR printer goes brrr"))
            }
            for record in sessionRecords {
                guard let key = record.recordKey else { continue }
                if lastSessionByKey[key] != nil, lastSessionByKey[key] == previousRecordSessionByKey[key] {
                    add("sequel", workout, String(localized: "Back-to-back breakthroughs"),
                        String(localized: "You beat a PR from your previous completed session for the same exercise and metric."),
                        String(localized: "The sequel was stronger"))
                }
                previousRecordSessionByKey[key] = workout.id
                if record.kind == .strength {
                    let reps = repsKeys.contains(key)
                    if (reps && !firstRepRecord) || (!reps && !firstWeightRecord),
                       let index = eventIndex[record.id] {
                        events[index].playfulTitle = reps ? String(localized: "Same human. More horsepower.")
                            : String(localized: "Gravity filed a complaint")
                    }
                    if reps { firstRepRecord = true } else { firstWeightRecord = true }
                }
            }
            for key in keysBySession[workout.id, default: []] { lastSessionByKey[key] = workout.id }
            recordCount += sessionRecords.count
            for count in [10, 25, 50, 100] where recordCount >= count {
                add("records-\(count)", workout, String(localized: "\(count) Journey PRs"),
                    String(localized: "Individual strength and cardio records across your journey."), String(localized: "A collection of breakthroughs"))
            }
        }
        let byID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for exercise in exercises {
            let points = exercise.performances.filter { visibleIDs.contains($0.sessionID) && $0.value.isFinite && $0.value > 0 }
                .sorted { $0.date == $1.date ? $0.sessionID.uuidString < $1.sessionID.uuidString : $0.date < $1.date }
            guard let baseline = points.first else { continue }
            for point in points.dropFirst() {
                guard let workout = byID[point.sessionID] else { continue }
                for percent in [25, 50, 100] where point.value / baseline.value >= 1 + Double(percent) / 100 {
                    add("improvement-\(exercise.id)-\(percent)", workout,
                        String(localized: "\(exercise.name): \(percent)% above your starting point"),
                        exercise.isReps ? String(localized: "Compared with your first recorded bodyweight-rep result.")
                            : String(localized: "Compared with your first recorded weight result for this exercise."),
                        String(localized: "Look how far you've come"))
                }
            }
        }
        let months = Dictionary(grouping: workouts) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        var bestMonthDays = 0
        for month in months.keys.sorted() {
            let sessions = months[month, default: []]
            var activeDays = Set<Date>()
            for workout in sessions {
                activeDays.insert(calendar.startOfDay(for: workout.date))
                for count in [5, 10, 15, 20] where activeDays.count >= count {
                    add("rhythm-\(count)", workout, String(localized: "\(count) active days in a month"),
                        String(localized: "The first month you reached this milestone. Each day counts once."), String(localized: "Finding your rhythm"))
                }
            }
            guard let end = calendar.dateInterval(of: .month, for: month)?.end, end <= now,
                  let last = sessions.last else { continue }
            if bestMonthDays > 0 && activeDays.count > bestMonthDays {
                add("best-month-\(month.timeIntervalSince1970)", last, String(localized: "Your most active month yet"),
                    String(localized: "\(month.formatted(.dateTime.month(.wide).year())): \(activeDays.count) active days, beating your previous best of \(bestMonthDays)."),
                    String(localized: "Your strongest month yet"), unlockedAt: end)
            }
            bestMonthDays = max(bestMonthDays, activeDays.count)
            if sessions.contains(where: \.hasStrength), sessions.contains(where: \.hasCardio),
               sessions.contains(where: { !recordsBySession[$0.id, default: []].isEmpty }) {
                add("montage", last, String(localized: "A month of strength, cardio and PRs"),
                    month.formatted(.dateTime.month(.wide).year()), String(localized: "Main character training montage"), unlockedAt: end)
            }
        }
        return events
    }
}
