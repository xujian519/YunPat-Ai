# ──────────────────────────────────────────────────────
# YunPat-Ai — Build / Test / Lint / Format 标准 Lane
# ──────────────────────────────────────────────────────

# 包路径（按构建顺序排列）
PACKAGES := \
	Packages/PatentClient \
	Packages/YunPatNetworking \
	Packages/YunPatCore \
	Packages/YunPatPlugins \
	Packages/YunPatDesktop \
	Packages/YunPatSandbox

# 工具检测
SWIFT        := $(shell which swift 2>/dev/null || echo "swift")
SWIFTLINT    := $(shell which swiftlint 2>/dev/null || echo "swiftlint")
SWIFT_FORMAT := $(shell xcrun --find swift-format 2>/dev/null || echo "")

.PHONY: all build test lint format cli clean

all: build lint

# ── 全量构建 ──────────────────────────────────────────
build:
	@echo "═══ 全量构建 ═══"
	@swift build
	@for pkg in $(PACKAGES); do \
		if [ -f "$$pkg/Package.swift" ]; then \
			echo "─── building $$pkg ───"; \
			swift build --package-path $$pkg; \
		fi \
	done
	@echo "✅ 全量构建完成"

# ── 逐包测试 ──────────────────────────────────────────
test:
	@echo "═══ 逐包运行测试 ═══"
	@total=0; passed=0; \
	for pkg in $(PACKAGES); do \
		if [ -f "$$pkg/Package.swift" ] && [ -d "$$pkg/Tests" ]; then \
			name=$$(basename $$pkg); \
			echo "─── testing $$name ───"; \
			if swift test --package-path $$pkg 2>&1; then \
				echo "✅ $$name"; \
				passed=$$((passed + 1)); \
			else \
				echo "❌ $$name"; \
			fi; \
			total=$$((total + 1)); \
		fi \
	done; \
	echo "═══ 测试结果: $$passed/$$total 包通过 ═══"

# ── SwiftLint ─────────────────────────────────────────
lint:
	@echo "═══ SwiftLint ═══"
	@if [ -x "$(SWIFTLINT)" ]; then \
		$(SWIFTLINT) --strict; \
	else \
		echo "⚠️  swiftlint 未安装，跳过。安装: brew install swiftlint"; \
	fi

# ── swift-format ─────────────────────────────────────
format:
	@echo "═══ swift-format ═══"
	@if [ -n "$(SWIFT_FORMAT)" ] && [ -x "$(SWIFT_FORMAT)" ]; then \
		find App Packages -name "*.swift" \
			-not -path "*/.build/*" \
			-not -path "*/checkouts/*" \
			-print0 | \
		xargs -0 $(SWIFT_FORMAT) --in-place --configuration .swift-format; \
		echo "✅ 格式化完成"; \
	else \
		echo "⚠️  swift-format 未安装（Xcode 工具链需包含 swift-format），跳过。"; \
	fi

# ── CLI（项目无独立 CLI 目标，等价于 build）─────────────
cli:
	@echo "═══ 构建 CLI (↪ build) ═══"
	swift build

# ── 清理 ──────────────────────────────────────────────
clean:
	@echo "═══ 清理构建产物 ═══"
	swift package clean
	for pkg in $(PACKAGES); do \
		if [ -f "$$pkg/Package.swift" ]; then \
			swift package --package-path $$pkg clean; \
		fi \
	done
	rm -rf .build
	@echo "✅ 清理完成"
