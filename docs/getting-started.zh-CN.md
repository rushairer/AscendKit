# AscendKit 中文入门

用命令行或 AI Agent 准备 App Store 截图、元数据和审核提交。

AscendKit 是本地优先的 Swift CLI：它将发布进度保存到本地工作区，支持 JSON 输出，并在远程修改前要求显式确认参数。你可以只采用截图或元数据流程，也可以让 AI Agent 接手完整的发布准备工作。

[English README](../README.md) · [完整命令参考](../README.md#command-reference) · [Agent 操作手册](agent-release-playbook.md)

## 可以做什么

- 导入截图，或通过确定性的 UI 测试采集截图，制作带设备边框、主题和多语言文案的商店海报。
- 创建、导入、检查元数据，比较本地内容与 App Store Connect 状态后再应用修改。
- 检查项目的发布问题，输出下一步可执行命令。
- 选择已上传的构建，检查提交条件，执行带确认步骤的 App Review 提交。

核心流程不依赖 fastlane，也支持导入已有 fastlane 元数据和截图。归档、签名和二进制上传继续使用你的现有工具，例如 Xcode Cloud。App Privacy 的部分操作仍可能需要在 App Store Connect 网页完成。

## 安装

需要 macOS 14 或更新版本。项目检查需要 Xcode 命令行工具；模拟器和 UI 测试截图需要相应的 Xcode 环境。只有远程 ASC 操作需要 App Store Connect API 密钥。

```bash
brew tap rushairer/ascendkit
brew install ascendkit
ascendkit --version
ascendkit --help
```

## 先做一次本地检查

在你的 **App 项目根目录**打开终端：

```bash
APP_ROOT="$PWD"
RELEASE_ID="local-check"
WORKSPACE="$APP_ROOT/.ascendkit/releases/$RELEASE_ID"

ascendkit intake inspect --root "$APP_ROOT" --release-id "$RELEASE_ID" --save --json
ascendkit workspace gitignore --workspace "$WORKSPACE" --fix --json
ascendkit doctor release --workspace "$WORKSPACE" --json
ascendkit workspace next-steps --workspace "$WORKSPACE" --json
```

这些命令会创建 `.ascendkit/releases/local-check` 本地工作区，并更新项目的 Git 忽略规则，不需要 ASC 密钥，也不会修改远程状态。检查结果可能包含待解决的问题；请根据输出继续处理。正式发布时，为对应版本选择独立的 release ID。

## 把首页交给 AI Agent

可以直接发送以下请求，并附上已知的项目路径、release ID 和 ASC profile 名称。不要发送私钥内容。

```text
请使用 AscendKit 帮我准备当前 Apple App 的 App Store 发布：
https://github.com/rushairer/AscendKit

先阅读 README 的 AI Agent Quick Start（包括完整提示词），
再按照它链接的 agent-release-playbook.md 执行。
使用已安装的 ascendkit CLI，通过 workspace next-steps 等 JSON 输出推进。
缺少真实项目参数时先询问，不要把占位符当作实际值执行。
远程修改前先检查计划，仅在任务授权范围内使用明确的确认参数。
不要将密钥或发布工作区提交到仓库；二进制上传交给现有流程。
最后汇报完成情况、阻塞项和仍需人工处理的步骤。
```

英文首页保留完整的 Agent 提示词、命令示例和恢复流程。网页上的折叠区只用于方便阅读，内容仍完整保存在原始 Markdown 中。准确命令和操作约束以英文 README、CLI 帮助和操作手册为准。

## 下一步

- [完整发布流程](../README.md#quick-start-submit-an-app-store-release)
- [截图命令](../README.md#screenshots)
- [添加项目级 Agent 指令](claude-md-snippet-for-app-projects.md)
- [安全模型](security-model.md)与[自动化边界](automation-boundaries.md)
