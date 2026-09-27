import SwiftData
import SwiftUI
import UIKit

struct BirthdayHomeSection: View {
    @Query(sort: [SortDescriptor(\UserProfile.createdAt), SortDescriptor(\UserProfile.id)]) private var profiles: [UserProfile]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isTabActive) private var isTabActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var preferences = BirthdayCelebrationPreferences()
    @State private var now = Date.now
    @State private var clockRevision = 0
    @Binding var bursts: [WorkoutCompletionConfettiBurst]
    let canCelebrate: Bool

    private var occasion: BirthdayOccasion? {
        guard let profile = profiles.first else { return nil }
        return BirthdayCelebrationPolicy.occasion(profileID: profile.id, displayName: profile.displayName,
                                                   dateOfBirth: profile.dateOfBirth, on: now)
    }

    private var refreshID: String {
        "\(scenePhase)-\(isTabActive)-\(canCelebrate)-\(reduceMotion)-\(clockRevision)-\(profiles.first?.id.uuidString ?? "")-\(profiles.first?.dateOfBirth?.description ?? "")"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let occasion, !preferences.isDismissed(occasion) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("🎂").font(.largeTitle).accessibilityHidden(true)
                        Text(occasion.greeting)
                            .font(WGJTheme.headingFont(.title2))
                            .foregroundStyle(WGJTheme.textPrimary)
                        Text("Another year stronger.")
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        preferences.dismiss(occasion)
                        bursts = []
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(WGJIconButtonStyle())
                    .accessibilityLabel("Dismiss birthday greeting")
                    .accessibilityIdentifier("birthday-dismiss-button")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .wgjCardContainer(strong: true)
                .overlay(RoundedRectangle(cornerRadius: WGJRadius.card)
                    .strokeBorder(WGJTheme.accentGold.opacity(0.6), lineWidth: 1))
                .padding(.top, 20)
            }
        }
        .task(id: refreshID) {
            guard scenePhase == .active, isTabActive else { return }
            defer { bursts = [] }
            while !Task.isCancelled {
                now = .now
                if canCelebrate, let occasion, !preferences.isDismissed(occasion) {
                    do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                    if preferences.claimConfetti(occasion), !reduceMotion {
                        bursts = WorkoutCompletionConfettiPolicy.burstDescriptors(
                            origin: .overlayCenter, intensity: .completedWorkout, variant: .standard, birthday: true
                        ).map { WorkoutCompletionConfettiBurst(descriptor: $0, birthday: true) }
                        do { try await Task.sleep(for: WorkoutCompletionConfettiPolicy.burstLifetime) } catch { return }
                        bursts = []
                    }
                }
                let date = Date.now
                let midnight = BirthdayCelebrationPolicy.localCalendar.dateInterval(of: .day, for: date)?.end
                    ?? date.addingTimeInterval(3600)
                do { try await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSince(date)))) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
            clockRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            now = .now
            clockRevision += 1
        }
    }
}
