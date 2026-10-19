# 协作规则（写给开发机器人）

本仓库主要由编码机器人（例如 DeepSeek）开发，由 PR 审核机器人审核合并。请严格遵守：

## 分支与 PR
1. **不要直接推送 `main`。** 每个任务开一个分支：`feat/<简述>`、`fix/<简述>`、`docs/<简述>`、`eval/<简述>`。
2. 每个 PR 只做一件事，尽量小（建议 < 600 行改动，不含生成文件）。
3. 开 PR 时在描述里写清：
   - 对应 `docs/PLAN.md` 的哪个里程碑、哪几条验收标准；
   - 做了什么、怎么验证的（单元测试 / 真机测量 / 评测分数）；
   - 新增依赖或模型的 **许可证和来源**；
   - 已知限制。
4. **CI 必须是绿的**（`.github/workflows/ios.yml`：XcodeGen 生成工程 + iOS 模拟器构建 + 单元测试）。
5. **合并由 PR 审核机器人负责**（squash merge）。开发机器人不要自己合并，也不要改分支保护或 CI 来让检查通过。审核打回后，在同一个分支上继续提交修复。
6. 产品方向上的问题（需要用户拍板的）写在 PR 描述的「待决问题」里，不要自行假设。

## 硬规则（摘自 PLAN.md，违反即打回）
- 不上云：不上传图片，不调用远程服务，不在运行时下载模型或语言包。
- 不含夸克或其他商业 App 的代码、模型、素材；不用它们的输出训练。
- 只用 MIT / Apache-2.0 / BSD 许可的模型、代码、数据集。DocTr / DocTr++ / DocGeoNet / DocScanner 只能离线对照，永不进仓库的发布产物。
- 不提交任何真实照片或用户数据。测试集放在仓库外。
- 保真模式只做几何。

## 工程约定
- 工程以 `project.yml` 为准，`*.xcodeproj` 不入库：`brew install xcodegen && xcodegen generate`。
- Swift 5 语言模式、SwiftUI、最低 iOS 17。
- 图像处理优先用系统框架：Vision、Core Image、Metal、PDFKit、AVFoundation。
- 纯算法逻辑放在 `LocalScan/Core/`，必须有单元测试；耗时关键路径加 `os_signpost`。
- **模型权重不直接进 git**（`.gitignore` 已拦截 `.mlmodel` / `.mlpackage` / `.onnx` / `.pt`）。用脚本从原始发布地址下载，校验 SHA-256，并在 `docs/MODELS.md` 记录：名称、版本、许可证、来源 URL、大小、哈希、转换命令。若确需随包提交，先在 PR 里说明并经审核同意（可用 Git LFS）。
- 评测脚本放 `eval/`，只提交脚本和汇总分数，不提交图片。

## 参考资料
- `docs/research/report.md`：竞品与 iOS 技术调研。
- `docs/research/reverse-engineering-summary.md`：夸克离线流水线的设计层面结论。
- `prototypes/kimi-web/`：网页原型，只作 UX 参考和经典基线，不复用代码。
