// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import SwiftUI

struct TranslationEngineControl: NSViewRepresentable {
    @Binding var selection: TranslationEngine
    let label: String
    let appleHelp: String
    let googleHelp: String
    private static let engines: [TranslationEngine] = [.apple, .google]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["Apple", "Google"], trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.choose(_:)))
        control.segmentStyle = .rounded
        control.controlSize = .regular
        for (index, symbol) in ["cpu", "cloud"].enumerated() {
            control.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
            control.setWidth(90, forSegment: index)
        }
        control.setAccessibilityIdentifier("translationEnginePicker")
        updateNSView(control, context: context)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = Self.engines.firstIndex(of: selection) ?? 0
        control.isEnabled = context.environment.isEnabled
        control.setAccessibilityLabel(label)
        control.setToolTip(appleHelp, forSegment: 0)
        control.setToolTip(googleHelp, forSegment: 1)
    }

    final class Coordinator: NSObject {
        var parent: TranslationEngineControl
        init(_ parent: TranslationEngineControl) { self.parent = parent }

        @objc func choose(_ sender: NSSegmentedControl) {
            guard TranslationEngineControl.engines.indices.contains(sender.selectedSegment) else { return }
            let engine = TranslationEngineControl.engines[sender.selectedSegment]
            if engine != parent.selection { parent.selection = engine }
        }
    }
}
