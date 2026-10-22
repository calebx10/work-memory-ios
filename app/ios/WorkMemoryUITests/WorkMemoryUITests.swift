import XCTest

final class WorkMemoryUITests: XCTestCase {
    @MainActor
    func testPhoneMemoryWorkflowWithSyntheticService() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-tests"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["录音库"].waitForExistence(timeout: 30))
        app.tabBars.buttons["录音库"].tap()
        let row = app.buttons["recording-11111111-1111-4111-8111-111111111111"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let memory = app.buttons["openMemory"]
        for _ in 0..<8 where !memory.isHittable { app.swipeUp() }
        XCTAssertTrue(memory.isHittable); memory.tap()
        app.buttons["发送并分析"].tap()
        let confirm = app.buttons["confirmAI"]
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["分析完成"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["先小规模验证需求，再决定是否扩大投入。"].exists)
        app.segmentedControls.buttons["原文"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "客户提出先用两周验证需求")).firstMatch.exists)
        app.buttons["回听原始分段"].tap()
        XCTAssertTrue(app.navigationBars["原文依据"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.segmentedControls.buttons["选题"].tap()
        XCTAssertTrue(app.staticTexts["为什么我建议先做小范围试用"].exists)
        let draft = app.buttons["生成口播初稿"]
        for _ in 0..<6 where !draft.isHittable { app.swipeUp() }
        draft.tap()
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp() }
        confirm.tap()
        XCTAssertTrue(app.staticTexts["口播初稿"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["素材"].tap()
        XCTAssertTrue(app.staticTexts["为什么我建议先做小范围试用"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "素材库-已保存选题"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor
    func testNewRecordingAndSettingsNavigation() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-ui-tests"]; app.launch()
        let start = app.buttons["新建场景并开始录音"]
        XCTAssertTrue(start.waitForExistence(timeout: 20)); start.tap()
        XCTAssertTrue(app.navigationBars["新建录音场景"].exists)
        app.buttons["取消"].tap()
        app.tabBars.buttons["设置"].tap()
        app.buttons["openAISettings"].tap()
        XCTAssertTrue(app.navigationBars["AI 服务"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["serviceKey"].exists)
        app.buttons["useAPIMart"].tap()
        XCTAssertTrue(app.staticTexts["api.apimart.ai"].exists)
        app.buttons["useDeepSeekCombo"].tap()
        XCTAssertTrue(app.secureTextFields["analysisKey"].exists)
        XCTAssertTrue(app.staticTexts["api.deepseek.com"].exists)
    }
}
