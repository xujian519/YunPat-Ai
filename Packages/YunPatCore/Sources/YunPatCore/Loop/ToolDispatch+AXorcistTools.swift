import Foundation

// MARK: - AXorcist Desktop Automation Tools 注册 & 处理

extension ToolDispatch {

    func registerAXorcistTools() {
        handlers["ax_click"] = { name, input, context in
            await Self.handleAXClick(name: name, input: input, ctx: context)
        }
        toolSpecs["ax_click"] = ToolSpec(
            name: "ax_click",
            description: "点击指定应用中的 UI 元素（通过 Accessibility API）。需要 app 和 element 参数。"
        )
        handlers["ax_type"] = { name, input, context in
            await Self.handleAXType(name: name, input: input, ctx: context)
        }
        toolSpecs["ax_type"] = ToolSpec(
            name: "ax_type",
            description: "在指定应用的 UI 元素中输入文本。需要 app、text 和 target 参数。"
        )
        handlers["ax_read"] = { name, input, context in
            await Self.handleAXRead(name: name, input: input, ctx: context)
        }
        toolSpecs["ax_read"] = ToolSpec(
            name: "ax_read",
            description: "读取指定应用中 UI 元素的值/文本。需要 app 和 element 参数。"
        )
        handlers["ax_screenshot"] = { name, input, context in
            await Self.handleAXScreenshot(name: name, input: input, ctx: context)
        }
        toolSpecs["ax_screenshot"] = ToolSpec(
            name: "ax_screenshot",
            description: "截取指定应用窗口或整个屏幕的截图。可选 app 参数指定应用。"
        )
        handlers["ax_list_windows"] = { name, input, context in
            await Self.handleAXListWindows(name: name, input: input, ctx: context)
        }
        toolSpecs["ax_list_windows"] = ToolSpec(
            name: "ax_list_windows",
            description: "列出当前所有可见的窗口及其所属应用。"
        )
        handlers["ax_get_properties"] = { name, input, context in
            await Self.handleAXGetProperties(name: name, input: input, ctx: context)
        }
        toolSpecs["ax_get_properties"] = ToolSpec(
            name: "ax_get_properties",
            description: "获取指定 UI 元素的所有 Accessibility 属性。需要 app 和 element 参数。"
        )
        handlers["ax_find_element"] = { name, input, context in
            await Self.handleAXFindElement(name: name, input: input, ctx: context)
        }
        toolSpecs["ax_find_element"] = ToolSpec(
            name: "ax_find_element",
            description: "在指定应用中搜索是否存在匹配的 UI 元素。需要 app 和 query 参数。"
        )
    }

    // MARK: - Handlers

    private static func handleAXClick(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        guard let provider = AXorcistToolRegistry.provider else {
            return .handled(ToolResponse.errResp(
                code: .permissionDenied,
                message: "桌面自动化未启用",
                hint: "请在系统设置中授予辅助功能权限"
            ).jsonString())
        }
        let app: String = input["app"]?.stringValue ?? ""
        let element: String = input["element"]?.stringValue ?? ""
        guard !app.isEmpty, !element.isEmpty else {
            return .handled(ToolResponse.errResp(
                code: .invalidArgs, message: "app 和 element 参数必填"
            ).jsonString())
        }
        do {
            try await provider.click(app: app, element: element)
            return .handled(ToolResponse.okResp(data: .object([
                "action": .string("click"),
                "app": .string(app),
                "element": .string(element),
                "success": .bool(true)
            ])).jsonString())
        } catch {
            return .handled(ToolResponse.errResp(
                code: .executionError, message: error.localizedDescription
            ).jsonString())
        }
    }

    private static func handleAXType(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        guard let provider = AXorcistToolRegistry.provider else {
            return .handled(ToolResponse.errResp(
                code: .permissionDenied, message: "桌面自动化未启用"
            ).jsonString())
        }
        let app: String = input["app"]?.stringValue ?? ""
        let text: String = input["text"]?.stringValue ?? ""
        let target: String = input["target"]?.stringValue ?? ""
        guard !app.isEmpty, !text.isEmpty, !target.isEmpty else {
            return .handled(ToolResponse.errResp(
                code: .invalidArgs, message: "app、text 和 target 参数必填"
            ).jsonString())
        }
        do {
            try await provider.type(app: app, text: text, target: target)
            return .handled(ToolResponse.okResp(data: .object([
                "action": .string("type"),
                "app": .string(app),
                "target": .string(target),
                "length": .number(Double(text.count)),
                "success": .bool(true)
            ])).jsonString())
        } catch {
            return .handled(ToolResponse.errResp(
                code: .executionError, message: error.localizedDescription
            ).jsonString())
        }
    }

