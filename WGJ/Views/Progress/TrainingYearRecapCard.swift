import SwiftUI
import UIKit

@MainActor
enum TrainingYearRecapRenderer {
    static let canvasSize = TrainingShareImageRenderer.canvasSize

    static func render(_ recap: TrainingYearRecap) -> UIImage? {
        TrainingShareImageRenderer.render(TrainingYearRecapCard(recap: recap))
    }
}

struct TrainingYearRecapCard: View {
    let recap: TrainingYearRecap

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.025, green: 0.045, blue: 0.085),
                Color(red: 0.025, green: 0.13, blue: 0.21), Color(red: 0.02, green: 0.05, blue: 0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 0) {
                brand
                HStack(alignment: .top) {
                    Text("My year\nin training.")
                        .font(.system(size: 30, weight: .bold, design: .rounded)).lineSpacing(-2)
                        .lineLimit(2).minimumScaleFactor(0.8)
                    Spacer(minLength: 12)
                    Text(recap.yearTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(WGJTheme.accentCyan).multilineTextAlignment(.trailing)
                        .lineLimit(2).minimumScaleFactor(0.45).frame(width: 126, alignment: .trailing)
                }.padding(.top, 24)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(recap.workoutCount.formatted())
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .foregroundStyle(WGJTheme.accentCyan).lineLimit(1).minimumScaleFactor(0.6)
                    Text("WORKOUTS").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
                        .foregroundStyle(.white.opacity(0.6))
                }.padding(.top, 12)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    alignment: .leading, spacing: 14) {
                    metric(JourneyFormatting.time(recap.durationSeconds), label: "TRAINING TIME")
                    metric(recap.activeDays.formatted(), label: "ACTIVE DAYS")
                    metric(JourneyFormatting.distance(recap.walkRunDistanceMeters, unit: recap.distanceUnit), label: "WALKING & RUNNING")
                    metric(recap.trainingWeeks.formatted(), label: "TRAINING WEEKS")
                }.padding(.top, 12)
                monthlyChart.padding(.top, 26)
                if let month = recap.busiestMonth {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "calendar.badge.checkmark").foregroundStyle(WGJTheme.accentCyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Busiest month · \(month)").font(.system(size: 11, weight: .semibold, design: .rounded))
                                .lineLimit(2).minimumScaleFactor(0.8)
                            Text("^[\(recap.busiestMonthWorkoutCount) workout](inflect: true)")
                                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                        }
                    }.padding(.top, 20)
                }
                if let highlight = recap.highlight {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(WGJTheme.accentCyan)
                        Text(highlight).font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(2).minimumScaleFactor(0.75)
                    }.padding(.top, 14)
                }
                Spacer(minLength: 12)
            }.padding(28)
        }.foregroundStyle(.white).clipped()
    }

    private var brand: some View {
        HStack(spacing: 9) {
            Image("SplashIcon").resizable().scaledToFit().frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("WE GO JIM").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.5)
                Text("MY YEAR IN TRAINING").font(.system(size: 7, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func metric(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(.white.opacity(0.45))
        }
    }

    private var monthlyChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WORKOUTS THROUGH THE YEAR").font(.system(size: 8, weight: .bold)).tracking(1)
                .foregroundStyle(.white.opacity(0.55))
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(recap.months) { month in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(month.workoutCount > 0 ? WGJTheme.accentCyan : .white.opacity(0.1))
                            .frame(height: max(2, 58 * Double(month.workoutCount) / Double(max(1, recap.months.map(\.workoutCount).max() ?? 1))))
                        Text(month.label).font(.system(size: 6, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5)).lineLimit(1).minimumScaleFactor(0.6)
                    }.frame(maxWidth: .infinity, alignment: .bottom)
                }
            }.frame(height: 76, alignment: .bottom)
            Text("^[\(recap.milestoneCount) milestone](inflect: true) along the way")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
        }
    }
}

#Preview("Year recap") {
    TrainingYearRecapCard(recap: TrainingYearRecap(yearStart: .now, yearTitle: "2026", isYearInProgress: true,
        workoutCount: 148, activeDays: 132, durationSeconds: 64 * 3_600, walkRunDistanceMeters: 182_400,
        distanceUnit: .kilometers, trainingWeeks: 42, milestoneCount: 18,
        months: (1...12).map { .init(date: Date(timeIntervalSince1970: Double($0) * 86_400),
            label: String($0), workoutCount: $0 * 2) },
        busiestMonth: "September", busiestMonthWorkoutCount: 24, highlight: "Barbell Bench Press · 100 kg"))
        .frame(width: 360, height: 640)
}
