import SwiftUI
import CuebarCore

/// The Raycast-style ⌘K actions popup, anchored to the palette's bottom-right.
///
/// Rendered inside the main panel rather than as a second window: the palette is
/// a non-activating `NSPanel` that hides on resign-key, so a separate key window
/// would dismiss it. The parent's key monitor drives selection and Return.
struct ActionsMenuView: View {
    // Value inputs keep the outgoing popup intact when closing clears the model.
    // The parent observes the model; this view only uses it to dispatch actions.
    let model: PaletteModel
    let menu: ActionsMenuState
    let items: [QuickActionItem]
    let title: String
    let subtitle: String
    let focusToken: UUID
    @FocusState private var isFilterFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PaletteModel, menu: ActionsMenuState) {
        self.model = model
        self.menu = menu
        items = model.visibleActionsItems
        title = model.actionsTitle
        subtitle = model.actionsSubtitle
        focusToken = model.actionsFocusToken
    }

    private var isPlaylistMode: Bool { menu.mode == .playlists }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            list
            Divider().opacity(0.5)
            filterField
        }
        .frame(width: 300)
        .frame(maxHeight: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .onChange(of: focusToken) { _, _ in isFilterFocused = true }
        .onAppear { isFilterFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if isPlaylistMode {
                Button {
                    model.backActionsMenu()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(isPlaylistMode ? "Add to Playlist" : title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if !isPlaylistMode, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var list: some View {
        if items.isEmpty {
            Text(isPlaylistMode ? "No playlists" : "No actions")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            actionRow(index: index, item: item)
                                .id(item.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: menu.selection) { _, newValue in
                    guard items.indices.contains(newValue) else { return }
                    if reduceMotion {
                        proxy.scrollTo(items[newValue].id, anchor: .center)
                    } else {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(items[newValue].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
    }

    private func actionRow(index: Int, item: QuickActionItem) -> some View {
        let isSelected = menu.selection == index
        let tint: Color = item.isDestructive ? .red : .primary
        return HStack(spacing: 10) {
            Image(systemName: item.symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(tint)

            Text(item.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(tint)

            Spacer(minLength: 8)

            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { model.runQuickAction(item.action) }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Search for actions…", text: Binding(
                get: { menu.query },
                set: { model.setActionsQuery($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($isFilterFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
