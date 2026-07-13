import ApplicationServices
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case usage
    case inaccessible(String)
    case noWindow
    case invalidWindow(minimized: Bool, width: Int, height: Int)
    case emptyContent(width: Int, height: Int, nodes: Int)

    var description: String {
        switch self {
        case .usage:
            "usage: qa-window-content-probe.swift <pid>"
        case let .inaccessible(detail):
            "SETUP_FAIL: Accessibility inspection failed: \(detail)"
        case .noWindow:
            "SETUP_FAIL: Zoid window did not appear"
        case let .invalidWindow(minimized, width, height):
            "SETUP_FAIL: expected a non-minimized 1180x760 window, got minimized=\(minimized) size=\(width)x\(height)"
        case let .emptyContent(width, height, nodes):
            "RED: exact empty-window symptom reproduced: non-minimized \(width)x\(height) Zoid window has \(nodes) AX content nodes after onboarding continuation"
        }
    }
}

func value(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else { return nil }
    return result
}

func stringValue(_ element: AXUIElement, _ attribute: CFString) -> String? {
    value(element, attribute) as? String
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (value(element, kAXChildrenAttribute as CFString) as? [AXUIElement]) ?? []
}

func descendants(_ root: AXUIElement, maximumDepth: Int = 14) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue: [(AXUIElement, Int)] = [(root, 0)]
    while let (element, depth) = queue.first {
        queue.removeFirst()
        guard depth < maximumDepth else { continue }
        for child in children(element) {
            result.append(child)
            queue.append((child, depth + 1))
        }
    }
    return result
}

func window(for application: AXUIElement, timeout: TimeInterval) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let windows = value(application, kAXWindowsAttribute as CFString) as? [AXUIElement],
           let first = windows.first {
            return first
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
}

func button(identifier expectedIdentifier: String, in window: AXUIElement) -> AXUIElement? {
    descendants(window).first { element in
        guard stringValue(element, kAXRoleAttribute as CFString) == kAXButtonRole as String else { return false }
        return stringValue(element, kAXIdentifierAttribute as CFString) == expectedIdentifier
    }
}

func waitForButton(identifier expectedIdentifier: String, in window: AXUIElement, timeout: TimeInterval) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let button = button(identifier: expectedIdentifier, in: window) { return button }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
}

func contentNodeCount(in window: AXUIElement) -> Int {
    let contentRoles = Set([
        kAXStaticTextRole as String,
        kAXButtonRole as String,
        kAXGroupRole as String,
        kAXScrollAreaRole as String,
        kAXTextFieldRole as String,
        kAXCheckBoxRole as String
    ])
    return descendants(window).filter {
        guard let role = stringValue($0, kAXRoleAttribute as CFString), contentRoles.contains(role) else { return false }
        if role != kAXButtonRole as String { return true }
        let subrole = stringValue($0, kAXSubroleAttribute as CFString) ?? ""
        return ![kAXCloseButtonSubrole, kAXMinimizeButtonSubrole, kAXZoomButtonSubrole]
            .map { $0 as String }
            .contains(subrole)
    }.count
}

func windowState(_ window: AXUIElement) throws -> (minimized: Bool, width: Int, height: Int) {
    let minimized = (value(window, kAXMinimizedAttribute as CFString) as? Bool) ?? false
    guard let sizeValue = value(window, kAXSizeAttribute as CFString),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
        throw ProbeError.inaccessible("window size is unavailable")
    }
    var size = CGSize.zero
    guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
        throw ProbeError.inaccessible("window size could not be decoded")
    }
    return (minimized, Int(size.width.rounded()), Int(size.height.rounded()))
}

do {
    guard CommandLine.arguments.count == 2,
          let pid = Int32(CommandLine.arguments[1]) else { throw ProbeError.usage }
    let application = AXUIElementCreateApplication(pid)
    guard let initialWindow = window(for: application, timeout: 10) else { throw ProbeError.noWindow }
    let initialState = try windowState(initialWindow)
    let initialNodes = contentNodeCount(in: initialWindow)
    if let continuation = waitForButton(identifier: "onboarding.continue", in: initialWindow, timeout: 3) {
        guard AXUIElementPerformAction(continuation, kAXPressAction as CFString) == .success else {
            throw ProbeError.inaccessible("onboarding continuation could not be activated")
        }
        Thread.sleep(forTimeInterval: 1)
    } else if initialNodes < 5,
              !initialState.minimized,
              initialState.width == 1180,
              initialState.height == 760 {
        throw ProbeError.emptyContent(
            width: initialState.width,
            height: initialState.height,
            nodes: initialNodes
        )
    } else {
        throw ProbeError.inaccessible("onboarding.continue did not appear in a non-empty launch window")
    }
    guard let finalWindow = window(for: application, timeout: 5) else { throw ProbeError.noWindow }
    let state = try windowState(finalWindow)
    guard !state.minimized, state.width == 1180, state.height == 760 else {
        throw ProbeError.invalidWindow(minimized: state.minimized, width: state.width, height: state.height)
    }
    let contentNodes = contentNodeCount(in: finalWindow)
    guard contentNodes >= 5 else {
        throw ProbeError.emptyContent(width: state.width, height: state.height, nodes: contentNodes)
    }
    print("GREEN: non-minimized \(state.width)x\(state.height) Zoid window exposes \(contentNodes) AX content nodes after onboarding continuation")
} catch {
    fputs("\(error)\n", stderr)
    exit(error is ProbeError ? 1 : 2)
}
