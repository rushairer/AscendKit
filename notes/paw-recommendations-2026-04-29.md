# Paw Recommendations — 2026-04-29

## 背景
本文件用于汇总对 AscendKit 当前规划文档的补充建议，并显式吸收阿笨在本轮讨论中的反馈。

当前已确认的前提：
- **MVP 必须包含截图能力**，而且这是强需求，不应被削弱或后置
- **MVP 不应人为限制自动化截图能力**；相反，截图应作为核心价值之一重点建设
- **AI 需要参与判断 App 的核心亮点功能，并据此生成截图计划、推荐展示顺序与重点画面**
- **ASC 官方 API 边界不预先定死**，而是在开发过程中通过真实实现与验证逐步摸清
- **可恢复的 release workspace 模型采纳**
- **Release Doctor 需要继续扩展高价值检查项**
- **产品聚焦 SwiftUI 主题 App + Apple 最新技术栈**
- **截图侧考虑两条输入路径并存**：
  1. UI Test 自动生成截图
  2. 用户自己提供截图
- **截图后处理仍由 AscendKit 提供**：圆角、边框、整理、输出组织

---

## 一、重新收敛后的产品建议

### 1. 产品定位建议
AscendKit 不应只是“去掉 fastlane 的另一个自动化工具”，而应明确定位为：

> **一个面向 SwiftUI App 的、可恢复、可审计、以截图与发布资产为核心的 App Store 发布辅助系统。**

这个定位里有几个关键点：
- **SwiftUI-first**：只服务于你真正要服务的 app 类型，不追求覆盖一切历史工程
- **Screenshot-first**：截图进入 MVP，且是核心工作流，而不是附属功能
- **AI-assisted screenshot intelligence**：AI 不只是润色文案，而要参与“该拍什么、先拍什么、亮点怎么表达”的判断
- **Release-asset-first**：核心价值在发布素材与提审准备，而不是替代 Xcode Cloud 做构建上传
- **Recoverable**：一次发布不是一组临时命令，而是一个可恢复的 release workspace
- **Auditable**：每次检查、计划、同步、提交准备都应该留下可读状态

---

### 2. MVP 截图能力应强化，而不是保守收缩
既然截图是强需求，那么 MVP 不该只停留在“跑 UI Test 抓原图”这一层，而应该把**AI 驱动的截图规划能力**放进核心能力定义中。

建议把 MVP 截图能力定义为：

#### 必做能力
- 根据 App 结构、信息架构、关键功能、目标受众，**由 AI 协助判断最值得展示的核心亮点功能**
- 生成 screenshot plan：
  - 该展示哪些页面/状态
  - 顺序如何安排
  - 哪些亮点优先
  - 哪些功能适合做首屏/次屏
- 支持 **UI Test 驱动截图采集**
- 支持 **用户自带 screenshots** 导入
- 对 raw 截图做完整性校验
- 提供后处理：
  - rounded corners
  - device frame composition
  - 输出命名整理
  - manifest / coverage summary
- 支持 AI 对截图结果进行二次审视：
  - 是否体现卖点
  - 是否存在空洞画面
  - 是否顺序不合理
  - 是否缺少某个重要场景

#### 额外建议能力
- AI 给出“推荐展示 narrative”，而不只是离散页面列表
- AI 区分：
  - 核心卖点截图
  - 功能支撑截图
  - 信任/质感截图
- AI 可以根据 App 类型（工具、效率、健康、内容、陪伴等）调整截图策略

这里的重点不是弱化自动化，而是**明确：AscendKit 的截图能力不只是执行层自动化，还包括判断层智能化。**

---

### 3. 重新定义截图系统：执行能力 + 判断能力
为了更准确表达你的原意，截图系统建议分成两层，而不是把它理解成单纯 capture pipeline。

#### Layer A — Screenshot Intelligence
负责“拍什么、为什么拍、怎么排序”。

输入：
- app 工程结构
- SwiftUI 页面结构与导航线索
- 功能模块信息
- 用户提供的产品描述/定位
- doctor / metadata / release context

输出：
- screenshot plan
- hero features list
- recommended screen order
- per-screen purpose
- missing highlight warnings

AI 在这一层的职责是：
- 判断核心亮点
- 发现“技术上可拍但营销上没价值”的页面
- 提醒缺少关键展示场景
- 帮用户从“能截图”走向“会展示”

#### Layer B — Screenshot Execution
负责“怎么把图真正产出来并整理好”。

输入路径：
1. UI Test Capture
2. User-provided Screenshots

