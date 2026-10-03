import XCTest
import UIKit

final class ZhouJiUITests: XCTestCase {
    @MainActor
    func testTimerDesignKeepsGoalPauseAndFinishSemantics() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData"]
        app.launch()
        app.buttons["开始计时"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["timer.goal"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["timer.goal"].label.isEmpty)
        XCTAssertTrue(app.buttons["暂停"].isHittable)
        XCTAssertTrue(app.buttons["结束计时"].isHittable)
        saveScreenshot("secondary-timer-running", app: app)
        app.buttons["暂停"].tap()
        XCTAssertTrue(app.staticTexts["已经暂停"].waitForExistence(timeout: 3))
        saveScreenshot("secondary-timer-paused", app: app)
        app.buttons["收起"].tap()
        app.buttons["查看当前计时"].tap()
        XCTAssertTrue(app.buttons["继续"].waitForExistence(timeout: 3))
        app.buttons["继续"].tap()
        XCTAssertTrue(app.staticTexts["正在投入"].waitForExistence(timeout: 3))
        app.buttons["结束计时"].tap()
        XCTAssertTrue(app.staticTexts["整理开题资料"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["开始计时"].firstMatch.exists)
        XCTAssertFalse(app.buttons["查看当前计时"].exists)
    }

    @MainActor
    func testSecondaryProfileDesignsKeepRealDataAndNavigation() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJIsolationSampleData", "-ZJInitialTab", "profile"]
        app.launch()
        openOverview(in: app)
        XCTAssertEqual(app.staticTexts["profile.completed"].label, "1 件")
        saveScreenshot("secondary-overview", app: app)
        app.buttons["profile.closePanel"].tap()
        openPreferences(in: app)
        XCTAssertTrue(app.buttons["profile.edit"].label.contains("小粥"))
        saveScreenshot("secondary-preferences", app: app)
        app.buttons["关于粥记"].tap()
        XCTAssertTrue(app.staticTexts["一粥又一周"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["about.version"].exists)
        saveScreenshot("secondary-about", app: app)
        app.buttons["完成"].tap()
        app.buttons["profile.edit"].tap()
        XCTAssertTrue(app.textFields["profile.nickname"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["profile.avatar.leaf"].isSelected)
        saveScreenshot("secondary-profile-editor", app: app)
        app.buttons["取消"].tap()
        app.buttons["profile.closePanel"].tap()
        XCTAssertTrue(app.buttons["profile.identity"].label.contains("小粥"))
    }

    @MainActor
    func testSecondaryProfileLargeTextKeepsNavigationAndKeyboardSaveReachable() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJIsolationSampleData", "-ZJInitialTab", "profile",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openOverview(in: app)
        for identifier in ["profile.completed", "profile.weekFocus", "profile.completionRate"] {
            let value = app.staticTexts[identifier]
            for _ in 0..<6 where !value.isHittable { app.swipeUp() }
            XCTAssertTrue(value.isHittable)
            XCTAssertLessThanOrEqual(value.frame.maxX, app.frame.maxX)
        }
        saveScreenshot("secondary-overview-large", app: app)
        app.buttons["profile.closePanel"].tap()
        openPreferences(in: app)
        let about = app.buttons["关于粥记"]
        for _ in 0..<6 where !about.isHittable { app.swipeUp() }
        about.tap()
        let version = app.staticTexts["about.version"]
        for _ in 0..<6 where !version.isHittable { app.swipeUp() }
        XCTAssertTrue(version.isHittable)
        saveScreenshot("secondary-about-large", app: app)
        app.buttons["完成"].tap()
        let logout = app.buttons["account.logout"]
        for _ in 0..<8 where !logout.isHittable { app.swipeUp() }
        XCTAssertTrue(logout.isHittable)
        XCTAssertTrue(app.buttons["account.delete"].exists)
        saveScreenshot("secondary-preferences-large", app: app)
        app.buttons["profile.closePanel"].tap()
        app.buttons["profile.identity"].tap()
        let nickname = app.textFields["profile.nickname"]
        for _ in 0..<5 where !nickname.isHittable { app.swipeUp() }
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        let save = app.buttons["profile.save"]
        XCTAssertFalse(save.isEnabled)
        nickname.typeText("大字昵称")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY)
        saveScreenshot("secondary-profile-keyboard-large", app: app)
        save.tap()
        XCTAssertTrue(app.buttons["profile.identity"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["profile.identity"].label.contains("大字昵称"))
    }

    @MainActor
    func testProfileBackNavigationStaysClearDuringLargeTextInput() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJIsolationSampleData", "-ZJInitialTab", "profile",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let identity = app.buttons["profile.identity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 3))
        let originalIdentity = identity.label
        identity.tap()
        let nickname = app.textFields["profile.nickname"]
        for _ in 0..<5 where !nickname.isHittable { app.swipeUp() }
        XCTAssertTrue(nickname.isHittable)
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        nickname.typeText("大字昵称")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let cancel = app.buttons["取消"]
        XCTAssertTrue(cancel.isHittable)
        saveScreenshot("secondary-profile-navigation-large-keyboard", app: app)
        assertPaperBehindBackNavigation(in: app, button: cancel)
        XCTAssertTrue(app.buttons["profile.save"].isHittable)
        cancel.tap()
        XCTAssertTrue(identity.waitForExistence(timeout: 3))
        XCTAssertEqual(identity.label, originalIdentity)
    }

    @MainActor
    func testTimerLargeTextKeepsControlsAndElapsedTimeReachable() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let start = app.buttons["开始计时"].firstMatch
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["暂停"].isHittable)
        XCTAssertTrue(app.buttons["结束计时"].isHittable)
        let elapsed = app.descendants(matching: .any).matching(identifier: "timer.elapsed").firstMatch
        for _ in 0..<5 where elapsed.frame.maxY > app.buttons["暂停"].frame.minY {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(elapsed.isHittable)
        XCTAssertLessThanOrEqual(elapsed.frame.maxY, app.buttons["暂停"].frame.minY)
        XCTAssertNotNil(elapsed.value as? String)
        saveScreenshot("secondary-timer-large", app: app)
        app.buttons["暂停"].tap()
        XCTAssertTrue(app.buttons["继续"].waitForExistence(timeout: 3))
        app.buttons["继续"].tap()
        app.buttons["结束计时"].tap()
        XCTAssertTrue(app.buttons["开始计时"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["查看当前计时"].exists)
    }

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
        // This completed task sits below the quiet Today illustration.
        for _ in 0..<4 where !app.staticTexts["账户独有任务"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["账户独有任务"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["整理开题资料"].exists)
    }

    @MainActor
    func testSettingsHideBackupControlsAndKeepRunningTimerAvailable() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData"]
        app.launch()
        app.buttons["开始计时"].firstMatch.tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 3))
        app.buttons["收起"].tap()
        app.buttons["tab.profile"].tap()
        openPreferences(in: app)
        XCTAssertTrue(app.buttons["关于粥记"].isHittable)
        saveScreenshot("profile-preferences-top", app: app)
        for _ in 0..<5 { app.swipeUp() }
        for identifier in ["backup.export", "backup.import", "backup.protection", "backup.deletedAccount"] {
            XCTAssertFalse(app.buttons[identifier].exists)
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "数据备份")).firstMatch.exists)
        saveScreenshot("profile-preferences-without-backup", app: app)
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
        XCTAssertGreaterThan(firstTask.frame.height, 100)
        XCTAssertLessThanOrEqual(firstTask.frame.maxY, app.buttons["tab.today"].frame.minY)
        let message = app.staticTexts["today.message"]
        XCTAssertTrue(message.isHittable)
        XCTAssertLessThan(message.frame.maxY, firstTask.frame.minY)
        XCTAssertLessThanOrEqual(message.frame.maxX, app.frame.width * 0.6)
        saveScreenshot("today-empty-reference", app: app)
        XCTAssertFalse(app.staticTexts["今天想做点什么？"].exists)
        XCTAssertTrue(app.buttons["tab.today"].isSelected)
        XCTAssertTrue(app.buttons["tab.goals"].exists)
        XCTAssertTrue(app.buttons["tab.calendar"].exists)
        XCTAssertTrue(app.buttons["tab.profile"].exists)
        firstTask.tap()
        XCTAssertTrue(app.textFields["今天要做什么？"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCompletingAllTasksShowsQuietTodayAndSupportsAddingAndRestoring() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-appAppearance", "light"]
        app.launch()
        app.buttons["today.firstTask"].tap()
        let field = app.textFields["今天要做什么？"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        field.typeText("读完一章书")
        app.buttons["添加"].tap()
        XCTAssertTrue(app.buttons["完成任务"].waitForExistence(timeout: 2))
        app.buttons["完成任务"].tap()

        let add = app.buttons["today.firstTask"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertTrue(add.isHittable)
        saveScreenshot("today-all-completed", app: app)
        XCTAssertEqual(add.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertGreaterThan(add.frame.height, 100)
        XCTAssertLessThanOrEqual(add.frame.maxY, app.buttons["tab.today"].frame.minY)
        XCTAssertTrue(app.staticTexts["today.message"].label.contains("今天的事都完成了"))
        XCTAssertFalse(app.buttons["恢复任务"].isHittable)

        add.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        field.typeText("喝一杯水")
        app.buttons["添加"].tap()
        XCTAssertTrue(app.buttons["完成任务"].waitForExistence(timeout: 2))
        XCTAssertFalse(add.exists)
        app.buttons["完成任务"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        for _ in 0..<4 where !app.buttons["恢复任务"].firstMatch.isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["恢复任务"].firstMatch.isHittable)
        app.cells.containing(.staticText, identifier: "喝一杯水").element.swipeLeft()
        XCTAssertTrue(app.buttons["删除"].waitForExistence(timeout: 2))
        app.buttons["删除"].tap()
        XCTAssertTrue(app.buttons["撤销"].waitForExistence(timeout: 2))
        app.buttons["撤销"].tap()
        XCTAssertTrue(app.staticTexts["喝一杯水"].waitForExistence(timeout: 2))
        for _ in 0..<4 where !app.buttons["恢复任务"].firstMatch.isHittable { app.swipeUp() }
        app.buttons["恢复任务"].firstMatch.tap()
        XCTAssertTrue(app.buttons["完成任务"].waitForExistence(timeout: 2))
        XCTAssertFalse(add.exists)
    }

    @MainActor
    func testProfileTabShowsTruthfulLocalOverview() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "profile"]
        app.launch()

        XCTAssertTrue(app.staticTexts["profile.guestName"].waitForExistence(timeout: 3))
        openOverview(in: app)
        XCTAssertEqual(app.staticTexts["profile.completed"].label, "0 件")
        XCTAssertEqual(app.staticTexts["profile.weekFocus"].label, "0分钟")
        XCTAssertEqual(app.staticTexts["profile.completionRate"].label, "0%")
        app.buttons["profile.closePanel"].tap()
        openPreferences(in: app)
        for _ in 0..<6 where !app.staticTexts["数据与存储"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["数据与存储"].exists)
        XCTAssertFalse(app.buttons["外观"].exists)
        XCTAssertTrue(app.buttons["关于粥记"].exists)
        XCTAssertTrue(app.staticTexts["游客模式"].exists)
        XCTAssertTrue(app.staticTexts["登录后可保留账户身份。云同步尚未上线，当前数据仍仅保存在本机。"].exists)
        XCTAssertFalse(app.staticTexts["sync.title"].exists)
        app.buttons["profile.closePanel"].tap()
        XCTAssertTrue(app.buttons["tab.profile"].isSelected)
    }

    @MainActor
    func testProfileUsesCalendarTabAndNestedAbout() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "profile", "-appAppearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["profile.settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["profile.review"].exists)
        XCTAssertFalse(app.buttons["日历回顾"].exists)
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.today"].waitForExistence(timeout: 3))
        app.buttons["tab.profile"].tap()
        openPreferences(in: app)
        app.buttons["关于粥记"].tap()
        XCTAssertTrue(app.staticTexts["粥记"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["profile.preferencesHeading"].waitForExistence(timeout: 3))
        app.buttons["profile.closePanel"].tap()
        XCTAssertTrue(app.buttons["profile.settings"].isHittable)
    }

    @MainActor
    func testProfileIdentityEditsNameAndAvatarAndClearsAfterLogout() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJIsolationSampleData", "-ZJInitialTab", "profile"]
        app.launch()
        let identity = app.buttons["profile.identity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 3))
        XCTAssertTrue(identity.label.contains("小粥"))
        XCTAssertEqual(identity.value as? String, "头像：新芽")
        saveScreenshot("profile-user", app: app)

        identity.tap()
        let nickname = app.textFields["profile.nickname"]
        XCTAssertTrue(nickname.waitForExistence(timeout: 3))
        XCTAssertEqual(nickname.value as? String, "小粥")
        XCTAssertTrue(app.buttons["profile.avatar.leaf"].isSelected)
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        nickname.typeText("新的昵称")
        app.buttons["profile.avatar.moon"].tap()
        app.buttons["profile.save"].tap()
        XCTAssertTrue(app.staticTexts["profile.editorHeading"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(identity.label.contains("新的昵称"))
        XCTAssertEqual(identity.value as? String, "头像：月夜")
        saveScreenshot("profile-user-updated", app: app)

        identity.tap()
        XCTAssertTrue(nickname.waitForExistence(timeout: 3))
        XCTAssertEqual(nickname.value as? String, "新的昵称")
        XCTAssertTrue(app.buttons["profile.avatar.moon"].isSelected)
        app.buttons["profile.avatar.sunrise"].tap()
        app.buttons["取消"].tap()
        XCTAssertEqual(identity.value as? String, "头像：月夜")

        identity.tap()
        XCTAssertTrue(nickname.waitForExistence(timeout: 3))
        app.buttons["profile.avatar.sunrise"].tap()
        app.buttons["profile.save"].tap()
        XCTAssertTrue(app.staticTexts["profile.editorHeading"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(identity.value as? String, "头像：榴榴")
        saveScreenshot("profile-default-avatar", app: app)

        openPreferences(in: app)
        let logout = app.buttons["account.logout"]
        for _ in 0..<8 where !logout.isHittable { app.swipeUp() }
        XCTAssertTrue(logout.isHittable)
        logout.tap()
        app.sheets.buttons["退出登录"].tap()
        XCTAssertTrue(app.staticTexts["profile.guestName"].waitForExistence(timeout: 3))
        XCTAssertFalse(identity.exists)
        saveScreenshot("profile-guest", app: app)
    }

    @MainActor
    func testProfileIdentityRemainsEditableWithLargeText() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJIsolationSampleData", "-ZJInitialTab", "profile",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        let identity = app.buttons["profile.identity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 3))
        XCTAssertTrue(identity.isHittable)
        XCTAssertTrue(identity.label.contains("小粥"))
        saveScreenshot("profile-user-large-text", app: app)
        identity.tap()
        XCTAssertTrue(app.textFields["profile.nickname"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
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
        XCTAssertTrue(app.buttons["profile.settings"].waitForExistence(timeout: 4))
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
    func testGoalTaskInputKeepsBottomNavigationVisibleAndUsable() throws {
        continueAfterFailure = false
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityM"] {
            let app = makeApp()
            app.launchArguments += ["-ZJInitialTab", "goals", "-UIPreferredContentSizeCategoryName", category]
            app.launch()
            createGoal(named: "阅读计划", in: app)
            app.staticTexts["阅读计划"].tap()
            let field = app.textFields["添加一个小任务"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.tap()
            field.typeText("Read one page")
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
            saveScreenshot("goal-task-navigation-input-\(category)", app: app)
            let tabs = ["today", "goals", "calendar", "profile"].map { app.buttons["tab.\($0)"] }
            for tab in tabs {
                XCTAssertTrue(tab.waitForExistence(timeout: 3), "输入目标任务时应保留底部导航")
                XCTAssertTrue(tab.isHittable)
                XCTAssertLessThanOrEqual(tab.frame.maxY, keyboard.frame.minY)
            }
            let add = app.buttons["添加"]
            XCTAssertTrue(add.isHittable)
            XCTAssertLessThanOrEqual(add.frame.maxY, tabs[0].frame.minY)

            tabs[0].tap()
            XCTAssertTrue(tabs[0].isSelected)
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))
            tabs[1].tap()
            XCTAssertTrue(app.staticTexts["goal.tasks.heading"].waitForExistence(timeout: 3))
            XCTAssertEqual(field.value as? String, "Read one page")
            XCTAssertTrue(app.staticTexts["0/0"].exists)
            field.tap()
            add.tap()
            XCTAssertTrue(app.staticTexts["Read one page"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["0/1"].exists)
            XCTAssertTrue(tabs[1].isSelected)
            app.terminate()
        }
    }

    @MainActor
    func testGoalTaskHeaderKeepsSizeWhileEnteringTask() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        createGoal(named: "Lalala1", in: app)
        app.staticTexts["Lalala1"].tap()

        let heading = app.staticTexts["goal.tasks.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        let initialHeading = heading.frame
        saveScreenshot("goal-task-size-before-input", app: app)
        let field = app.textFields["添加一个小任务"]
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        field.typeText("Read one page")
        saveScreenshot("goal-task-size-during-input", app: app)
        XCTAssertEqual(heading.frame.height, initialHeading.height, accuracy: 1, "输入任务时目标标题不应缩小")
        XCTAssertEqual(heading.frame.width, initialHeading.width, accuracy: 1, "输入任务时目标标题尺寸应保持一致")

        let add = app.buttons["添加"]
        XCTAssertTrue(add.isHittable)
        XCTAssertLessThanOrEqual(add.frame.maxY, app.keyboards.firstMatch.frame.minY)
        add.tap()
        XCTAssertTrue(app.staticTexts["Read one page"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["0/1"].exists)
        XCTAssertEqual(heading.frame.height, initialHeading.height, accuracy: 1)
        saveScreenshot("goal-task-size-after-input", app: app)
    }

    @MainActor
    func testGoalTaskPageAddsUnderCurrentGoalAndOpensPrintedSettings() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals", "-appAppearance", "light"]
        app.launch()
        createGoal(named: "多读书", in: app)
        app.staticTexts["多读书"].tap()

        let assignment = app.staticTexts["新任务会自动归属「多读书」"]
        XCTAssertTrue(assignment.waitForExistence(timeout: 3))
        let field = app.textFields["添加一个小任务"]
        let add = app.buttons["添加"]
        XCTAssertTrue(field.isHittable)
        XCTAssertFalse(add.isEnabled)
        saveScreenshot("goal-tasks-empty-printed", app: app)
        field.tap()
        field.typeText("读十页书")
        XCTAssertTrue(add.isEnabled)
        XCTAssertTrue(add.isHittable)
        XCTAssertLessThanOrEqual(add.frame.maxY, app.keyboards.firstMatch.frame.minY)
        saveScreenshot("goal-tasks-adding-printed", app: app)
        add.tap()
        XCTAssertTrue(app.staticTexts["读十页书"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["0/1"].exists)
        XCTAssertEqual(field.value as? String, "添加一个小任务")
        app.buttons["完成任务"].tap()
        XCTAssertTrue(app.staticTexts["100%"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1/1"].exists)
        saveScreenshot("goal-tasks-completed-printed", app: app)

        app.buttons["目标设置"].tap()
        XCTAssertTrue(app.staticTexts["goal.settings.heading"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["tab.goals"].exists)
        XCTAssertTrue(app.buttons["goal.icon.scope"].isSelected)
        XCTAssertFalse(app.buttons["保存设置"].isEnabled)
        app.buttons["goal.icon.book.closed"].tap()
        XCTAssertTrue(app.buttons["goal.icon.book.closed"].isSelected)
        saveScreenshot("goal-settings-printed", app: app)

        let name = app.textFields["目标名称"]
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        name.typeText("年度阅读")
        let save = app.buttons["保存设置"]
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(app.buttons["目标设置"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["年度阅读"].exists)
        XCTAssertTrue(app.buttons["tab.goals"].exists)
        app.buttons["目标设置"].tap()
        XCTAssertEqual(name.value as? String, "年度阅读")
        XCTAssertTrue(app.buttons["goal.icon.book.closed"].isSelected)
        app.buttons["返回目标"].tap()
        app.buttons["返回目标列表"].tap()
        app.buttons["tab.today"].tap()
        for _ in 0..<4 where !app.staticTexts["读十页书"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["读十页书"].exists)
    }

    @MainActor
    func testLongGoalNameKeepsInlineTaskAdditionReachable() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        let name = String(repeating: "阅读", count: 80)
        app.buttons["新建目标"].tap()
        let goalField = app.textFields["目标名称"]
        XCTAssertTrue(goalField.waitForExistence(timeout: 3))
        goalField.tap()
        goalField.typeText(name)
        app.buttons["创建"].tap()
        let goalTitle = app.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(goalTitle.waitForExistence(timeout: 3))
        goalTitle.tap()
        let field = app.textFields["添加一个小任务"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        saveScreenshot("goal-long-name-addition", app: app)
        XCTAssertTrue(field.isHittable)
        field.tap()
        field.typeText("读十页书")
        let add = app.buttons["添加"]
        XCTAssertTrue(add.isHittable)
        XCTAssertLessThanOrEqual(add.frame.maxY, app.keyboards.firstMatch.frame.minY)
        saveScreenshot("goal-long-name-keyboard", app: app)
        add.tap()
        XCTAssertTrue(app.staticTexts["读十页书"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testGoalPagesKeepAdditionAndSaveReachableWithLargeText() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        createGoal(named: "多读书", in: app)
        app.staticTexts["多读书"].tap()
        let field = app.textFields["添加一个小任务"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("读十页书")
        let add = app.buttons["添加"]
        XCTAssertTrue(add.isHittable)
        XCTAssertLessThanOrEqual(add.frame.maxY, app.keyboards.firstMatch.frame.minY)
        saveScreenshot("goal-tasks-large-text-keyboard", app: app)
        add.tap()
        XCTAssertTrue(app.staticTexts["读十页书"].waitForExistence(timeout: 3))
        app.buttons["目标设置"].tap()
        let reading = app.buttons["goal.icon.book.closed"]
        for _ in 0..<5 where !reading.isHittable { app.swipeUp() }
        XCTAssertTrue(reading.isHittable)
        reading.tap()
        let save = app.buttons["保存设置"]
        XCTAssertTrue(save.isHittable)
        saveScreenshot("goal-settings-large-text", app: app)
        save.tap()
        XCTAssertTrue(app.buttons["目标设置"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tab.goals"].exists)
    }

    @MainActor
    func testApprovedGoalTaskAndSettingsScreens() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals", "-appAppearance", "light"]
        app.launch()
        createGoal(named: "多读书", in: app)
        app.staticTexts["多读书"].tap()
        for title in ["选好一本书", "读第一章", "读第二章"] {
            createTask(named: title, in: app)
            app.buttons["完成任务"].firstMatch.tap()
        }
        createTask(named: "读第三章", in: app)
        createTask(named: "整理读书笔记", in: app)
        XCTAssertTrue(app.staticTexts["3/5"].exists)
        XCTAssertTrue(app.staticTexts["60%"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "完成任务").count, 2)
        XCTAssertEqual(app.buttons.matching(identifier: "恢复任务").count, 3)
        saveScreenshot("goal-tasks-approved-design", app: app)
        app.buttons["目标设置"].tap()
        XCTAssertTrue(app.buttons["goal.icon.book.closed"].waitForExistence(timeout: 3))
        app.buttons["goal.icon.book.closed"].tap()
        XCTAssertTrue(app.buttons["保存设置"].isHittable)
        saveScreenshot("goal-settings-approved-design", app: app)
        app.buttons["保存设置"].tap()
        app.buttons["返回目标列表"].tap()
        XCTAssertTrue(app.staticTexts["3/5"].waitForExistence(timeout: 3))
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

        let backButton = app.buttons["返回目标列表"]
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
    func testTodayHeaderKeepsScaleWhenTasksChange() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let greeting = app.staticTexts["today.greeting"]
        XCTAssertTrue(greeting.waitForExistence(timeout: 3))
        let originalFrame = greeting.frame
        saveScreenshot("today-scale-empty", app: app)
        assertTodayArtworkReachesScreenEdges(in: app)

        app.buttons["today.firstTask"].tap()
        let field = app.textFields["今天要做什么？"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Read one page")
        app.buttons["添加"].tap()
        XCTAssertTrue(app.staticTexts["Read one page"].waitForExistence(timeout: 3))
        saveScreenshot("today-scale-incomplete", app: app)
        assertTodayArtworkReachesScreenEdges(in: app)
        XCTAssertEqual(greeting.frame.height, originalFrame.height, accuracy: 1, "添加任务后首页插画中的文字不应随场景缩小")
        XCTAssertEqual(greeting.frame.minX, originalFrame.minX, accuracy: 1, "首页场景应保持相同的横向比例")
        XCTAssertTrue(app.buttons["tab.today"].isHittable)

        let complete = app.buttons["完成任务"].firstMatch
        for _ in 0..<3 where !complete.isHittable { app.swipeUp() }
        XCTAssertTrue(complete.isHittable)
        complete.tap()
        XCTAssertTrue(app.buttons["today.firstTask"].waitForExistence(timeout: 3))
        saveScreenshot("today-scale-completed", app: app)
        assertTodayArtworkReachesScreenEdges(in: app)
        XCTAssertEqual(greeting.frame.height, originalFrame.height, accuracy: 1)
        XCTAssertEqual(greeting.frame.minX, originalFrame.minX, accuracy: 1)

        let restore = app.buttons["恢复任务"].firstMatch
        for _ in 0..<4 where !restore.isHittable { app.swipeUp() }
        XCTAssertTrue(restore.isHittable)
        restore.tap()
        for _ in 0..<4 where !greeting.isHittable { app.swipeDown() }
        XCTAssertTrue(greeting.isHittable)
        XCTAssertEqual(greeting.frame.height, originalFrame.height, accuracy: 1)
        XCTAssertEqual(greeting.frame.minX, originalFrame.minX, accuracy: 1)
        assertTodayArtworkReachesScreenEdges(in: app)
        let restoredCompletion = app.buttons["完成任务"].firstMatch
        for _ in 0..<3 where !restoredCompletion.isHittable { app.swipeUp() }
        XCTAssertTrue(restoredCompletion.isHittable)
    }

    @MainActor
    func testLastTodayTaskCanScrollAboveFloatingAddButton() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let add = app.buttons["添加任务"]
        let lastTimer = app.buttons.matching(identifier: "开始计时").element(boundBy: 2)
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        let list = app.collectionViews.firstMatch
        XCTAssertGreaterThanOrEqual(list.frame.maxY, add.frame.maxY)
        for _ in 0..<4 {
            if lastTimer.isHittable && !lastTimer.frame.intersects(add.frame) { break }
            list.swipeUp()
        }
        XCTAssertTrue(lastTimer.isHittable, "最后一项任务可以滚动到完整可操作的位置")
        XCTAssertFalse(lastTimer.frame.intersects(add.frame))
        saveScreenshot("today-floating-add-multiple-tasks", app: app)
        lastTimer.tap()
        XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSingleTodayTaskStartsTimerWithoutAddButtonOverlap() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        app.buttons["today.firstTask"].tap()
        let field = app.textFields["今天要做什么？"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("读一页书")
        app.buttons["添加"].tap()

        let start = app.buttons["开始计时"].firstMatch
        let add = app.buttons["添加任务"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        saveScreenshot("today-single-task-ready", app: app)
        XCTAssertTrue(start.isHittable, "刚添加任务后应可直接开始计时，无需先滚动找入口")
        XCTAssertFalse(start.frame.intersects(add.frame), "新增按钮不能遮住任务计时入口")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.exists)
        XCTAssertGreaterThanOrEqual(list.frame.maxY, add.frame.maxY, "列表应延伸到悬浮加号下方，不为加号保留固定横条")
        XCTAssertLessThanOrEqual(start.frame.maxY, app.buttons["tab.today"].frame.minY)
        start.tap()
        XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 3))
        app.buttons["收起"].tap()

        let current = app.buttons["查看当前计时"]
        XCTAssertTrue(current.waitForExistence(timeout: 3))
        XCTAssertTrue(current.isHittable)
        XCTAssertTrue(add.isHittable)
        XCTAssertFalse(current.frame.intersects(add.frame))
        let taskTimer = app.buttons["查看计时"].firstMatch
        XCTAssertTrue(taskTimer.isHittable, "收起计时页后任务操作仍应可见")
        XCTAssertFalse(taskTimer.frame.intersects(current.frame))
        XCTAssertFalse(taskTimer.frame.intersects(add.frame))
        saveScreenshot("today-single-task-running", app: app)
        current.tap()
        app.buttons["结束计时"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        XCTAssertTrue(start.isHittable)
        XCTAssertFalse(start.frame.intersects(add.frame))
    }

    @MainActor
    func testNewTaskOpensKeyboardAndKeepsSubmitReachable() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        app.buttons["today.firstTask"].tap()

        let field = app.textFields["今天要做什么？"]
        let keyboard = app.keyboards.firstMatch
        let submit = app.buttons["添加"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3), "Opening a task should focus its name automatically")
        XCTAssertTrue(field.isHittable)
        XCTAssertTrue(submit.isHittable)
        XCTAssertFalse(submit.isEnabled)
        XCTAssertLessThanOrEqual(submit.frame.maxY, keyboard.frame.minY)

        field.typeText("   ")
        XCTAssertFalse(submit.isEnabled)
        app.buttons["清空任务名称"].tap()
        XCTAssertTrue(keyboard.exists)
        field.typeText("读十页书")
        XCTAssertTrue(submit.isEnabled)
        XCTAssertTrue(submit.isHittable)
        XCTAssertLessThanOrEqual(submit.frame.maxY, keyboard.frame.minY)
        saveScreenshot("new-task-reference-keyboard", app: app)
        submit.tap()
        XCTAssertTrue(app.staticTexts["读十页书"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tab.today"].isHittable)
    }

    @MainActor
    func testNewTaskLargeTextKeepsCreationReachable() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        app.buttons["today.firstTask"].tap()
        let field = app.textFields["今天要做什么？"]
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        XCTAssertTrue(field.isHittable)
        field.typeText("大字也能记一件事")
        let submit = app.buttons["添加"]
        XCTAssertTrue(submit.isEnabled)
        XCTAssertTrue(submit.isHittable)
        XCTAssertLessThanOrEqual(submit.frame.maxY, keyboard.frame.minY)
        saveScreenshot("new-task-large-text-keyboard", app: app)
        submit.tap()
        XCTAssertTrue(app.staticTexts["大字也能记一件事"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tab.today"].isHittable)
    }

    @MainActor
    func testTaskEditorHidesNavigationUntilReturning() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        app.buttons["today.firstTask"].tap()
        XCTAssertTrue(app.textFields["今天要做什么？"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["tab.today"].exists)
        app.buttons["返回今天"].tap()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["today.firstTask"].isHittable)
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

        app.buttons["返回目标"].tap()
        app.buttons["返回目标列表"].tap()
        app.staticTexts["切记1"].tap()
        app.buttons["目标设置"].tap()
        XCTAssertTrue(app.images["当前图标，目标"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["goal.icon.scope"].isSelected)
        app.buttons["goal.icon.book.closed"].tap()
        app.buttons["保存设置"].tap()

        app.buttons["返回目标列表"].tap()
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

        XCTAssertTrue(app.staticTexts["goal.settings.heading"].waitForExistence(timeout: 2))
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
        XCTAssertTrue(app.staticTexts["profile.guestName"].waitForExistence(timeout: 2))
        saveScreenshot("profile-light", app: app)
        app.buttons["tab.today"].tap()
        app.buttons["开始计时"].firstMatch.tap()
        XCTAssertTrue(app.buttons["结束计时"].waitForExistence(timeout: 2))
        app.buttons["结束计时"].tap()
        XCTAssertTrue(app.staticTexts["整理开题资料"].waitForExistence(timeout: 2))
        app.buttons["完成任务"].firstMatch.tap()
        for title in ["投递实习简历", "练习 SwiftUI"] {
            let remaining = app.cells.containing(.staticText, identifier: title).element
            for _ in 0..<4 where !remaining.isHittable { app.swipeUp() }
            XCTAssertTrue(remaining.isHittable)
            XCTAssertTrue(remaining.buttons["完成任务"].exists)
        }
        let row = app.cells.containing(.staticText, identifier: "投递实习简历").element
        row.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertTrue(app.buttons["撤销"].waitForExistence(timeout: 2))
        app.buttons["撤销"].tap()
        XCTAssertTrue(app.staticTexts["投递实习简历"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testGoalReferenceCardsKeepProgressAccessible() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let artworkBottom = app.buttons["tab.goals"].frame.minY
        XCTAssertNotNil(goalArtworkTopAtMargin(in: app, above: artworkBottom, margin: 0), "插画必须到达左侧屏幕边缘")
        XCTAssertNotNil(goalArtworkTopAtMargin(in: app, above: artworkBottom, margin: app.frame.width - 0.5), "插画必须到达右侧屏幕边缘")
        let names = ["健康一点", "多读书", "坚持运动", "做更好的自己"]
        for name in names { createGoal(named: name, in: app) }
        for (name, icon) in [("健康一点", "leaf"), ("做更好的自己", "heart")] {
            app.staticTexts[name].tap()
            app.buttons["目标设置"].tap()
            let choice = app.buttons["goal.icon.\(icon)"]
            for _ in 0..<3 where !choice.isHittable { app.swipeUp() }
            choice.tap()
            app.buttons["保存设置"].tap()
            app.buttons["返回目标列表"].tap()
        }
        XCTAssertFalse(app.staticTexts["0/0"].exists, "列表卡片不显示参考图中没有的进度数字")
        let row = app.buttons.containing(.staticText, identifier: "多读书").firstMatch
        XCTAssertTrue(row.exists)
        XCTAssertTrue((row.value as? String ?? "").contains("完成 0 个，共 0 个任务"), "精简视觉后仍保留进度的无障碍说明")
        saveScreenshot("goals-reference-four-cards", app: app)
        app.buttons["目标筛选"].tap()
        app.buttons["进行中"].tap()
        XCTAssertTrue(app.staticTexts["多读书"].exists)
    }

    @MainActor
    func testGoalBackgroundStaysInPlaceWhileCreatingGoal() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["新建目标"].waitForExistence(timeout: 3))
        let originalArtworkY = try XCTUnwrap(goalArtworkTopAtMargin(in: app, above: app.buttons["tab.goals"].frame.minY))
        saveScreenshot("goals-background-before-creation", app: app)
        app.buttons["新建目标"].tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        let field = app.textFields["目标名称"]
        XCTAssertTrue(field.isHittable)
        field.typeText("多读书")
        let create = app.buttons["创建"]
        XCTAssertTrue(create.isHittable)
        XCTAssertLessThanOrEqual(create.frame.maxY, keyboard.frame.minY)
        saveScreenshot("goals-background-during-creation", app: app)
        let visibleArtworkY = goalArtworkTopAtMargin(in: app, above: keyboard.frame.minY)
        XCTAssertGreaterThanOrEqual(visibleArtworkY ?? app.frame.height, originalArtworkY - 2,
                                    "输入目标时，背景插画不能从原来的底部位置被推到键盘上方")
        app.buttons["取消"].tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))
        let restoredArtworkY = try XCTUnwrap(goalArtworkTopAtMargin(in: app, above: app.buttons["tab.goals"].frame.minY))
        XCTAssertEqual(restoredArtworkY, originalArtworkY, accuracy: 2)
        app.buttons["新建目标"].tap()
        field.typeText("每天阅读")
        create.tap()
        XCTAssertTrue(app.staticTexts["每天阅读"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testHeaderNewGoalStaysFixedWhileScrollingAndReturnsAfterCancel() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJInitialTab", "goals", "-ZJPreviewSampleData", "-appAppearance", "light",
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
        app.launchArguments += ["-ZJPreviewSampleData", "-appAppearance", "light"]
        app.launch()
        let start = app.buttons["开始计时"].firstMatch
        for _ in 0..<3 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        start.tap()
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
    func testAllPagesStayLightAndAppearanceControlIsRemoved() throws {
        continueAfterFailure = false
        for legacyAppearance in ["dark", "system"] {
            let app = makeApp()
            app.launchArguments += ["-ZJPreviewSampleData", "-appAppearance", legacyAppearance]
            app.launch()
            for tab in ["today", "goals", "calendar", "profile"] {
                app.buttons["tab.\(tab)"].tap()
                XCTAssertTrue(app.buttons["tab.\(tab)"].isSelected)
                assertLightPaper(in: app)
                saveScreenshot("fixed-light-\(legacyAppearance)-\(tab)", app: app)
            }
            openPreferences(in: app)
            XCTAssertTrue(app.buttons["关于粥记"].waitForExistence(timeout: 2))
            XCTAssertFalse(app.buttons["外观"].exists)
            assertLightPaper(in: app)
            app.buttons["profile.closePanel"].tap()
            app.buttons["tab.today"].tap()
            app.buttons["添加任务"].tap()
            XCTAssertTrue(app.textFields["今天要做什么？"].waitForExistence(timeout: 2))
            assertLightPaper(in: app)
            app.terminate()
        }
    }

    @MainActor
    func testReferenceAppearanceWithLargeText() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments += ["-ZJPreviewSampleData", "-appAppearance", "light",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        XCTAssertTrue(app.buttons["添加任务"].waitForExistence(timeout: 3))
        saveScreenshot("today-light-large-text", app: app)
        app.buttons["tab.goals"].tap()
        XCTAssertTrue(app.buttons["目标筛选"].waitForExistence(timeout: 2))
        saveScreenshot("goals-light-large-text", app: app)
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.previousMonth"].waitForExistence(timeout: 2))
        app.buttons["calendar.previousMonth"].tap()
        XCTAssertTrue(app.staticTexts["calendar.empty"].waitForExistence(timeout: 2))
        saveScreenshot("calendar-light-large-text", app: app)
        app.buttons["tab.profile"].tap()
        XCTAssertTrue(app.buttons["profile.overview"].isHittable)
        XCTAssertTrue(app.buttons["profile.settings"].isHittable)
        openOverview(in: app)
        XCTAssertTrue(app.staticTexts["profile.weekFocus"].exists)
        saveScreenshot("profile-overview-light-large-text", app: app)
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
        XCTAssertTrue(app.staticTexts["profile.preferencesHeading"].waitForExistence(timeout: 3))
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
    private func assertTodayArtworkReachesScreenEdges(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        var latestSamples: [(isRight: Bool, inset: Int, inkFraction: Double)] = []
        // A native scroll indicator briefly covers the inner sampled columns after scrolling.
        // Wait for the actual pixels to satisfy the same per-column requirement; clipping still times out.
        let reachesEdges = NSPredicate { _, _ in
            guard let samples = self.todayArtworkEdgeSamples(in: app), !samples.isEmpty else { return false }
            latestSamples = samples
            return samples.allSatisfy { $0.inkFraction > 0.02 }
        }
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: reachesEdges, object: nil)],
            timeout: 3
        )
        XCTAssertEqual(result, .completed, "首页插画应在滚动稳定后到达两侧边缘", file: file, line: line)
        XCTAssertFalse(latestSamples.isEmpty, "Screenshot unavailable", file: file, line: line)
        for sample in latestSamples {
            XCTAssertGreaterThan(sample.inkFraction, 0.02,
                                 "首页插画应到达\(sample.isRight ? "右" : "左")侧屏幕边缘，不能被列表左右留白裁切（第 \(sample.inset) 列）", file: file, line: line)
        }
    }

    @MainActor
    private func goalArtworkTopAtMargin(in app: XCUIApplication, above bottom: CGFloat, margin: CGFloat = 14) -> CGFloat? {
        guard let image = UIImage(data: app.screenshot().pngRepresentation)?.cgImage else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let scale = CGFloat(width) / app.frame.width
        // The 14pt margin is outside cards, inputs and navigation icons.
        // Inspect actual printed pixels rather than an invisible layout frame.
        let x = min(width - 1, max(0, Int(margin * scale)))
        for y in stride(from: Int(100 * scale), to: min(height, Int(bottom * scale)), by: 2) {
            let offset = (y * width + x) * 4
            if pixels[offset] < 190 && pixels[offset + 1] < 190 && pixels[offset + 2] < 180 {
                return CGFloat(y) / scale
            }
        }
        return nil
    }

    @MainActor
    private func todayArtworkEdgeSamples(in app: XCUIApplication) -> [(isRight: Bool, inset: Int, inkFraction: Double)]? {
        guard let image = UIImage(data: app.screenshot().pngRepresentation)?.cgImage else {
            return nil
        }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // The reference's terracotta tabletop reaches both sides of the screen.
        // Inspect visible pixels, so a full-size image clipped by its list row cannot pass.
        // Include the outermost pixel: the asset's transparent rim must not leave a gap.
        let scale = CGFloat(width) / app.frame.width
        var samplesByColumn: [(isRight: Bool, inset: Int, inkFraction: Double)] = []
        for isRight in [false, true] {
            for inset in stride(from: 0, to: Int(5 * scale), by: 2) {
                var inkPixels = 0
                var samples = 0
                for y in stride(from: Int(CGFloat(height) * 0.15), to: Int(CGFloat(height) * 0.7), by: 3) {
                    let x = isRight ? width - inset - 1 : inset
                    let offset = (y * width + x) * 4
                    let red = Int(pixels[offset])
                    let green = Int(pixels[offset + 1])
                    let blue = Int(pixels[offset + 2])
                    if red > 150 && red - green > 18 && green - blue > 12 && blue < 185 {
                        inkPixels += 1
                    }
                    samples += 1
                }
                samplesByColumn.append((isRight, inset, Double(inkPixels) / Double(max(1, samples))))
            }
        }
        return samplesByColumn
    }

    @MainActor
    private func assertPaperBehindBackNavigation(in app: XCUIApplication, button: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        guard let image = UIImage(data: app.screenshot().pngRepresentation)?.cgImage else {
            XCTFail("Screenshot unavailable", file: file, line: line)
            return
        }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let scale = CGFloat(width) / app.frame.width
        let minX = Int((button.frame.maxX + 8) * scale)
        let maxX = Int((app.frame.maxX - 16) * scale)
        let minY = Int((button.frame.minY + 8) * scale)
        let maxY = Int((button.frame.maxY - 8) * scale)
        var darkPixels = 0
        var samples = 0
        for y in stride(from: max(0, minY), to: min(height, maxY), by: 3) {
            for x in stride(from: max(0, minX), to: min(width, maxX), by: 3) {
                let offset = (y * width + x) * 4
                if Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2]) < 450 { darkPixels += 1 }
                samples += 1
            }
        }
        XCTAssertGreaterThan(samples, 0, file: file, line: line)
        XCTAssertLessThan(Double(darkPixels) / Double(max(1, samples)), 0.01,
                          "滚动内容不应穿过固定返回栏的纸色背景", file: file, line: line)
    }

    @MainActor
    private func assertLightPaper(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard let image = UIImage(data: app.screenshot().pngRepresentation)?.cgImage else {
            XCTFail("Screenshot unavailable", file: file, line: line)
            return
        }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // Sample the outer paper margin; use the median to ignore individual paper specks.
        let sampleX = Int(Double(width) * 0.015)
        let sampleY = Int(Double(height) * 0.12)
        var channels = [[Int](), [Int](), [Int]()]
        for y in (sampleY - 3)...(sampleY + 3) {
            for x in (sampleX - 3)...(sampleX + 3) {
                let offset = (y * width + x) * 4
                for channel in 0..<3 { channels[channel].append(Int(pixels[offset + channel])) }
            }
        }
        let red = channels[0].sorted()[24]
        let green = channels[1].sorted()[24]
        let blue = channels[2].sorted()[24]
        XCTAssertGreaterThan(red, 200, "Expected light paper, got RGB \(red), \(green), \(blue)", file: file, line: line)
        XCTAssertGreaterThan(green, 200, file: file, line: line)
        XCTAssertGreaterThan(blue, 180, file: file, line: line)
        XCTAssertGreaterThan(red, green, file: file, line: line)
        XCTAssertGreaterThan(green, blue, file: file, line: line)
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZJInMemoryStore"]
        return app
    }
}
