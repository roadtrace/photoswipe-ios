import XCTest

final class FlowTests: XCTestCase {
    func testPendingTrashReviewCanKeepPhoto() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launchWithPhotoAccess(app)
        XCTAssertTrue(app.buttons["source-all"].waitForExistence(timeout: 30))
        app.buttons["source-all"].tap()
        let trash = app.buttons["action-trash"]
        XCTAssertTrue(trash.waitForExistence(timeout: 10))
        trash.tap()
        let review = app.buttons.containing(.staticText, identifier: "Review 1").firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()
        let checkbox = app.buttons.matching(identifier: "review-toggle").firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10))
        capture(app, name: "pending-trash-review")
        checkbox.tap()
        XCTAssertFalse(app.buttons["confirm-deletion"].isEnabled)
        app.buttons["review-close"].tap()
        XCTAssertFalse(review.exists)
    }

    func testPreviewSavedResultsAndDeletionReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launchWithPhotoAccess(app)
        let duplicates = app.buttons["source-duplicates"]
        XCTAssertTrue(duplicates.waitForExistence(timeout: 30))
        duplicates.tap()
        let photo = app.buttons.matching(identifier: "duplicate-photo").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 60))

        photo.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["preview-close"].waitForExistence(timeout: 10))
        let zoom = app.scrollViews["zoom-photo"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 20))
        capture(app, name: "comparison-fit")
        zoom.doubleTap()
        capture(app, name: "comparison-preview")
        app.buttons["preview-close"].tap()
        // Long press must not also toggle deletion.
        XCTAssertTrue(app.buttons["Nothing selected"].exists)

        for index in 0..<3 {
            app.buttons.matching(identifier: "duplicate-photo").element(boundBy: index).tap()
        }
        let review = app.buttons["review-duplicates"]
        XCTAssertTrue(app.staticTexts["Review 3"].waitForExistence(timeout: 5))
        capture(app, name: "duplicate-groups")
        app.buttons["duplicates-back"].tap()
        app.buttons["source-duplicates"].tap()
        XCTAssertTrue(app.staticTexts["Review 3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Scanning for duplicates"].exists)

        // A new process must restore groups and choices without a scan.
        app.terminate()
        launchWithPhotoAccess(app)
        XCTAssertTrue(duplicates.waitForExistence(timeout: 30))
        duplicates.tap()
        XCTAssertTrue(app.staticTexts["Review 3"].waitForExistence(timeout: 5))
        review.tap()
        let tile = app.buttons.matching(identifier: "review-photo").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        capture(app, name: "deletion-review")
        tile.tap()
        XCTAssertTrue(app.buttons["preview-close"].waitForExistence(timeout: 10))
        app.buttons["preview-close"].tap()
        for toggle in app.buttons.matching(identifier: "review-toggle").allElementsBoundByIndex { toggle.tap() }
        XCTAssertFalse(app.buttons["confirm-deletion"].isEnabled)
        app.buttons["review-close"].tap()
        XCTAssertTrue(app.buttons["Nothing selected"].waitForExistence(timeout: 5))
    }

    func testRandomSourceOpensDeck() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launchWithPhotoAccess(app)
        let random = app.buttons["source-random"]
        XCTAssertTrue(random.waitForExistence(timeout: 30))
        if !random.isHittable { app.swipeUp() }
        capture(app, name: "source-picker")
        random.tap()
        XCTAssertTrue(app.staticTexts["RANDOM"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["action-heart.fill"].isEnabled)
        capture(app, name: "random-deck")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchWithPhotoAccess(_ app: XCUIApplication) {
        let handler = addUIInterruptionMonitor(withDescription: "Photos access") { alert in
            for title in ["Allow Full Access", "Allow Access to All Photos", "Allow"] {
                if alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            }
            return false
        }
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for target in [springboard, app] {
            if target.alerts.firstMatch.waitForExistence(timeout: 3) {
                let alert = target.alerts.firstMatch
                for title in ["Allow Full Access", "Allow Access to All Photos", "Allow"] {
                    if alert.buttons[title].exists { alert.buttons[title].tap(); break }
                }
            }
        }
        // A safe blank area triggers XCTest's interruption handler if the
        // permission sheet arrived after the initial checks.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        removeUIInterruptionMonitor(handler)
    }
}
