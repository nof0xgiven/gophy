import SwiftUI

@MainActor
struct MenuBarContentView: View {
    @Environment(NavigationCoordinator.self) private var navigationCoordinator
    @State private var viewModel = MenuBarViewModel()

    var body: some View {
        VStack(spacing: 0) {
            statusSection

            Divider()

            quickActionsSection

            if !viewModel.upcomingEvents.isEmpty {
                Divider()
                upcomingSection
            }

            if !viewModel.lastMeetingTitle.isEmpty {
                Divider()
                lastMeetingSection
            }

            Divider()

            footerSection
        }
        .frame(width: 320)
        .padding(.vertical, 4)
        .task {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private var statusSection: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.statusIcon)
                .foregroundStyle(viewModel.statusIconColor)
                .font(.title3)
                .symbolEffect(.pulse, isActive: viewModel.isRecording)

            Text(viewModel.statusText)
                .font(.headline)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var quickActionsSection: some View {
        VStack(spacing: 4) {
            Button {
                viewModel.startInstantMeeting(navigationCoordinator: navigationCoordinator)
            } label: {
                Label("Start Instant Meeting", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)

            if let nextEvent = viewModel.upcomingEvents.first {
                Button {
                    viewModel.startMeetingForEvent(nextEvent, navigationCoordinator: navigationCoordinator)
                } label: {
                    Label("Start: \(nextEvent.title)", systemImage: "calendar.badge.play")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Upcoming")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)

            upcomingEventsList
        }
    }

    @ViewBuilder
    private var upcomingEventsList: some View {
        ForEach(viewModel.upcomingEvents) { event in
            upcomingEventRow(event)
        }
    }

    private func upcomingEventRow(_ event: UnifiedCalendarEvent) -> some View {
        Button {
            viewModel.startMeetingForEvent(event, navigationCoordinator: navigationCoordinator)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.body)
                        .lineLimit(1)
                    Text(formatEventTime(event))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle")
                    .foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var lastMeetingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last Meeting")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.lastMeetingTitle)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if !viewModel.lastMeetingSummary.isEmpty {
                    Text(viewModel.lastMeetingSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerSection: some View {
        HStack(spacing: 12) {
            Button {
                activateApp()
            } label: {
                Label("Show Gophy", systemImage: "window.cauldron")
            }
            .buttonStyle(.borderless)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func formatEventTime(_ event: UnifiedCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: event.startDate)
    }

    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
