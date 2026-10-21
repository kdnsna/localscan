# 离线找边评测（eval/）

这里只放**评测脚本与格式说明**，不放任何照片、扫描结果或模型权重。
照片可以放在 `eval/data/`（已被 `.gitignore` 忽略），也可以放在仓库外的任意本地目录。

## 数据目录约定

推荐结构（`eval/data/` 整个目录永不提交）：

```
eval/data/
├── images/              # 可选，照片也可以直接平铺在 eval/data/
│   ├── 001.jpg
│   └── 002.heic
├── labels.json          # 人工标注的四边形
└── predictions.json     # 在模拟器/真机上跑 EvalHarnessTests 生成
```

`EvalHarnessTests` 不递归子目录；把待评测的 `jpg` / `jpeg` / `heic` / `png`
直接放在环境变量 `LOCALSCAN_EVAL_DIR` 指向的目录里即可。

## 标注格式（labels.json）

坐标系与 App 一致：**左上原点、x 向右、y 向下，单位是原图像素**。
四个角点顺序固定为 **TL、TR、BR、BL**，每点 `[x, y]`。

```json
{
  "images": [
    {
      "file": "001.jpg",
      "width": 3024,
      "height": 4032,
      "quad": [
        [412, 530],
        [2610, 488],
        [2660, 3520],
        [380, 3468]
      ]
    }
  ]
}
```

- `file`：图片文件名（不含目录，需与评测目录中的文件同名）。
- `width` / `height`：原图像素数，即标注坐标所在的尺寸。
- `quad`：四个角点，顺序必须是左上、右上、右下、左下。

## 预测格式（predictions.json）

`EvalHarnessTests` 会写入同样的字段，并额外记录 `ms`：

```json
{
  "images": [
    {
      "file": "001.jpg",
      "width": 3024,
      "height": 4032,
      "quad": [
        [408, 526],
        [2608, 491],
        [2655, 3518],
        [384, 3470]
      ],
      "ms": 842.7
    }
  ]
}
```

- 预测的 `width` / `height` 若与标注不同，评分脚本会按
  `标注宽 / 预测宽`、`标注高 / 预测高` 分别缩放预测坐标后再算 IoU。
- `ms` 可选；缺失该字段的图片不参与耗时统计。
- 标注里存在、预测里缺失的图片按 **IoU = 0** 计入，因此也会拉高失败率。
- 其他额外字段会被忽略；不会写入任何像素数据。

## 在 App 上跑预测（需要 macOS + Xcode）

`EvalHarnessTests` 只有在设置 `LOCALSCAN_EVAL_DIR` 时才运行，否则自动
`XCTSkip`。在模拟器里通过 `TEST_RUNNER_` 前缀把变量传给测试进程
（Xcode 会去掉该前缀）：

```bash
export TEST_RUNNER_LOCALSCAN_EVAL_DIR="$PWD/eval/data"
export TEST_RUNNER_LOCALSCAN_EVAL_OUT="$PWD/eval/data"   # 可省略，默认同目录

xcodebuild test \
  -project LocalScan.xcodeproj \
  -scheme LocalScan \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:LocalScanTests/EvalHarnessTests \
  CODE_SIGNING_ALLOWED=NO
```

流程：`CaptureDecoder().decode(data)` → `DocumentQuadDetector.detect(in:)`
→ 把检测到的四边形从工作图尺寸映射回原图尺寸 → `ProcessingQueue().process(...)`
（用 `ContinuousClock` 计时）→ 写入 `LOCALSCAN_EVAL_OUT/predictions.json`
（默认与照片同目录）。也可以用真机跑同一个测试；真机上的绝对耗时才有
PLAN 所说的参考价值。

## 运行评分与耗时统计

```bash
# 逐张 IoU、中位数、失败率（IoU < 0.90）；不达标也返回 0
python3 eval/score_iou.py \
  --labels eval/data/labels.json \
  --predictions eval/data/predictions.json

# 机器可读输出；--strict 时阈值不达标退出码为 1
python3 eval/score_iou.py \
  --labels eval/data/labels.json \
  --predictions eval/data/predictions.json \
  --json --strict

# count / P50 / P95 / max，对照 P50 <= 1000 ms、P95 <= 1500 ms
python3 eval/timing_report.py eval/data/predictions.json
python3 eval/timing_report.py eval/data/predictions.json --json --strict

# 只跑脚本自己的单元测试（全部是合成数字，不需要照片）
python3 -m unittest discover -s eval/tests
```

`timing_report.py` 也接受 `{"timings":[{"ms":...}, ...]}` 或
`{"timings":[123, 456]}` 形式的 `timings.json`；没有 `ms` 的记录会被跳过。

验收阈值来自 `docs/PLAN.md` M1：

- 找边 IoU 中位数 **≥ 0.95**；
- 失败率（IoU **< 0.90**）**≤ 5%**；
- 单页「按快门 → 成品」P50 **≤ 1000 ms**、P95 **≤ 1500 ms**（iPhone 12 目标，
  需要真机测量）。

`timing_report.py` 的百分位使用 nearest-rank：排序后取
`ceil(p / 100 × N) - 1` 处的值。

## 隐私与仓库规则

1. **照片绝不进仓库。** 真实照片、扫描结果、`.heic` / `.jpg` / `.png` 等
   一律放在 `eval/data/`（已忽略）或仓库外；不要用 `git add -f` 绕过。
2. **不要提交模型权重。** 评测只调用 App/系统现有能力，本目录不含模型。
3. **只提交标注格式、脚本和汇总分数。** 仓库里可以有脚本、`eval/README.md`
   和脱敏的汇总表，不能有可还原用户内容的图片、文字或 EXIF。
4. **完全离线。** 评测脚本只用 Python 标准库，不访问网络、不安装依赖；
   App 端由 CI 的 `scripts/check_no_network.sh` 做静态无网络检查。
5. **隐私照片先打码/脱敏**再用于人工评测；标注文件同样可能暴露内容，默认
   放在仓库外或 `eval/data/`。
