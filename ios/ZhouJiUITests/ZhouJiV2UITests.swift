import XCTest

final class ZhouJiUITests: XCTestCase {
    @MainActor
    func testAccountLibrarySwitchRebuildsListsAndStatistics() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData", "-ZJIsolationSampleData", "-ZJInitialTab", "profile"]
        app.launch()
        openOverview(in: app)
        XCTAssertEqual(app.staticTexts["profile.completed"].label, "1 件")
        app.buttons["profile.closePanel"].tap()
        openPreferences(in: app)
        XCTAssertTrue(app.staticTexts["library.current"].waitForExistence(timeout: 4))
        let guest = app.buttons["library.guest"]
        for _ in 0..<3 where !guest.isHittable { app.swipeUp() }
        guest.tap()
        XCTAssertTrue(app.buttons["profile.settings"].waitForExistence(timeout: 4))
        openOverview(in: app)
        XCTAssertEqual(app.staticTexts["profile.completed"].label, "7 件")
        app.buttons["profile.closePanel"].tap()
        app.buttons["tab.today"].tap()
        XCTAssertTrue(app.staticTexts["整理开题资料"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["账户独有任务"].exists)
        app.buttons["tab.profile"].tap()
        openPreferences(in: app)
        let account = app.buttons["library.account"]
        for _ in 0..<3 where !account.isHittable { app.swipeUp() }
        account.tap()
        XCTAssertTrue(app.buttons["profile.settings"].waitForExistence(timeout: 4))
        openOverview(in: app)
        XCTAssertEqual(app.staticTexts["profile.completed"].label, "1 件")
        app.buttons["profile.closePanel"].tap()
        app.buttons["tab.today"].tap()
        XCTAssertTrue(app.staticTexts["账户独有任务"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["整理开题资料"].exists)
    }

    @MainActor
    func testBackupRestoreProtectsCurrentRunningTimer() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData"]
        app.launch()
        app.buttons["开始计时"].firstMatch.tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 3))
        app.buttons["收起"].tap()
        app.buttons["tab.profile"].tap()
        openPreferences(in: app)
        let restore = app.buttons["backup.import"]
        for _ in 0..<5 where !restore.isHittable { app.swipeUp() }
        XCTAssertTrue(restore.isHittable)
        restore.tap()
        let message = app.staticTexts["backup.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 3))
        XCTAssertTrue(message.label.contains("请先结束当前计时"))
        app.buttons["profile.closePanel"].tap()
        app.buttons["tab.today"].tap()
        XCTAssertTrue(app.buttons["查看当前计时"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testColdLaunchUsesV3NavigationAndStartsOnToday() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.buttons["添加任务"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["添加任务"].exists)
        let firstTask = app.buttons["today.firstTask"]
        XCTAssertTrue(firstTask.isHittable)
        XCTAssertEqual(firstTask.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertGreaterThan(firstTask.frame.height, 120)
        XCTAssertLessThanOrEqual(firstTask.frame.maxY, app.buttons["tab.today"].frame.minY)
        XCTAssertFalse(app.staticTexts["今天想做点什么？"].exists)
        XCTAssertTrue(app.buttons["tab.today"].isSelected)
        XCTAssertTrue(app.buttons["tab.goals"].exists)
        XCTAssertTrue(app.buttons["tab.calendar"].exists)
        XCTAssertTrue(app.buttons["tab.profile"].exists)
        firstTask.tap()
        XCTAssertTrue(app.textFields["今天要做什么？"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testProfileTabShowsTruthfulLocalOverview() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "profile"]
        app.launch()

        XCTAssertTrue(app.staticTexts["一粥又一周"].firstMatch.waitForExistence(timeout: 3))
        openOverview(in: app)
        XCTAssertEqual(app.staticTexts["profile.completed"].label, "0 件")
        XCTAssertEqual(app.staticTexts["profile.weekFocus"].label, "0分钟")
        XCTAssertEqual(app.staticTexts["profile.completionRate"].label, "0%")
        app.buttons["profile.closePanel"].tap()
        openPreferences(in: app)
        for _ in 0..<6 where !app.staticTexts["数据与存储"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["数据与存储"].exists)
        XCTAssertTrue(app.buttons["外观"].exists)
        XCTAssertTrue(app.buttons["关于粥记"].exists)
        XCTAssertTrue(app.staticTexts["游客模式"].exists)
        XCTAssertTrue(app.staticTexts["登录后可保留账户身份。云同步尚未上线，当前数据仍仅保存在本机。"].exists)
        XCTAssertFalse(app.staticTexts["sync.title"].exists)
        app.buttons["profile.closePanel"].tap()
        XCTAssertTrue(app.buttons["tab.profile"].isSelected)
    }

    @MainActor
    func testProfileMenuOpensCalendarAndNestedAbout() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "profile", "-appAppearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["profile.review"].waitForExistence(timeout: 3))
        app.buttons["profile.review"].tap()
        XCTAssertTrue(app.buttons["calendar.today"].waitForExistence(timeout: 3))
        app.buttons["profile.closePanel"].coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.04)).tap()
        openPreferences(in: app)
        app.buttons["关于粥记"].tap()
        XCTAssertTrue(app.staticTexts["粥记"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["偏好设置"].waitForExistence(timeout: 3))
        app.buttons["profile.closePanel"].tap()
        XCTAssertTrue(app.buttons["profile.settings"].isHittable)
    }

    @MainActor
    func testContentSyncCardAppearsOnlyWhenFlagEnabled() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += [
            "-ZJPreviewSampleData", "-ZJIsolationSampleData", "-ZJInitialTab", "profile", "-ZJSyncContent"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["一粥又一周"].firstMatch.waitForExistence(timeout: 4))
        openPreferences(in: app)
        XCTAssertTrue(app.staticTexts["账户记录 · 离线"].waitForExistence(timeout: 3)
                      || app.staticTexts["账户的本机记录"].waitForExistence(timeout: 2)
                      || app.buttons["library.guest"].waitForExistence(timeout: 2))
        // Sync card is opt-in; scroll until its upload control appears.
        let upload = app.buttons["sync.upload"]
        var found = false
        for _ in 0..<8 {
            if upload.exists || upload.isHittable {
                found = true
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(found, "sync.upload should appear when -ZJSyncContent is set")
        XCTAssertTrue(app.buttons["sync.restore"].exists)
        XCTAssertTrue(app.buttons["sync.pushPending"].exists)
    }

    @MainActor
    func testWeChatLoginWithoutInstalledWeChatKeepsGuestState() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "profile"]
        app.launch()
        openPreferences(in: app)
        let button = app.buttons["account.wechatLogin"]
        if !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let error = app.staticTexts["account.message"]
        XCTAssertTrue(error.waitForExistence(timeout: 35))
        XCTAssertTrue(error.label.contains("微信") || error.label.contains("登录服务"))
        XCTAssertFalse(app.buttons["account.logout"].exists)
        XCTAssertTrue(button.isEnabled)
    }

    @MainActor
    func testGoalTaskLifecycleUpdatesProgressAndSupportsUndo() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals"]
        app.launch()

        XCTAssertTrue(app.staticTexts["我的目标"].firstMatch.waitForExistence(timeout: 3))
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
    func testCompletedTimedGoalAppearsInCalendar() async throws {
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
        app.buttons["tab.calendar"].tap()

        XCTAssertTrue(app.staticTexts["calendar.selectedDate"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["calendar.completed"].label, "1 件完成")
        XCTAssertFalse(app.staticTexts["calendar.duration"].label.contains("0分钟"))
        app.buttons["calendar.summary"].tap()
        XCTAssertTrue(app.staticTexts["复习错题"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "准备考试")).firstMatch.exists)
        app.buttons["calendar.closeDetails"].tap()
        XCTAssertTrue(app.buttons["calendar.summary"].isHittable)

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
        app.buttons["目标筛选"].tap()
        app.buttons["已完成"].tap()
        XCTAssertTrue(app.staticTexts["这里还没有目标"].waitForExistence(timeout: 2))
        app.buttons["目标筛选"].tap()
        app.buttons["全部"].tap()
        XCTAssertTrue(app.staticTexts["论文"].waitForExistence(timeout: 2))
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.staticTexts["calendar.completed"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["calendar.completed"].label, "2 件完成")
        saveScreenshot("calendar-light", app: app)
        app.buttons["calendar.previousMonth"].tap()
        XCTAssertTrue(app.staticTexts["calendar.empty"].waitForExistence(timeout: 2))
        app.buttons["calendar.today"].tap()
        XCTAssertEqual(app.staticTexts["calendar.completed"].label, "2 件完成")
        app.buttons["tab.profile"].tap()
        XCTAssertTrue(app.staticTexts["一粥又一周"].waitForExistence(timeout: 2))
        saveScreenshot("profile-light", app: app)
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
    func testHeaderNewGoalStaysFixedWhileScrollingAndReturnsAfterCancel() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals", "-ZJPreviewSampleData", "-appAppearance", "dark",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let newGoal = app.buttons["新建目标"]
        XCTAssertTrue(newGoal.waitForExistence(timeout: 3))
        let initialFrame = newGoal.frame
        let initialGoalY = app.staticTexts["求职"].frame.minY
        app.swipeUp()
        XCTAssertLessThan(app.staticTexts["求职"].frame.minY, initialGoalY)
        XCTAssertTrue(newGoal.isHittable)
        XCTAssertEqual(newGoal.frame.minY, initialFrame.minY, accuracy: 1)
        XCTAssertGreaterThan(newGoal.frame.midX, app.frame.midX)
        XCTAssertLessThan(newGoal.frame.midY, app.frame.midY)
        saveScreenshot("goals-header-add-scrolled", app: app)
        // Tap the edge of the 44pt target outside the painted 36pt circle.
        newGoal.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.04)).tap()
        XCTAssertTrue(app.textFields["目标名称"].waitForExistence(timeout: 2))
        XCTAssertFalse(newGoal.exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(newGoal.waitForExistence(timeout: 2))
        XCTAssertTrue(newGoal.isHittable)
    }

    @MainActor
    func testFloatingAddTaskRemainsUsableWithRunningTimer() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData", "-appAppearance", "dark"]
        app.launch()
        app.buttons["开始计时"].firstMatch.tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 2))
        app.buttons["收起"].tap()

        let addTask = app.buttons["添加任务"]
        let currentTimer = app.buttons["查看当前计时"]
        XCTAssertTrue(addTask.waitForExistence(timeout: 2))
        XCTAssertTrue(addTask.isHittable)
        XCTAssertTrue(currentTimer.isHittable)
        XCTAssertFalse(addTask.frame.intersects(currentTimer.frame))
        XCTAssertGreaterThan(addTask.frame.midX, app.frame.midX)
        XCTAssertLessThanOrEqual(addTask.frame.maxY, app.buttons["tab.today"].frame.minY)
        saveScreenshot("today-floating-glass-active-timer", app: app)

        addTask.tap()
        XCTAssertTrue(app.textFields["今天要做什么？"].waitForExistence(timeout: 2))
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
            openPreferences(in: app)
            let settings = app.buttons["外观"]
            for _ in 0..<3 where !settings.isHittable { app.swipeUp() }
            XCTAssertTrue(settings.isHittable)
            settings.tap()
            app.buttons[appearance].tap()
            XCTAssertEqual(settings.value as? String, appearance)
            app.buttons["profile.closePanel"].tap()
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
        XCTAssertTrue(app.buttons["目标筛选"].waitForExistence(timeout: 2))
        saveScreenshot("goals-dark-large-text", app: app)
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.previousMonth"].waitForExistence(timeout: 2))
        app.buttons["calendar.previousMonth"].tap()
        XCTAssertTrue(app.staticTexts["calendar.empty"].waitForExistence(timeout: 2))
        saveScreenshot("calendar-dark-large-text", app: app)
        app.buttons["tab.profile"].tap()
        XCTAssertTrue(app.buttons["profile.overview"].isHittable)
        XCTAssertTrue(app.buttons["profile.settings"].isHittable)
        openOverview(in: app)
        XCTAssertTrue(app.staticTexts["profile.weekFocus"].exists)
        saveScreenshot("profile-overview-dark-large-text", app: app)
        app.buttons["profile.closePanel"].tap()
    }

    @MainActor
    func testCalendarChangesDateMonthAndReturnsToToday() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData", "-ZJInitialTab", "calendar"]
        app.launch()
        XCTAssertTrue(app.staticTexts["calendar.completed"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["calendar.completed"].label, "2 件完成")
        XCTAssertFalse(app.buttons["tab.records"].exists)
        let currentDay = Calendar.current.component(.day, from: Date.now)
        XCTAssertTrue(app.buttons["calendar.day.\(currentDay)"].isSelected)
        let otherDay = currentDay == 1 ? 2 : 1
        app.buttons["calendar.day.\(otherDay)"].tap()
        XCTAssertTrue(app.buttons["calendar.day.\(otherDay)"].isSelected)
        XCTAssertTrue(app.staticTexts["calendar.selectedDate"].label.contains("\(otherDay)日"))
        app.buttons["calendar.nextMonth"].tap()
        XCTAssertTrue(app.staticTexts["calendar.empty"].waitForExistence(timeout: 2))
        app.buttons["calendar.today"].tap()
        XCTAssertTrue(app.buttons["calendar.day.\(currentDay)"].isSelected)
        XCTAssertEqual(app.staticTexts["calendar.completed"].label, "2 件完成")
    }

    @MainActor
    private func openPreferences(in app: XCUIApplication) {
        let settings = app.buttons["profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.navigationBars["偏好设置"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func openOverview(in app: XCUIApplication) {
        let overview = app.buttons["profile.overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 3))
        overview.tap()
        XCTAssertTrue(app.staticTexts["profile.completed"].waitForExistence(timeout: 3))
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
