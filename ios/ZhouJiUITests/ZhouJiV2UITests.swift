import XCTest

final class ZhouJiUITests: XCTestCase {
    @MainActor
    func testColdLaunchUsesV3NavigationAndStartsOnToday() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["粥记"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["添加任务"].exists)
        XCTAssertTrue(app.tabBars.buttons["今天"].isSelected)
        XCTAssertTrue(app.tabBars.buttons["目标"].exists)
        XCTAssertTrue(app.tabBars.buttons["记录"].exists)
    }

    @MainActor
    func testGoalTaskLifecycleUpdatesProgressAndSupportsUndo() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals"]
        app.launch()

        XCTAssertTrue(app.staticTexts["目标"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["新建目标"].tap()

        let goalField = app.textFields["目标名称"]
        XCTAssertTrue(goalField.waitForExistence(timeout: 2))
        goalField.tap()
        goalField.typeText("完成毕业论文")
        app.buttons["创建"].tap()

        let goalName = app.staticTexts["完成毕业论文"]
        XCTAssertTrue(goalName.waitForExistence(timeout: 2))
        goalName.tap()

        XCTAssertTrue(app.staticTexts["0%"].waitForExistence(timeout: 2))

        let taskField = app.textFields["添加一个小任务"]
        taskField.tap()
        taskField.typeText("写摘要")
        app.buttons["添加"].tap()

        let taskName = app.staticTexts["写摘要"]
        XCTAssertTrue(taskName.waitForExistence(timeout: 2))
        app.buttons["完成任务"].tap()
        XCTAssertTrue(app.staticTexts["100%"].waitForExistence(timeout: 2))

        let taskRow = app.cells.containing(.staticText, identifier: "写摘要").element
        taskRow.swipeLeft()
        let deleteButton = app.buttons["删除"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        deleteButton.tap()
        XCTAssertTrue(app.buttons["撤销"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["0%"].exists)

        app.buttons["撤销"].tap()
        XCTAssertTrue(app.staticTexts["100%"].waitForExistence(timeout: 2))
        XCTAssertTrue(taskName.exists)
    }

    @MainActor
    func testDeletingGoalKeepsTaskAndRemovesItsAssignment() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals"]
        app.launch()

        createGoal(named: "保持运动", in: app)
        app.staticTexts["保持运动"].tap()
        createTask(named: "散步二十分钟", in: app)

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.tap()
        let goalRow = app.cells.containing(.staticText, identifier: "保持运动").element
        goalRow.swipeLeft()
        app.buttons["删除"].tap()

        let confirmDeletion = app.buttons["删除目标"]
        XCTAssertTrue(confirmDeletion.waitForExistence(timeout: 2))
        confirmDeletion.tap()
        XCTAssertTrue(app.staticTexts["保持运动"].waitForNonExistence(timeout: 2))

        app.tabBars.buttons["今天"].tap()
        XCTAssertTrue(app.staticTexts["散步二十分钟"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["保持运动"].exists)
    }

    @MainActor
    func testCreatingTaskFromTodayCanAssignGoal() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals"]
        app.launch()

        createGoal(named: "完成毕业论文", in: app)
        app.tabBars.buttons["今天"].tap()
        app.buttons["添加任务"].tap()

        let goalPicker = app.buttons["today.goalPicker"]
        XCTAssertTrue(goalPicker.waitForExistence(timeout: 2))
        XCTAssertEqual(goalPicker.value as? String, "无目标")
        goalPicker.tap()
        app.buttons["完成毕业论文"].tap()
        XCTAssertEqual(goalPicker.value as? String, "完成毕业论文")

        let taskField = app.textFields["今天要做什么？"]
        taskField.tap()
        taskField.typeText("写论文摘要")
        app.buttons["添加"].tap()

        XCTAssertTrue(app.staticTexts["写论文摘要"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["完成毕业论文"].exists)

        app.tabBars.buttons["目标"].tap()
        app.staticTexts["完成毕业论文"].tap()
        XCTAssertTrue(app.staticTexts["写论文摘要"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testGoalSettingsCanChangeAndPersistIcon() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals"]
        app.launch()

        createGoal(named: "年度阅读", in: app)
        app.staticTexts["年度阅读"].tap()
        app.buttons["目标设置"].tap()

        XCTAssertTrue(app.navigationBars["目标设置"].waitForExistence(timeout: 2))
        let bookIcon = app.buttons["goal.icon.book.closed"]
        XCTAssertTrue(bookIcon.waitForExistence(timeout: 2))
        bookIcon.tap()
        XCTAssertTrue(app.images["当前图标，阅读"].waitForExistence(timeout: 2))
        app.buttons["保存设置"].tap()

        XCTAssertTrue(app.buttons["目标设置"].waitForExistence(timeout: 2))
        app.buttons["目标设置"].tap()
        XCTAssertTrue(app.images["当前图标，阅读"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCompletedTimedGoalAppearsInRecords() async throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals"]
        app.launch()

        createGoal(named: "准备考试", in: app)
        app.staticTexts["准备考试"].tap()
        createTask(named: "复习错题", in: app)

        let startTimer = app.buttons["开始计时"]
        XCTAssertTrue(startTimer.waitForExistence(timeout: 2))
        startTimer.tap()
        XCTAssertTrue(app.staticTexts["正在投入"].waitForExistence(timeout: 2))
        try await Task.sleep(for: .seconds(2))
        app.buttons["结束计时"].tap()

        XCTAssertTrue(app.staticTexts["复习错题"].waitForExistence(timeout: 2))
        app.buttons["完成任务"].tap()
        app.tabBars.buttons["记录"].tap()

        XCTAssertTrue(app.staticTexts["记录"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["records.today.completed"].label, "1 件")
        XCTAssertEqual(app.staticTexts["records.week.completed"].label, "1 件")
        XCTAssertNotEqual(app.staticTexts["records.today.duration"].label, "0分钟")
        XCTAssertNotEqual(app.staticTexts["records.week.duration"].label, "0分钟")
        XCTAssertTrue(app.staticTexts["准备考试"].exists)
    }

    @MainActor
    private func createGoal(named name: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["新建目标"].waitForExistence(timeout: 3))
        app.buttons["新建目标"].tap()
        let field = app.textFields["目标名称"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        field.typeText(name)
        app.buttons["创建"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 2))
    }

    @MainActor
    private func createTask(named name: String, in app: XCUIApplication) {
        let field = app.textFields["添加一个小任务"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        field.typeText(name)
        app.buttons["添加"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 2))
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZJInMemoryStore"]
        return app
    }
}