输出：
- raw screenshots
- composed screenshots
- manifests
- logs
- completeness/quality report

这样的拆法比单纯说“截图 pipeline”更准确，也更符合产品差异化方向。

---

## 二、关于 ASC 官方 API 边界的建议

你的反馈是对的：**现在不应该过早把 ASC API 能力边界定死**。

更合适的做法不是“先假设能不能做”，而是：

> **在开发中建立 capability discovery 机制，用真实实现和真实 app 验证去收敛边界。**

### 建议落地方式
新增一个持续维护的文档：
- `docs/asc-capability-notes.md`

内容不是静态承诺表，而是动态记录：
- 已验证可用的操作
- 文档支持但实践中有 sharp edges 的操作
- 需要 fallback 的操作
- 版本上下文 / editable version / build linkage 的现实行为
- 提交审核、截图同步、IAP 相关的特殊情况

建议字段：
- domain
- operation
- official docs link
- implementation status
- tested with real app?
- caveats
- fallback
- last verified date

重点不是“先知道全部答案”，而是**把摸索过程沉淀成工程资产**。

---

## 三、release workspace 建议正式采纳
这个方向建议直接上升为核心设计原则。

### 核心观点
一个 release 不应该只是一串 CLI 命令，而应该是一个可恢复、可检查、可复用的工作空间。

建议形态：

```text
.ascendkit/
  releases/
    2026-04-myapp-1.2.0/
      manifest.json
      doctor-report.json
      screenshot-plan.json
      screenshot-insights.json
      screenshots/
        raw/
        composed/
        manifests/
      metadata/
      asc/
        observed-state.json
        diff.json
      readiness.json
      audit/
```

### 这个模型能解决的真实问题
- 发布工作跨天进行
- build processing 不是即时完成
- metadata / screenshots / review notes 分阶段补齐
- 本地期望状态与 ASC 实际状态可能多次变化
- 某次同步失败后需要恢复现场
- AI 生成过的 screenshot reasoning / highlight 判断需要保留，便于继续迭代

### 建议新增文档
- `docs/release-workspace-model.md`

建议定义清楚：
- release id 如何生成
- workspace 生命周期
- observed state / desired state / diff / apply history
- 哪些文件是 runtime state，哪些是用户可编辑输入
- AI 生成的 screenshot reasoning 存放在哪里
- 如何做 archive / cleanup

---

## 四、Release Doctor 继续补强建议
现有 doctor 方向已经不错，但如果要更贴近真实上架痛点，还建议继续增加下面几类高价值检查。

### A. 审核语义风险检查
这类不是“编译错误式 blocker”，但非常容易导致审核来回。

建议加入：
- app 是否存在登录门槛，但 reviewer instructions 不完整
- app 是否存在 paywall，但 reviewer notes 未说明体验路径
- app 是否依赖特定硬件 / 区域 / 资格 / 邀请码
- 首屏是否可能表现为空壳或无内容
- AI 功能是否缺少对 reviewer 足够明确的说明
- 订阅类 app 是否缺 restore / terms / privacy 可见性提醒

这些可先作为：
- risk hint
- guided checklist
- human-confirmed readiness item

而不是硬判定。

---

### B. 元数据质量检查
不只检查“有没有”和“超没超长”，还应检查“像不像可上线的文案”。

建议加入：
- subtitle / keywords 低信息量重复
- 跨语言文案明显只是机械直译
- 竞品词 / 品牌词误用风险
- release notes 质量过低
- 多语言 name/subtitle 定位不一致
- TODO / test / internal wording / staging 文案残留

这块很适合做成：
- rule-based lint
- AI-assisted explanation
- user acceptance required

---

### C. 版本上下文一致性检查
这是发布自动化里非常容易“看似成功、实际错位”的部分。

建议明确专项检查：
- 本地目标 version 与 ASC editable version 是否一致
- build 是否对应当前目标 release
- metadata 是否准备同步到错误版本上下文
- screenshots 是否准备覆盖错误版本资产
- release notes / version / build policy 是否互相不一致

建议把这块单独做成 doctor family，而不是散落在多个检查项里。

---

### D. SwiftUI / 最新 Apple 技术专项检查
既然已经聚焦 SwiftUI-first，那 doctor 可以更积极地利用这个边界。

建议新增：
- SwiftUI app 生命周期与 target 配置合理性检查
- scene / window group 基础结构检查（面向截图与启动稳定性）
- 预览/调试专用内容是否误混入 release 行为
- 深色模式 / 动态字体 / 本地化截断的截图风险提示
- 常见 SwiftUI 导航状态是否适合 UI Test 稳定驱动
- fixture / seed data / launch argument 约定是否完整

