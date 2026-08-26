import Foundation
import XCTest

final class VanmoDeviceInteractionTests: XCTestCase {
    private enum Action: String {
        case screenshot
        case tree
        case tap
        case type
        case swipe
        case wait
        case assertState = "assert"
        case journey
    }

    private enum Journey: String {
        case tabNavigation = "tab-navigation"
    }

    private enum SelectorKind: String {
        case identifier
        case label
    }

    private enum Direction: String {
        case up
        case down
        case left
        case right
    }

    private enum ExpectedState: String {
        case exists
        case absent
    }

    private enum CommandError: LocalizedError {
        case missingVariable(String)
        case invalidVariable(name: String, value: String, expected: String)
        case elementNotFound(kind: String, selector: String, timeout: TimeInterval)
        case expectationNotMet(expected: String, kind: String, selector: String, timeout: TimeInterval)

        var errorDescription: String? {
            switch self {
            case let .missingVariable(name):
                return "Missing required environment variable \(name)."
            case let .invalidVariable(name, value, expected):
                return "Invalid \(name) value '\(value)'; expected \(expected)."
            case let .elementNotFound(kind, selector, timeout):
                return "No element matched \(kind) '\(selector)' within \(timeout) seconds."
            case let .expectationNotMet(expected, kind, selector, timeout):
                return "Element \(kind) '\(selector)' did not become \(expected) within \(timeout) seconds."
            }
        }
    }

    private let defaultTimeout: TimeInterval = 10
    private let minimumTimeout: TimeInterval = 0.1
    private let maximumTimeout: TimeInterval = 60
    private let maximumTreeElementCount = 500

    func testExecuteCommand() {
        let app = XCUIApplication()
        app.launch()

        do {
            let environment = ProcessInfo.processInfo.environment
            let action: Action = try requiredEnum(
                named: "VANMO_UI_ACTION",
                in: environment,
                expected: "screenshot, tree, tap, type, swipe, wait, assert, or journey"
            )
            try execute(action, environment: environment, app: app)
            print("[VanmoUI] action=\(action.rawValue) succeeded")
        } catch {
            attachFailureArtifacts(for: app)
            recordFailure(
                withDescription: "[VanmoUI] \(error.localizedDescription)",
                inFile: #filePath,
                atLine: #line,
                expected: false
            )
        }
    }

    private func execute(
        _ action: Action,
        environment: [String: String],
        app: XCUIApplication
    ) throws {
        switch action {
        case .screenshot:
            add(screenshotAttachment(named: "vanmo-ui-screenshot.png"))
        case .tree:
            add(try treeAttachment(for: app, named: "vanmo-ui-tree.json"))
        case .tap:
            let (element, kind, selector) = try selectedElement(in: app, environment: environment)
            let timeout = try timeout(from: environment)
            guard element.waitForExistence(timeout: timeout) else {
                throw CommandError.elementNotFound(
                    kind: kind.rawValue,
                    selector: selector,
                    timeout: timeout
                )
            }
            element.tap()
        case .type:
            let (element, kind, selector) = try selectedElement(in: app, environment: environment)
            let text = try requiredValue(named: "VANMO_UI_TEXT", in: environment)
            let timeout = try timeout(from: environment)
            guard element.waitForExistence(timeout: timeout) else {
                throw CommandError.elementNotFound(
                    kind: kind.rawValue,
                    selector: selector,
                    timeout: timeout
                )
            }
            element.tap()
            element.typeText(text)
        case .swipe:
            let direction: Direction = try requiredEnum(
                named: "VANMO_UI_DIRECTION",
                in: environment,
                expected: "up, down, left, or right"
            )
            performSwipe(direction, in: app)
        case .wait, .assertState:
            let (element, kind, selector) = try selectedElement(in: app, environment: environment)
            let expected: ExpectedState = try requiredEnum(
                named: "VANMO_UI_EXPECTED",
                in: environment,
                expected: "exists or absent"
            )
            let timeout = try timeout(from: environment)
            try wait(
                for: expected,
                element: element,
                kind: kind,
                selector: selector,
                timeout: timeout
            )
        case .journey:
            let journey: Journey = try requiredEnum(
                named: "VANMO_UI_JOURNEY",
                in: environment,
                expected: "tab-navigation"
            )
            let timeout = try timeout(from: environment)
            switch journey {
            case .tabNavigation:
                try runTabNavigationJourney(in: app, timeout: timeout)
            }
        }
    }

    private func runTabNavigationJourney(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) throws {
        try wait(
            for: .exists,
            element: element(identifier: "screen.library", in: app),
            kind: .identifier,
            selector: "screen.library",
            timeout: timeout
        )

        let tab = try settingsTabElement(in: app, timeout: timeout)
        tab.tap()

        try wait(
            for: .exists,
            element: element(identifier: "screen.settings", in: app),
            kind: .identifier,
            selector: "screen.settings",
            timeout: timeout
        )

        add(screenshotAttachment(named: "vanmo-ui-screenshot.png"))
        add(try treeAttachment(for: app, named: "vanmo-ui-tree.json"))
        print("[VanmoUI] journey=tab-navigation succeeded")
    }

