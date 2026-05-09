import LisdoCore
import SwiftUI

struct LisdoMacSidebarView: View {
    @EnvironmentObject private var iCloudSyncStatusMonitor: LisdoICloudSyncStatusMonitor

    @Binding var selection: LisdoMacSelection
    let categories: [Category]
    let drafts: [ProcessingDraft]
    let captures: [CaptureItem]
    let todos: [Todo]
    let onAddCategory: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    sidebarRow(
                        title: "Inbox",
                        detail: "\(drafts.count) drafts",
                        systemImage: "tray",
                        count: inboxCount
                    )
                    .tag(LisdoMacSelection.inbox)

                    sidebarRow(
                        title: "Drafts",
                        detail: "Review required",
                        systemImage: "sparkles",
                        count: drafts.count
                    )
                    .tag(LisdoMacSelection.drafts)

                    sidebarRow(
                        title: "Today",
                        detail: "Due and scheduled",
                        systemImage: "clock",
                        count: todayCount
                    )
                    .tag(LisdoMacSelection.today)

                    sidebarRow(
                        title: "Plan",
                        detail: "Lisdo planning",
                        systemImage: "calendar"
                    )
                    .tag(LisdoMacSelection.plan)

                    sidebarRow(
                        title: "From iPhone",
                        detail: "Mac processing queue",
                        systemImage: "iphone",
                        count: fromIPhoneCount
                    )
                    .tag(LisdoMacSelection.fromIPhone)
                }

                Section {
                    ForEach(categories, id: \.id) { category in
                        HStack(spacing: 10) {
                            LisdoCategoryDot(category: category)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                    .lineLimit(1)
                                Text(category.descriptionText.isEmpty ? "Category todos" : category.descriptionText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(todos.inCategory(category.id).count)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .tag(LisdoMacSelection.category(category.id))
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text("Categories")
                        Spacer()
                        Button(action: onAddCategory) {
                            Image(systemName: "plus")
                                .font(.caption.weight(.semibold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Add Category")
                        .accessibilityLabel("Add Category")
                        .padding(.trailing, 8)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollIndicators(.hidden)

            Divider()
                .opacity(0.55)

            HStack(spacing: 8) {
                Image(systemName: iCloudSyncStatusMonitor.snapshot.systemImage)
                    .frame(width: 16)
                Text(iCloudSyncStatusMonitor.snapshot.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(iCloudSyncStatusMonitor.snapshot.isCloudBacked ? .secondary : .tertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .help(iCloudSyncStatusMonitor.snapshot.detail ?? iCloudSyncStatusMonitor.snapshot.title)
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        .task {
            iCloudSyncStatusMonitor.refresh()
        }
    }

    private var inboxCount: Int {
        drafts.count + captures.filter { $0.status != .approvedTodo }.count
    }

    private var todayCount: Int {
        let calendar = Calendar.current
        return todos.filter { todo in
            if let dueDate = todo.dueDate, calendar.isDateInToday(dueDate) {
                return true
            }
            if let scheduledDate = todo.scheduledDate, calendar.isDateInToday(scheduledDate) {
                return true
            }
            return todo.dueDateText?.localizedCaseInsensitiveContains("today") == true
        }.count
    }

    private var fromIPhoneCount: Int {
        captures.filter { $0.createdDevice == .iPhone || $0.preferredProviderMode == .macOnlyCLI || $0.status == .pendingProcessing }.count
    }

    private func sidebarRow(
        title: String,
        detail: String,
        systemImage: String,
        count: Int? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
