# Kimi 网页原型（仅供参考）

这是用户用 Kimi 生成的一个网页版扫描原型，原样收录在 `app/` 下（去掉了 `node_modules`、`dist`，保留 `package-lock.json`），**不是** LocalScan iOS App 的代码，也**不会**被原生 App 复用。

## 它是什么
- 技术栈：React + Vite + OpenCV.js + Tesseract.js + jsPDF。
- 页面流程：首页 → 相机 → 裁剪编辑 → 滤镜工作区 → 导出。
- 处理：Canny 轮廓找四边形、手动拖角裁剪、透视拉正；滤镜「原图 / 增强（灰度世界白平衡 + 直方图拉伸 + 反锐化）/ 黑白（自适应阈值）/ 灰度」；Tesseract OCR；jsPDF 导出 A4。
- 没有曲面展平，也没有任何机器学习模型。

## 在本项目里的用途
1. 交互参考：页面流程和滤镜分组是原生 App 的 UX 参照。
2. 评测基线：它的经典 CV 流程是评测里的「经典基线」，原生 App 必须在找边 IoU 和耗时上都胜过它。
3. 可借鉴的点：找边失败时默认给一个内缩 6% 的四边形；找边前把图缩到 1080 px。

详见 [`docs/PLAN.md`](../../docs/PLAN.md) 的「Kimi 网页原型的参考价值」。

> 注意：Tesseract.js 运行时会从网络下载语言包，违反本项目「不上云」的硬规则，所以原生 App 用 Vision OCR。

## 本地运行（可选）
```bash
cd prototypes/kimi-web/app
npm ci
npm run dev
```