    private static func handleAXRead(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        guard let provider = AXorcistToolRegistry.provider else {
            return .handled(ToolResponse.errResp(
                code: .permissionDenied, message: "桌面自动化未启用"
            ).jsonString())
        }
        let app: String = input["app"]?.stringValue ?? ""
        let element: String = input["element"]?.stringValue ?? ""
        guard !app.isEmpty, !element.isEmpty else {
            return .handled(ToolResponse.errResp(
                code: .invalidArgs, message: "app 和 element 参数必填"
            ).jsonString())
        }
        do {
            let value: String = try await provider.read(app: app, element: element)
            return .handled(ToolResponse.okResp(data: .object([
                "app": .string(app),
                "element": .string(element),
                "value": .string(value)
            ])).jsonString())
        } catch {
            return .handled(ToolResponse.errResp(
                code: .executionError, message: error.localizedDescription
            ).jsonString())
        }
    }

    private static func handleAXScreenshot(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        guard let provider = AXorcistToolRegistry.provider else {
            return .handled(ToolResponse.errResp(
                code: .permissionDenied, message: "桌面自动化未启用"
            ).jsonString())
        }
        let app: String? = input["app"]?.stringValue
        do {
            let data: Data = try await provider.screenshot(app: app, region: nil)
            return .handled(ToolResponse.okResp(data: .object([
                "action": .string("screenshot"),
                "app": .string(app ?? "fullscreen"),
                "size_bytes": .number(Double(data.count)),
                "format": .string("png")
            ])).jsonString())
        } catch {
            return .handled(ToolResponse.errResp(
                code: .executionError, message: error.localizedDescription
            ).jsonString())
        }
    }

    private static func handleAXListWindows(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        guard let provider = AXorcistToolRegistry.provider else {
            return .handled(ToolResponse.errResp(
                code: .permissionDenied, message: "桌面自动化未启用"
            ).jsonString())
        }
        do {
            let windows: [WindowInfo] = try await provider.listWindows()
            let lines: [String] = windows.map { win in
                "\(win.appName) — \(win.windowTitle) [pid:\(win.pid)]"
            }
            return .handled(ToolResponse.okResp(data: .object([
                "count": .number(Double(windows.count)),
                "windows": .string(lines.joined(separator: "\n"))
            ])).jsonString())
        } catch {
            return .handled(ToolResponse.errResp(
                code: .executionError, message: error.localizedDescription
            ).jsonString())
        }
    }

    private static func handleAXGetProperties(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        guard let provider = AXorcistToolRegistry.provider else {
            return .handled(ToolResponse.errResp(
                code: .permissionDenied, message: "桌面自动化未启用"
            ).jsonString())
        }
        let app: String = input["app"]?.stringValue ?? ""
        let element: String = input["element"]?.stringValue ?? ""
        guard !app.isEmpty, !element.isEmpty else {
            return .handled(ToolResponse.errResp(
                code: .invalidArgs, message: "app 和 element 参数必填"
            ).jsonString())
        }
        do {
            let props: [String: String] = try await provider.getProperties(app: app, element: element)
            var jsonProps: [String: JSONValue] = [:]
            for (propKey, propVal) in props { jsonProps[propKey] = .string(propVal) }
            return .handled(ToolResponse.okResp(data: .object(jsonProps)).jsonString())
        } catch {
            return .handled(ToolResponse.errResp(
                code: .executionError, message: error.localizedDescription
            ).jsonString())
        }
    }

    private static func handleAXFindElement(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        guard let provider = AXorcistToolRegistry.provider else {
            return .handled(ToolResponse.errResp(
                code: .permissionDenied, message: "桌面自动化未启用"
            ).jsonString())
        }
        let app: String = input["app"]?.stringValue ?? ""
        let query: String = input["query"]?.stringValue ?? ""
        guard !app.isEmpty, !query.isEmpty else {
            return .handled(ToolResponse.errResp(
                code: .invalidArgs, message: "app 和 query 参数必填"
            ).jsonString())
        }
        do {
            let found: Bool = try await provider.findElement(app: app, query: query)
            return .handled(ToolResponse.okResp(data: .object([
                "app": .string(app),
                "query": .string(query),
                "found": .bool(found)
            ])).jsonString())
        } catch {
            return .handled(ToolResponse.errResp(
                code: .executionError, message: error.localizedDescription
            ).jsonString())
        }
    }
}
