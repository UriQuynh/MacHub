// SPDX-License-Identifier: GPL-3.0-only
// MacHub — fork of HyperMac. Original work Copyright (C) 2026 Nguyễn Khắc Đại.
// Modifications Copyright (C) 2026 MacHub contributors.
// (Tách từ Views.swift của HyperMac.)

import SwiftUI

// MARK: - Main MenuBar View (Tabbed & Organized Architecture)

/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5 */
public struct MainView: View {
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var batteryManager: BatteryManager = BatteryManager.shared
    @ObservedObject var snapManager: WindowSnapManager = WindowSnapManager.shared
    @ObservedObject var windowManager: WindowManager = WindowManager.shared
    @ObservedObject var clipboardManager: ClipboardManager = ClipboardManager.shared
    @ObservedObject var caffeinateManager: CaffeinateManager = CaffeinateManager.shared
    @ObservedObject var updateManager: UpdateManager = UpdateManager.shared
    @ObservedObject var thermalManager: ThermalManager = ThermalManager.shared
    @ObservedObject var virtualDisplayManager: VirtualDisplayManager = VirtualDisplayManager.shared
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager.shared
    @ObservedObject var finderCutPasteManager: FinderCutPasteManager = FinderCutPasteManager.shared
    @ObservedObject var cleanerManager: SystemCleanerManager = SystemCleanerManager.shared
    @ObservedObject var permissionsManager: PermissionsManager = PermissionsManager.shared
    @ObservedObject var languageManager: LanguageManager = LanguageManager.shared
    @ObservedObject var screenshotManager: ScreenshotManager = ScreenshotManager.shared

    public init(displayManager: DisplayManager) {
        self.displayManager = displayManager
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Modern Sleek Header Bar
                ModernHeaderBar(
                    batteryManager: batteryManager,
                    caffeinateManager: caffeinateManager,
                    updateManager: updateManager,
                    thermalManager: thermalManager,
                    onSelectThermal: {
                        displayManager.selectedMainTab = 1
                        thermalManager.selectedSection = 1
                    }
                )

                // Top Tab Navigation Bar
                TopTabBar(selectedTab: Binding<Int>(
                    get: { displayManager.selectedMainTab },
                    set: { displayManager.selectedMainTab = $0 }
                ))

                Divider().padding(.horizontal, 10)

                // Active Tab Content View
                Group {
                    switch displayManager.selectedMainTab {
                    case 0:
                        DisplaysTabView(
                            displayManager: displayManager,
                            permissionsManager: permissionsManager,
                            virtualDisplayManager: virtualDisplayManager
                        )
                    case 1:
                        HardwareCareTabView(
                            batteryManager: batteryManager,
                            thermalManager: thermalManager
                        )
                    case 2:
                        ShortcutsTabView(
                            displayManager: displayManager,
                            snapManager: snapManager,
                            windowManager: windowManager,
                            clipboardManager: clipboardManager,
                            caffeinateManager: caffeinateManager,
                            launchAtLoginManager: launchAtLoginManager,
                            finderCutPasteManager: finderCutPasteManager
                        )
                    case 3:
                        CleanerTabView(cleanerManager: cleanerManager)
                    case 4:
                        AgentTabView(monitor: AgentMonitor.shared)
                    default:
                        DisplaysTabView(
                            displayManager: displayManager,
                            permissionsManager: permissionsManager,
                            virtualDisplayManager: virtualDisplayManager
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().padding(.horizontal, 10)

                // Minimal Footer
                FooterView(updateManager: updateManager)
            }
            .id(languageManager.currentLanguage)
        }
        .frame(width: 380, height: 570)
        .alert(isPresented: Binding<Bool>(
            get: { displayManager.showAlert },
            set: { displayManager.showAlert = $0 }
        )) {
            Alert(
                title: Text(tr("Thông báo", "Notice")),
                message: Text(displayManager.alertMessage ?? ""),
                dismissButton: .default(Text(tr("Đã hiểu", "OK")))
            )
        }
    }
}