    private func settingsTabElement(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) throws -> XCUIElement {
        let identifiedTab = element(identifier: "tab.settings", in: app)
        if identifiedTab.waitForExistence(timeout: timeout) {
            return identifiedTab
        }

        let labeledTab = element(label: "设置", in: app)
        guard labeledTab.waitForExistence(timeout: timeout) else {
            throw CommandError.elementNotFound(
                kind: SelectorKind.identifier.rawValue,
                selector: "tab.settings",
                timeout: timeout
            )
        }
        return labeledTab
    }

    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func element(label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", label)
        ).firstMatch
    }

    private func selectedElement(
        in app: XCUIApplication,
        environment: [String: String]
    ) throws -> (XCUIElement, SelectorKind, String) {
        let kind: SelectorKind = try requiredEnum(
            named: "VANMO_UI_SELECTOR_KIND",
            in: environment,
            expected: "identifier or label"
        )
        let selector = try requiredValue(named: "VANMO_UI_SELECTOR", in: environment)
        let descendants = app.descendants(matching: .any)

        let element: XCUIElement
        switch kind {
        case .identifier:
            element = descendants.matching(identifier: selector).firstMatch
        case .label:
            element = descendants.matching(
                NSPredicate(format: "label == %@", selector)
            ).firstMatch
        }

        return (element, kind, selector)
    }

    private func performSwipe(_ direction: Direction, in app: XCUIApplication) {
        switch direction {
        case .up:
            app.swipeUp()
        case .down:
            app.swipeDown()
        case .left:
            app.swipeLeft()
        case .right:
            app.swipeRight()
        }
    }

    private func wait(
        for expected: ExpectedState,
        element: XCUIElement,
        kind: SelectorKind,
        selector: String,
        timeout: TimeInterval
    ) throws {
        let didMeetExpectation: Bool
        switch expected {
        case .exists:
            didMeetExpectation = element.waitForExistence(timeout: timeout)
        case .absent:
            let predicate = NSPredicate(format: "exists == false")
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
            didMeetExpectation = XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
        }

        guard didMeetExpectation else {
            throw CommandError.expectationNotMet(
                expected: expected.rawValue,
                kind: kind.rawValue,
                selector: selector,
                timeout: timeout
            )
        }
    }

    private func requiredValue(
        named name: String,
        in environment: [String: String]
    ) throws -> String {
        guard let value = environment[name], value.isEmpty == false else {
            throw CommandError.missingVariable(name)
        }
        return value
    }

    private func requiredEnum<Value: RawRepresentable>(
        named name: String,
        in environment: [String: String],
        expected: String
    ) throws -> Value where Value.RawValue == String {
        let rawValue = try requiredValue(named: name, in: environment)
        let normalizedValue = rawValue.lowercased()
        guard let value = Value(rawValue: normalizedValue) else {
            throw CommandError.invalidVariable(
                name: name,
                value: rawValue,
                expected: expected
            )
        }
        return value
    }

    private func timeout(from environment: [String: String]) throws -> TimeInterval {
        guard let rawValue = environment["VANMO_UI_TIMEOUT"], rawValue.isEmpty == false else {
            return defaultTimeout
        }
        guard
            let value = TimeInterval(rawValue),
            value >= minimumTimeout,
            value <= maximumTimeout
        else {
            throw CommandError.invalidVariable(
                name: "VANMO_UI_TIMEOUT",
                value: rawValue,
                expected: "a number from \(minimumTimeout) through \(maximumTimeout) seconds"
            )
        }
        return value
    }

    private func screenshotAttachment(named name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }

    private func treeAttachment(
        for app: XCUIApplication,
        named name: String
    ) throws -> XCTAttachment {
        let data = try treeData(for: app)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }

    private func treeData(for app: XCUIApplication) throws -> Data {
        let elements = app.descendants(matching: .any)
            .allElementsBoundByIndex
            .prefix(maximumTreeElementCount)
        let payload: [[String: Any]] = elements.map { element in
            let frame = element.frame
            return [
                "type": String(describing: element.elementType),
                "identifier": element.identifier,
                "label": element.label,
                "value": jsonValue(element.value),
                "frame": [
                    "x": frame.origin.x,
                    "y": frame.origin.y,
                    "width": frame.size.width,
                    "height": frame.size.height
                ],
                "enabled": element.isEnabled,
                "hittable": element.isHittable
            ]
        }
        return try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private func jsonValue(_ value: Any?) -> Any {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value
        case .none:
            return NSNull()
        case let value?:
            return String(describing: value)
        }
    }

    private func attachFailureArtifacts(for app: XCUIApplication) {
        add(screenshotAttachment(named: "vanmo-ui-failure.png"))
        do {
            add(try treeAttachment(for: app, named: "vanmo-ui-failure-tree.json"))
        } catch {
            print("[VanmoUI] failed to attach UI tree: \(error.localizedDescription)")
        }
    }
}
