# LocalScan

本地优先的 iPhone 文档扫描：扫描成图片 / PDF，AI 矫正全部在手机上完成。

## 目标
对标夸克扫描王的「扫描 + AI 矫正」体验，做一个 **又准又快、完全不上云** 的 iPhone 扫描 App：
- 拍照 → 实时找边 → 对准后自动拍 → 透视拉正 / 弯曲书页展平 → 增强 → 导出图片或多页 PDF。
- 「准」= 边找得准、书页拉得平，并且 **不改字**。
- 「快」= 打开即相机，单页从按快门到出成品 ≤ 1 秒（平纸，目标值），连拍不阻塞。

## 原则
1. **不上云。** 所有图像处理、OCR 都在手机本地完成；不调用任何服务器。见 [ADR-0001](docs/ADR-0001-on-device-first.md)。
2. **保真优先。** 「原图 / 保真」模式只做几何，不动像素里的字；默认不开 AI 增强。
3. **能用系统能力就用系统能力。** Vision 找边、Core Image 拉正、PDFKit 导出、Vision OCR，零包体。
4. **模型小。** 随包模型合计 ≤ 25 MB；平纸不跑展平模型。
5. **许可干净。** 只用 MIT / Apache-2.0 / BSD 许可的模型和数据集；不含任何夸克的代码、模型或素材。
6. **用数据说话。** 每个里程碑用同一套真实照片测试集客观评测（见 [PLAN](docs/PLAN.md#客观评测)）。

## 技术栈
Swift + SwiftUI，最低 iOS 17 / iPhone 12。工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成。

```bash
brew install xcodegen
xcodegen generate
open LocalScan.xcodeproj
```

## 状态
- **M0（脚手架 + CI）**：完成。XcodeGen 工程、SwiftUI 占位 App、单元测试 target、CI 与文档均已入库。
- **M1（MVP：拍摄、自动找边、透视拉正、导出）**：进行中。已实现：
  - 相机取景 + 实时找边 + 自动/手动拍摄；透视拉正 + 角点细化；
  - 手动四角编辑（带放大镜）；多页管理（排序、删除、重拍、重新裁剪）；
  - 滤镜：原图 / 灰度 / 黑白；图片导出（JPEG/HEIC，质量 0.85）与多页 PDF（200–300 DPI）；
  - **待完成**：真机测量（找边精度、单页耗时、20 页 PDF 导出耗时/大小、内存）。
- **M2（弯曲书页展平 + 经典增强 + 保真模式）**：已开始。经典「增强」滤镜已落地（低分辨率光照估计 → 除法归一化 → 温和对比度 + 轻锐化，Core Image，确定性）；书页模型、弯曲判定、展平（UVDoc 等）均**未开始**。M1 的真机测量仍待完成。
- M3：未开始，见 [docs/PLAN.md](docs/PLAN.md)。

## 目录
| 路径 | 内容 |
|---|---|
| `LocalScan/` | App 源码 |
| `LocalScanTests/` | 单元测试 |
| `docs/PLAN.md` | 分阶段计划、验收标准、评测方法、硬规则 |
| `docs/ADR-0001-on-device-first.md` | 架构决策：端侧优先 |
| `docs/research/` | 竞品与技术调研、逆向研究（设计层面）摘要 |
| `prototypes/kimi-web/` | 用户用 Kimi 做的网页原型，仅供参考 |
| `CONTRIBUTING.md` | 给开发机器人的协作规则 |
