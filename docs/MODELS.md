# 随包模型

## UVDocCoreML

- 来源：UVDoc，Tanguy MAGNE，MIT License。原项目：`https://github.com/tanguymagne/UVDoc`。
- 文件：`LocalScan/Resources/Models/UVDocCoreML.mlpackage`，约 15.86 MB；许可文本同目录 `UVDoc-LICENSE.txt`。
- 转换：仅保留 2D 网格输出头，FP16，最低部署目标 iOS 17。输入 `image` 为 488×712 RGB，输出 `grid` 为 `[1, 2, 45, 31]` FLOAT16。由随附参考产物直接集成，未在本仓库重新转换。
- SHA-256：`model.mlmodel` = `f0a34086aeb0ff7467e918550b9a9b9fa5ad4934d7d21e4ab1481957eb64088c`；`weights/weight.bin` = `81be4cd2ddfc1497353ec663fa008fdde61035d6ec0ee1ecfbb00299bb0908ab`。
- 用途：只对廉价判定为弯曲的页面运行；模型、Metal 或推理失败时保留透视结果。
- 验证状态：参考产物已通过模型规格检查、PyTorch FP16/FP32 数值对比和 Metal 数学等价检查；Core ML runtime 数值、真机精度与耗时仍待 macOS/iPhone 验证。

随包模型总量目前低于 25 MB。转换工具不进入 App，也不构成运行时依赖。
