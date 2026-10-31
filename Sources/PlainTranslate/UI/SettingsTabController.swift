// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import Combine
import SwiftUI

/// AppKit owns tab selection, keyboard navigation and toolbar overflow.
final class SettingsTabController: NSTabViewController {
    static let backIdentifier = NSToolbarItem.Identifier("settings.back")
    private weak var navigation: SettingsNavigation?
    private var subscriptions = Set<AnyCancellable>()
    private var ready = false

    init(navigation: SettingsNavigation, inspectCredentials: Bool = true) {
        self.navigation = navigation
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        canPropagateSelectedChildViewControllerTitle = false
        transitionOptions = []
        for pane in SettingsPane.allCases {
            let host = NSHostingController(rootView: SettingsView(
                pane: pane, inspectCredentials: inspectCredentials, navigation: navigation))
            host.title = pane.title(for: L10n.shared.language)
            host.preferredContentSize = NSSize(width: 840, height: 580)
            let item = NSTabViewItem(viewController: host)
            item.identifier = pane.rawValue
            item.label = host.title ?? ""
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: item.label)
            item.toolTip = item.label
            addTabViewItem(item)
        }
        selectedTabViewItemIndex = SettingsPane.allCases.firstIndex(of: navigation.selectedPane) ?? 0
        ready = true
        L10n.shared.$language.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLabels() }
            .store(in: &subscriptions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Settings are created programmatically") }

    override func viewWillAppear() {
        super.viewWillAppear()
        configureWindow()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        configureWindow()
    }

    func configureWindow() {
        guard let window = viewIfLoaded?.window else { return }
        window.toolbarStyle = .preference
        window.toolbar?.allowsUserCustomization = false
        window.toolbar?.allowsDisplayModeCustomization = false
        window.toolbar?.autosavesConfiguration = false
        window.toolbar?.displayMode = .iconAndLabel
        window.toolbar?.isVisible = true
        updateLabels()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard ready, let identifier = tabViewItem?.identifier as? String,
              let pane = SettingsPane(rawValue: identifier) else { return }
        navigation?.selectPane(pane)
        updateLabels()
    }

    override func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.backIdentifier, .flexibleSpace] + super.toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace]
    }

    override func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.backIdentifier, .flexibleSpace] + super.toolbarAllowedItemIdentifiers(toolbar)
    }

    override func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                          willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.backIdentifier else {
            return super.toolbar(toolbar, itemForItemIdentifier: itemIdentifier,
                                 willBeInsertedIntoToolbar: flag)
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = backTitle
        item.paletteLabel = backTitle
        item.toolTip = backTitle
        item.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: backTitle)
        item.target = self
        item.action = #selector(returnToTranslation)
        item.visibilityPriority = .high
        return item
    }

    private var backTitle: String {
        L10n.shared.language == .en ? "Back to translation" : "返回翻譯"
    }

    private func updateLabels() {
        let language = L10n.shared.language
        for (pane, item) in zip(SettingsPane.allCases, tabViewItems) {
            item.label = pane.title(for: language)
            item.toolTip = item.label
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: item.label)
            item.viewController?.title = item.label
        }
        guard let window = viewIfLoaded?.window else { return }
        let pane = SettingsPane.allCases.indices.contains(selectedTabViewItemIndex)
            ? SettingsPane.allCases[selectedTabViewItemIndex] : .translation
        window.title = "PlainTranslate · \(pane.title(for: language))"
        if let back = window.toolbar?.items.first(where: { $0.itemIdentifier == Self.backIdentifier }) {
            back.label = backTitle
            back.paletteLabel = backTitle
            back.toolTip = backTitle
            back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: backTitle)
        }
    }

    @objc private func returnToTranslation() { navigation?.returnToTranslation() }
}
