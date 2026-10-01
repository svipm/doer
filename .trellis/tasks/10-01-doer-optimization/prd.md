# Doer 优化路线：可维护性与稳定性提升

## Goal

在功能面已经铺开（浏览 / 帖子 / 回复 / AI / Notion / 插件 / 签到 / 小程序 / Cloudflare 验证 / Live Activity / DoH）之后，
把重心从「加功能」转向「降债务、收敛实现、补测试、补体验缺口」。

最近 25 个提交中绝大多数是 `fix:`（审计轮修 bug、编译错误、测试转绿），说明扩张速度已经超过稳定性。
本任务是一个**父任务**，只负责需求集合、子任务地图、跨子任务验收标准和最终集成 review，本身不直接实现。

## Confirmed Facts（已通过代码/文档核实）

- 427 个 Swift 文件，151909 行；`DoerTests` 68 个测试文件，集中在策略 / 解析 / store 等纯逻辑。
- 巨型文件（行数）：
  - `TopicDetailViewModel.swift` 2363 —— 其中 1–573 行是 6 个游离顶层类型
    （`TopicDetailHTMLParsing`、`TopicDetailPollResultMerger`、`TopicDetailPaginationPolicy`、
    `TopicDetailJumpScrollPolicy`、`TopicDetailFirstPaintPolicy`、`TopicDetailSnapshotPolicy`），
    ViewModel 类从 574 行开始。
  - `ChatTopicDetailViewController.swift` 2047
  - `ReplyComposerViewController.swift` 1649
  - `WeChatChatPostCell.swift` 1610
  - `AppearanceSettingsViewController.swift` 1598
  - `TopicDetailViewController.swift` 1564
  - `LocalConnectProxy.swift` 1548、`InAppBrowserViewController.swift` 1544、
    `PostWebViewCell.swift` 1496、`PostNativeCell.swift` 1471、
    `ComposerSharedCore.swift` 1388、`ForumContainerViewController.swift` 1363
- `TopicDetailCoordinator.swift`（585 行）**已存在**，`TopicDetailViewController+Actions/BottomBar/PostCellDelegate/TableView/Toc.swift` 也已存在
  → `.trellis/spec/frontend/topic-detail-refactor.md` 描述的重构**已部分完成，且文档内容已过期**（文档写 VC 1668 行，实际 1564）。
- 双轨实现：
  - 渲染：`PostWebViewCell`（WKWebView 快照）与 `PostNativeCell` + `NativeContent/*`（原生块渲染）。
  - 编辑器：`ComposerSharedCore`（1388）与 `ExperimentalComposer/`（`ExperimentalComposerView` 1332 + `ExperimentalComposerDocument` 826）。
- 无任何 `TODO/FIXME/HACK/XXX` 标记；债务靠 `ponytail:` 注释与 spec 记录。
- `.trellis/spec/frontend/quality-guidelines.md` 仍是空模板（Forbidden/Required/Testing/Review 全部 To be filled）。
- `ponytail:` 已知欠账：
  - `AIChatService.swift:84` —— AI 流式协议先整段返回。
  - `AIChatSheetViewController.swift:526` —— 「全部楼层」补拉上限 100 楼。
  - `TrustRequirementsViewController.swift:287` —— summary 不暴露 flag/封禁计数。
  - `TrustRequirementsViewController.swift:470` —— connect 页 HTML 解析跑在主 actor。
  - `PostNativeCell.swift:1272` —— site-setting 门控未实现。
  - `NewAPICheckInManualSignInViewController.swift:13` —— 无跨平台共享 Cookie 仓库。
- CI：`.github/workflows/Tests.yml` + `Build Unsigned IPA.yml`；无签名分发 / TestFlight 自动化。
- 项目来源：UIKit 架构源自 `Eilgnaw/dexo`，交互参考 `Lingyan000/fluxdo`（见 README 致谢与 `fluxdo-porting.md`）。

## Task Map（子任务）

| # | 子任务 | 交付物 | 依赖 |
|---|--------|--------|------|
| 1 | `10-01-topicdetail-split` | TopicDetail 标准路径拆分（游离类型出栈 + VC/VM 职责分离） | 无 |
| 2 | `10-01-dual-path-convergence` | 渲染与编辑器双轨收敛为单主路径 | 无（结论会影响 #1 的 Cell 部分是否值得投入） |
| 3 | `10-01-quality-and-tests` | 质量规约落地 + 巨型模块测试补齐 | 建议在 #1 之后（用拆出来的类型做测试锚点） |
| 4 | `10-01-experience-gaps` | AI 流式 / 离线缓存 / 推送核对 / 主线程解析 | 建议在 #1、#3 之后 |
| 5 | `10-01-release-pipeline` | 签名分发与 TestFlight 自动化 | 独立，可并行 |

依赖关系写在子任务各自的 `prd.md` / `implement.md` 里，不用树位置隐含。

## Requirements（父任务层面）

- R1：每个子任务必须可独立规划、实现、检查、归档，并有可测试的验收标准。
- R2：所有拆分必须是**行为不变**的重构，除非子任务 PRD 显式声明行为变更。
- R3：每完成一个子任务，必须补充或更新对应测试，不能只拆不测。
- R4：任何新增功能前，先落质量规约（子任务 3），并遵守「超阈值文件禁止加功能」的硬约束。
- R5：重构不得降低现有能力（iOS 15 兼容、多主题、多论坛、CF 验证、Live Activity 等）。

## Acceptance Criteria（跨子任务）

- [ ] 5 个子任务全部完成或明确取消，且各自验收标准通过。
- [ ] 代码库中不再存在 >1500 行的文件，或每个例外都在质量规约中有书面豁免理由。
- [ ] 双轨实现收敛为单一主路径，另一路径要么删除、要么降级为有文档说明的兜底。
- [ ] `.trellis/spec/frontend/quality-guidelines.md` 不再是空模板。
- [ ] `DoerTests` 覆盖被拆分的核心类型；新增测试随对应子任务落地。
- [ ] 全程 `DoerTests` scheme 与 `Packages/CookedHTML` 测试保持绿色。
- [ ] 每个子任务完成后按 Trellis Phase 3 流程更新 spec 并提交。

## Final Integration Review（父任务收口）

- 核对 5 个子任务的产出是否互相矛盾（尤其 #1 的 Cell 拆分 vs #2 的路径收敛）。
- 全量跑 `DoerTests` + `CookedHTML` 测试。
- 复查质量规约中的阈值与豁免清单是否与实际一致。
- 汇总为一份优化总结写入 `.trellis/spec/frontend/` 或 `docs/`。

## Out of Scope

- 新增论坛平台 / 新协议支持。
- 商业化、上架 App Store 的合规改造。
- 与优化无关的功能开发（如新插件、新主题）。
- 修改 `Packages/CookedHTML` 的解析语义（除非子任务显式声明）。

## Open Questions

- 子任务 2 的收敛力度：删除一条路径 vs 保留为兜底（风险容忍度决策，待确认）。
- 子任务 1 的边界：是否包含 `ChatTopicDetailViewController` 与 Composer（待确认）。

## Notes

- 本父任务不进入 `in_progress`；由子任务各自 `task.py start`。
- 每个子任务开工前必须有其自己的 `prd.md`，复杂子任务还需要 `design.md` + `implement.md`。
