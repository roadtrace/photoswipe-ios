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
        XCTAssertTrue(app.buttons["No photos selected"].exists)
        app.buttons["Close"].tap()
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
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        let zoom = app.scrollViews["zoom-photo"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 20))
        zoom.doubleTap()
        capture(app, name: "comparison-preview")
        app.buttons["Done"].tap()
        // Long press must not also toggle deletion.
        XCTAssertTrue(app.buttons["Nothing selected"].exists)

        photo.tap()
        let review = app.buttons["Review 1 photos"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        capture(app, name: "duplicate-groups")
        app.buttons["duplicates-back"].tap()
        app.buttons["source-duplicates"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Scanning for duplicates"].exists)

        // A new process must restore groups and choices without a scan.
        app.terminate()
        launchWithPhotoAccess(app)
        XCTAssertTrue(duplicates.waitForExistence(timeout: 30))
        duplicates.tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        let tile = app.buttons.matching(identifier: "review-photo").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        capture(app, name: "deletion-review")
        tile.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        app.buttons.matching(identifier: "review-toggle").firstMatch.tap()
        XCTAssertTrue(app.buttons["No photos selected"].exists)
        XCTAssertFalse(app.buttons["No photos selected"].isEnabled)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Nothing selected"].waitForExistence(timeout: 5))
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
