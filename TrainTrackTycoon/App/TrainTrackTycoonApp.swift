import SwiftUI

@main
struct TrainTrackTycoonApp: App {
    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
                .tint(TycoonTheme.railGreen)
        }
    }
}

@MainActor
private struct AppBootstrapView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator = GamePersistenceCoordinator()
    @State private var isConfirmingStartFresh = false

    var body: some View {
        Group {
            if let session = coordinator.session {
                GameRootView(session: session)
                    .onChange(of: session.persistenceRevision) { _, revision in
                        coordinator.sessionPersistenceDidChange(to: revision)
                    }
            } else if let launchError = coordinator.launchErrorMessage {
                startupFailure(
                    message: launchError,
                    canStartFresh: coordinator.canStartFresh
                )
            } else {
                startupProgress
            }
        }
        .task {
            coordinator.scenePhaseDidChange(to: scenePhase)
            await coordinator.launchIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            coordinator.scenePhaseDidChange(to: newPhase)
        }
        .alert(
            "Couldn’t save game",
            isPresented: Binding(
                get: { coordinator.saveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        coordinator.dismissSaveError()
                    }
                }
            )
        ) {
            Button("Try Again") {
                coordinator.retrySave()
            }
            Button("Not Now", role: .cancel) {
                coordinator.dismissSaveError()
            }
        } message: {
            Text(coordinator.saveErrorMessage ?? "The saved game couldn’t be updated.")
        }
        .confirmationDialog(
            "Delete the saved railway and start again?",
            isPresented: $isConfirmingStartFresh,
            titleVisibility: .visible
        ) {
            Button("Delete Saved Game", role: .destructive) {
                Task {
                    await coordinator.startFresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local save. It can’t be undone.")
        }
    }

    private var startupProgress: some View {
        ZStack {
            TycoonTheme.warmPaper.ignoresSafeArea()

            VStack(spacing: 18) {
                RailwayGlyph()
                    .scaleEffect(1.35)

                ProgressView("Preparing the railway…")
                    .font(.callout.weight(.medium))
                    .tint(TycoonTheme.railGreen)
            }
            .foregroundStyle(TycoonTheme.ink)
        }
    }

    private func startupFailure(message: String, canStartFresh: Bool) -> some View {
        ContentUnavailableView {
            Label("Couldn’t open the railway", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task {
                    await coordinator.retryLaunch()
                }
            }
            .buttonStyle(.borderedProminent)

            if canStartFresh {
                Button("Start Fresh", role: .destructive) {
                    isConfirmingStartFresh = true
                }
            }
        }
    }
}
