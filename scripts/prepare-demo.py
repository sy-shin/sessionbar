#!/usr/bin/env python3
"""Build an isolated renderer from production views and synthetic records only."""
from pathlib import Path
import shutil
root = Path(__file__).resolve().parent.parent
package = root / '.build/demo-preview'
views = package / 'Sources/Preview'
core = package / 'Sources/SessionbarCore'
views.mkdir(parents=True, exist_ok=True)
core.mkdir(parents=True, exist_ok=True)
for path in views.glob('*.swift'):
    path.unlink()
for path in core.glob('*.swift'):
    path.unlink()
for path in (root / 'Sources/SessionbarCore').glob('*.swift'):
    shutil.copy2(path, core / path.name)
for name in ['AppSettings.swift', 'Localization.swift', 'SessionInventory.swift',
             'SessionDetailView.swift', 'SessionTerminationView.swift', 'SessionReturnButton.swift',
             'SessionTheme.swift', 'SessionbarSettingsView.swift', 'SessionHistoryView.swift',
             'DiagnosticsView.swift', 'TerminalConnector.swift', 'ProcessObserver.swift',
             'CommandRunner.swift', 'SessionProcessController.swift']:
    shutil.copy2(root / 'Sources/sessionbar' / name, views / name)
source = (root / 'Sources/sessionbar/SessionbarApp.swift').read_text()
source = 'import SwiftUI\nimport AppKit\nimport SessionbarCore\n\n' + source[source.index('struct SessionListView:'):]
source = source.replace('@State private var filter = SessionListFilter.openSessions', '''@State private var filter: SessionListFilter
    init(store: SessionStore, settings: AppSettings, initialFilter: SessionListFilter = .openSessions) {
        self.store = store; self.settings = settings
        _filter = State(initialValue: initialFilter)
    }''')
(views / 'SessionListView.swift').write_text(source)
connector = (root / 'Sources/sessionbar/SessionWindowConnector.swift').read_text()
# Keep result types/labels; navigation in this renderer never controls real apps.
connector = connector[:connector.index('@MainActor')] + '''@MainActor enum SessionWindowConnector {
    static func canReturn(_ runtime: SessionRuntime?) -> Bool { runtime != nil }
    static func activateApp(_ runtime: SessionRuntime) -> WindowReturnResult { .appActivated }
}
'''
(views / 'SessionWindowConnector.swift').write_text(connector)
for path in (root / 'scripts/demo').glob('*.swift'):
    shutil.copy2(path, views / path.name)
(package / 'AGENTS.md').write_text('# Isolated demo\nUse synthetic records only. Do not access real sessions or capture the desktop.\n')
(package / 'README.md').write_text('# sessionbar demo renderer\nRenders production SwiftUI views with synthetic records.\n')
(package / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SessionbarDemo", platforms: [.macOS(.v14)], targets: [
    .target(name: "SessionbarCore"),
    .executableTarget(name: "Preview", dependencies: ["SessionbarCore"])
], swiftLanguageVersions: [.v5])
''')
print('Prepared isolated demo renderer')
