import XCTest

final class ZhouJiUITests: XCTestCase {
    @MainActor
    func testColdLaunchUsesV3NavigationAndStartsOnToday() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["粥记"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["添加任务"].exists)
        XCTAssertTrue(app.buttons["tab.today"].isSelected)
        XCTAssertTrue(app.buttons["tab.goals"].exists)
        XCTAssertTrue(app.buttons["tab.records"].exists)
        XCTAssertTrue(app.buttons["tab.profile"].exists)
    }

    @MainActor
    func testProfileTabShowsTruthfulLocalOverview() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "profile"]
        app.launch()

        XCTAssertTrue(app.staticTexts["我的"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["profile.completed"].label, "0 件")
        XCTAssertEqual(app.staticTexts["profile.weekFocus"].label, "0分钟")
        XCTAssertEqual(app.staticTexts["profile.completionRate"].label, "0%")
        XCTAssertTrue(app.staticTexts["数据与存储"].exists)
        XCTAssertTrue(app.buttons["外观"].exists)
        XCTAssertTrue(app.buttons["关于粥记"].exists)
        XCTAssertTrue(app.buttons["tab.profile"].isSelected)
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

        app.buttons["tab.today"].tap()
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
        app.buttons["tab.today"].tap()
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

        app.buttons["tab.goals"].tap()
        app.staticTexts["完成毕业论文"].tap()
        XCTAssertTrue(app.staticTexts["写论文摘要"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testDefaultGoalsShowRecommendedArtworkAndAllowManualChoice() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals", "-appAppearance", "light"]
        app.launch()

        createGoal(named: "高数", in: app)
        createGoal(named: "切记1", in: app)
        saveScreenshot("goals-default-artwork-light", app: app)

        app.staticTexts["高数"].tap()
        app.buttons["目标设置"].tap()
        XCTAssertTrue(app.images["当前图标，学习"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["goal.icon.scope"].isSelected)
        saveScreenshot("goal-artwork-picker", app: app)

        app.buttons["goal.icon.briefcase"].tap()
        XCTAssertTrue(app.images["当前图标，工作"].waitForExistence(timeout: 2))
        app.buttons["保存设置"].tap()
        app.buttons["目标设置"].tap()
        XCTAssertTrue(app.buttons["goal.icon.briefcase"].isSelected)
        XCTAssertTrue(app.images["当前图标，工作"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["切记1"].tap()
        app.buttons["目标设置"].tap()
        XCTAssertTrue(app.images["当前图标，目标"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["goal.icon.scope"].isSelected)
        app.buttons["goal.icon.book.closed"].tap()
        app.buttons["保存设置"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        saveScreenshot("goals-independent-icons", app: app)
        app.staticTexts["高数"].tap()
        app.buttons["目标设置"].tap()
        XCTAssertTrue(app.images["当前图标，工作"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["goal.icon.briefcase"].isSelected)
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
        app.buttons["tab.records"].tap()

        XCTAssertTrue(app.staticTexts["记录"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["records.today.completed"].label, "1 件")
        XCTAssertEqual(app.staticTexts["records.week.completed"].label, "1 件")
        XCTAssertNotEqual(app.staticTexts["records.today.duration"].label, "0分钟")
        XCTAssertNotEqual(app.staticTexts["records.week.duration"].label, "0分钟")
        XCTAssertTrue(app.staticTexts["准备考试"].exists)
    }

    @MainActor
    func testReferenceAppearanceAndNavigation() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData", "-appAppearance", "light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["整理开题资料"].waitForExistence(timeout: 3))
        saveScreenshot("today-light", app: app)
        app.buttons["tab.goals"].tap()
        XCTAssertTrue(app.staticTexts["论文"].waitForExistence(timeout: 2))
        saveScreenshot("goals-light", app: app)
        for _ in 0..<3 where !app.buttons["新建目标"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["新建目标"].isHittable)
        XCTAssertTrue(app.staticTexts["iOS App"].exists)
        for _ in 0..<3 where !app.buttons["全部"].isHittable { app.swipeDown() }
        app.buttons["已完成"].tap()
        XCTAssertTrue(app.staticTexts["这里还没有目标"].waitForExistence(timeout: 2))
        app.buttons["全部"].tap()
        XCTAssertTrue(app.staticTexts["论文"].waitForExistence(timeout: 2))
        app.buttons["tab.records"].tap()
        XCTAssertTrue(app.staticTexts["records.today.completed"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["records.today.completed"].label, "2 件")
        saveScreenshot("records-light", app: app)
        app.buttons["records.period.week"].tap()
        XCTAssertTrue(app.buttons["records.period.week"].isSelected)
        XCTAssertTrue(app.staticTexts["records.week.duration"].isHittable)
        app.buttons["records.period.today"].tap()
        XCTAssertTrue(app.staticTexts["records.today.completed"].isHittable)
        app.buttons["tab.today"].tap()
        app.buttons["开始计时"].firstMatch.tap()
        XCTAssertTrue(app.buttons["结束计时"].waitForExistence(timeout: 2))
        app.buttons["结束计时"].tap()
        XCTAssertTrue(app.staticTexts["整理开题资料"].waitForExistence(timeout: 2))
        app.buttons["完成任务"].firstMatch.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "完成任务").count, 2)
        let row = app.cells.containing(.staticText, identifier: "投递实习简历").element
        row.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertTrue(app.buttons["撤销"].waitForExistence(timeout: 2))
        app.buttons["撤销"].tap()
        XCTAssertTrue(app.staticTexts["投递实习简历"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testTodayAppearanceSwitching() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData"]
        app.launch()
        XCTAssertTrue(app.staticTexts["整理开题资料"].waitForExistence(timeout: 3))

        for (appearance, screenshot) in [("深色模式", "today-dark"),
                                        ("浅色模式", "today-switched-light"),
                                        ("深色模式", "today-switched-dark")] {
            app.buttons["tab.profile"].tap()
            let settings = app.buttons["外观"]
            for _ in 0..<3 where !settings.isHittable { app.swipeUp() }
            XCTAssertTrue(settings.isHittable)
            settings.tap()
            app.buttons[appearance].tap()
            XCTAssertEqual(settings.value as? String, appearance)
            app.buttons["tab.today"].tap()
            XCTAssertTrue(app.staticTexts["整理开题资料"].waitForExistence(timeout: 2))
            XCTAssertTrue(app.buttons["开始计时"].firstMatch.isHittable)
            saveScreenshot(screenshot, app: app)
            app.buttons["tab.goals"].tap()
            XCTAssertTrue(app.staticTexts["论文"].waitForExistence(timeout: 2))
            saveScreenshot(screenshot.replacingOccurrences(of: "today", with: "goals"), app: app)
        }
    }

    @MainActor
    func testReferenceAppearanceInDarkModeAndLargeText() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData", "-appAppearance", "dark",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        XCTAssertTrue(app.buttons["添加任务"].waitForExistence(timeout: 3))
        saveScreenshot("today-dark-large-text", app: app)
        app.buttons["tab.goals"].tap()
        XCTAssertTrue(app.buttons["全部"].waitForExistence(timeout: 2))
        saveScreenshot("goals-dark-large-text", app: app)
        app.buttons["tab.records"].tap()
        XCTAssertTrue(app.buttons["records.period.week"].waitForExistence(timeout: 2))
        app.buttons["records.period.week"].tap()
        XCTAssertTrue(app.staticTexts["records.week.completed"].isHittable)
        saveScreenshot("records-dark-large-text", app: app)
    }

    @MainActor
    private func saveScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