这会让 AscendKit 对 SwiftUI app 的价值明显强于泛化工具。

---

### E. 截图专项 Doctor
既然截图是 MVP 核心，建议 doctor 里单独有一组 screenshot readiness checks。

建议加入：
- 是否存在可用 UI Test target
- 是否存在 screenshot-specific launch mode
- 是否存在稳定 fixture/data seed 机制
- locale/device matrix 是否可落地
- screen coverage plan 是否完整
- raw screenshot 目录结构是否合法（针对用户自带路径）
- 是否存在明显 debug overlay / test banner / staging residue
- SwiftUI 页面是否存在异步加载导致截图不稳定的高风险点
- 当前 screen set 是否真的覆盖核心亮点，而不是仅覆盖导航层级

最后这一条尤其重要：
**AscendKit 不该只验证“有没有图”，还要帮助判断“图拍得对不对”。**

---

## 五、建议的 MVP 结构（结合当前反馈后）

### MVP 核心模块建议
1. **Config**
2. **Secrets**
3. **Audit**
4. **Intake**
5. **Doctor**
6. **Screenshot Intelligence**
7. **Screenshot Plan**
8. **Screenshot Capture (UI Test)**
9. **Screenshot Import (BYO)**
10. **Screenshot Compose**
11. **Metadata local storage + lint**
12. **ASC auth + basic lookup**
13. **Submission readiness**

这里的重点调整是：
- **把 Screenshot Intelligence 明确拉成 MVP 的正式模块**
- 不把截图理解成单纯底层自动化
- 允许 AI 在截图规划阶段真正发挥作用

### 建议暂缓为后续阶段
- review submission 真正远程执行
- IAP 远程创建/修改
- 复杂 pricing / offers 管理
- 过早的 agent adapter / MCP 深集成

这里“暂缓”的含义只是阶段排序，不是否定价值。

---

## 六、建议的命令树方向（第一阶段）

```text
ascendkit intake inspect
ascendkit doctor release
ascendkit doctor screenshots
ascendkit screenshots analyze-highlights
ascendkit screenshots plan
ascendkit screenshots capture
ascendkit screenshots import
ascendkit screenshots compose
ascendkit screenshots review
ascendkit metadata init
ascendkit metadata lint
ascendkit asc apps list
ascendkit asc builds list
ascendkit submit readiness
```

### 说明
- `screenshots analyze-highlights`：分析 app 的核心卖点与推荐展示重点
- `screenshots plan`：生成 screen plan、顺序和 coverage 建议
- `screenshots review`：对已生成截图做 AI 复审，判断是否足够体现卖点

### 补充建议
- 所有关键命令支持 `--json`
- 截图相关命令支持输出 manifest / reasoning / quality summary
- mutating 操作继续保留 dry-run / confirm 思路
- screenshot capture 失败时要有机器可读 failure 分类

---

## 七、我当前最推荐的文档补充
建议优先新增：

1. `docs/release-workspace-model.md`
2. `docs/asc-capability-notes.md`
3. `docs/screenshot-readiness-rules.md`
4. `docs/screenshot-intelligence.md`
5. `docs/mvp-roadmap.md`

### 每个文档的作用

#### `release-workspace-model.md`
定义发布工作空间与状态模型。

#### `asc-capability-notes.md`
记录 ASC API 真实摸索结果，而不是预设死边界。

#### `screenshot-readiness-rules.md`
把 UI Test 截图前提、用户自带截图规则、compose 输出要求写清楚。

#### `screenshot-intelligence.md`
定义 AI 如何判断核心亮点、如何形成 screenshot plan、如何复审截图价值。

#### `mvp-roadmap.md`
把“必须做”和“先不做”写清楚，避免 scope 膨胀。

---

## 八、一句总判断
AscendKit 当前最值得坚持的，不是“彻底反 fastlane”，而是：

> **把 SwiftUI App 的 App Store 截图与发布准备，做成一套可恢复、可检查、可智能判断、可自动执行、可持续验证的工程系统。**

阿笨这轮反馈之后，方向其实更清楚了：
- 不退截图
- 不压缩自动化截图 ambition
- AI 要参与亮点判断与截图规划
- 不预设 API 边界
- 聚焦 SwiftUI
- 强化 Doctor
- 接受 release workspace

这条线比我上一版写得更准确，也更符合你的原意。