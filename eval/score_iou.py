#!/usr/bin/env python3
"""四边形找边精度评测：凸多边形 IoU（纯标准库）。

标签与预测格式见 eval/README.md：

    labels.json      {"images":[{"file":..., "width":..., "height":...,
                                 "quad":[[x,y],[x,y],[x,y],[x,y]]}]}
    predictions.json 同上，可额外带 "ms"

预测坐标若与标注尺寸不同，会先按宽高比例缩放到标注尺寸再计算。
没有对应预测的图片按 IoU = 0 计入，因此也会计入失败率。
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from typing import Any, Dict, List, Optional, Sequence, Tuple

Point = Tuple[float, float]
Polygon = List[Point]

# docs/PLAN.md M1 验收阈值。
MEDIAN_IOU_TARGET = 0.95
FAILURE_IOU_THRESHOLD = 0.90
FAILURE_RATE_TARGET = 0.05

EPS = 1e-12


def signed_area(polygon: Sequence[Point]) -> float:
    """鞋带公式，返回有符号面积（逆时针为正，与屏幕坐标 y 向下无关）。"""
    if len(polygon) < 3:
        return 0.0
    total = 0.0
    for index, point in enumerate(polygon):
        nxt = polygon[(index + 1) % len(polygon)]
        total += point[0] * nxt[1] - nxt[0] * point[1]
    return total * 0.5


def polygon_area(polygon: Sequence[Point]) -> float:
    return abs(signed_area(polygon))


def _cross(ax: float, ay: float, bx: float, by: float) -> float:
    return ax * by - ay * bx


def _inside(point: Point, a: Point, b: Point, orientation: float) -> bool:
    edge_x = b[0] - a[0]
    edge_y = b[1] - a[1]
    point_x = point[0] - a[0]
    point_y = point[1] - a[1]
    return orientation * _cross(edge_x, edge_y, point_x, point_y) >= -EPS


def _segment_intersection(p1: Point, p2: Point,
                          q1: Point, q2: Point) -> Optional[Point]:
    """线段 p1-p2 与 q1-q2 的交点；平行时返回 None。"""
    rx = p2[0] - p1[0]
    ry = p2[1] - p1[1]
    sx = q2[0] - q1[0]
    sy = q2[1] - q1[1]
    denominator = _cross(rx, ry, sx, sy)
    if abs(denominator) <= EPS:
        return None
    qpx = q1[0] - p1[0]
    qpy = q1[1] - p1[1]
    t = _cross(qpx, qpy, sx, sy) / denominator
    # 数值误差可能让交点落在极小范围外，夹回线段内。
    t = min(1.0, max(0.0, t))
    return (p1[0] + t * rx, p1[1] + t * ry)


def clip_polygon(subject: Sequence[Point], clipper: Sequence[Point]) -> Polygon:
    """Sutherland–Hodgman：用凸多边形 clipper 裁剪 subject。"""
    if len(subject) < 3 or len(clipper) < 3:
        return []
    clip_area = signed_area(clipper)
    if abs(clip_area) <= EPS:
        return []
    orientation = 1.0 if clip_area > 0 else -1.0

    output: Polygon = list(subject)
    for index, a in enumerate(clipper):
        if not output:
            break
        b = clipper[(index + 1) % len(clipper)]
        input_points = output
        output = []
        previous = input_points[-1]
        previous_inside = _inside(previous, a, b, orientation)
        for current in input_points:
            current_inside = _inside(current, a, b, orientation)
            if current_inside:
                if not previous_inside:
                    intersection = _segment_intersection(previous, current, a, b)
                    if intersection is not None:
                        output.append(intersection)
                output.append(current)
            elif previous_inside:
                intersection = _segment_intersection(previous, current, a, b)
                if intersection is not None:
                    output.append(intersection)
            previous = current
            previous_inside = current_inside
    return output


def polygon_iou(subject: Sequence[Point], clip: Sequence[Point]) -> float:
    """两个凸多边形的 IoU；退化或无效时返回 0。"""
    area_subject = polygon_area(subject)
    area_clip = polygon_area(clip)
    if area_subject <= EPS or area_clip <= EPS:
        return 0.0
    intersection = polygon_area(clip_polygon(subject, clip))
    union = area_subject + area_clip - intersection
    if union <= EPS:
        return 0.0
    return max(0.0, min(1.0, intersection / union))


# 便于外部脚本/测试使用更直白的名字。
quad_iou = polygon_iou
iou = polygon_iou


def _positive_number(value: Any, context: str) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{context} 不是数字: {value!r}") from error
    if not math.isfinite(number) or number <= 0:
        raise ValueError(f"{context} 必须为正的有限数: {value!r}")
    return number


def _parse_quad(value: Any, context: str) -> Polygon:
    if not isinstance(value, (list, tuple)) or len(value) != 4:
        raise ValueError(f"{context} 必须包含 4 个 [x, y] 点")
    polygon: Polygon = []
    for index, point in enumerate(value):
        if not isinstance(point, (list, tuple)) or len(point) != 2:
            raise ValueError(f"{context}[{index}] 必须是 [x, y]")
        try:
            x = float(point[0])
            y = float(point[1])
        except (TypeError, ValueError) as error:
            raise ValueError(f"{context}[{index}] 不是数字") from error
        if not math.isfinite(x) or not math.isfinite(y):
            raise ValueError(f"{context}[{index}] 含非有限坐标")
        polygon.append((x, y))
    return polygon


def _image_list(document: Any, kind: str) -> List[Any]:
    if isinstance(document, dict):
        images = document.get("images")
    elif isinstance(document, list):
        images = document
    else:
        raise ValueError(f"{kind} 顶层必须是对象或数组")
    if not isinstance(images, list):
        raise ValueError(f"{kind} 缺少 images 数组")
    return images


def normalize_images(document: Any, kind: str) -> List[Dict[str, Any]]:
    """校验并规范化 labels/predictions 的 images 数组。"""
    result: List[Dict[str, Any]] = []
    for index, item in enumerate(_image_list(document, kind)):
        context = f"{kind}.images[{index}]"
        if not isinstance(item, dict):
            raise ValueError(f"{context} 必须是对象")
        filename = item.get("file")
        if not isinstance(filename, str) or not filename:
            raise ValueError(f"{context}.file 必须是非空字符串")
        width = _positive_number(item.get("width"), f"{context}.width")
        height = _positive_number(item.get("height"), f"{context}.height")
        quad = _parse_quad(item.get("quad"), f"{context}.quad")
        result.append({
            "file": filename,
            "width": width,
            "height": height,
            "quad": quad,
        })
    return result


def score_documents(labels: Any, predictions: Any) -> Dict[str, Any]:
    """按文件名为每张标注匹配预测，返回可直接 JSON 序列化的报告。"""
    label_images = normalize_images(labels, "labels")
    prediction_images = normalize_images(predictions, "predictions")
    prediction_by_file = {item["file"]: item for item in prediction_images}

    per_image: List[Dict[str, Any]] = []
    for label in label_images:
        prediction = prediction_by_file.get(label["file"])
        missing = prediction is None
        if missing:
            image_iou = 0.0
        else:
            scale_x = label["width"] / prediction["width"]
            scale_y = label["height"] / prediction["height"]
            scaled = [(x * scale_x, y * scale_y) for x, y in prediction["quad"]]
            image_iou = polygon_iou(scaled, label["quad"])
        per_image.append({
            "file": label["file"],
            "iou": image_iou,
            "missing": missing,
        })

    count = len(per_image)
    missing_count = sum(1 for item in per_image if item["missing"])
    failure_count = sum(1 for item in per_image
                        if item["iou"] < FAILURE_IOU_THRESHOLD)
    median_iou = (statistics.median(item["iou"] for item in per_image)
                  if per_image else None)
    failure_rate = failure_count / count if count else 0.0
    passed = bool(
        median_iou is not None
        and median_iou >= MEDIAN_IOU_TARGET
        and failure_rate <= FAILURE_RATE_TARGET
    )

    return {
        "images": per_image,
        "count": count,
        "missing_predictions": missing_count,
        "median_iou": median_iou,
        "failure_count": failure_count,
        "failure_iou_threshold": FAILURE_IOU_THRESHOLD,
        "failure_rate": failure_rate,
        "thresholds": {
            "median_iou": MEDIAN_IOU_TARGET,
            "failure_rate": FAILURE_RATE_TARGET,
        },
        "passed": passed,
    }


def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def _fmt(value: Optional[float], digits: int = 4) -> str:
    return "N/A" if value is None else f"{value:.{digits}f}"


def print_report(report: Dict[str, Any]) -> None:
    print("每张图片的 IoU：")
    for item in report["images"]:
        suffix = "  (缺失预测，按 IoU=0)" if item["missing"] else ""
        print(f"  {item['file']}\t{_fmt(item['iou'])}{suffix}")

    median = report["median_iou"]
    median_ok = median is not None and median >= MEDIAN_IOU_TARGET
    failure_ok = report["failure_rate"] <= FAILURE_RATE_TARGET
    print()
    print(f"图片数: {report['count']}，缺失预测: {report['missing_predictions']}")
    print(f"IoU 中位数: {_fmt(median)}"
          f"（目标 >= {MEDIAN_IOU_TARGET:.2f}：{'PASS' if median_ok else 'FAIL'}）")
    print(f"失败率 (IoU < {FAILURE_IOU_THRESHOLD:.2f}): "
          f"{report['failure_rate']:.2%}"
          f"（目标 <= {FAILURE_RATE_TARGET:.2%}：{'PASS' if failure_ok else 'FAIL'}）")
    print(f"结论: {'PASS' if report['passed'] else 'FAIL'}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="计算找边四边形 IoU，并对照 docs/PLAN.md M1 阈值。")
    parser.add_argument("labels_positional", nargs="?", metavar="LABELS")
    parser.add_argument("predictions_positional", nargs="?", metavar="PREDICTIONS")
    parser.add_argument("-l", "--labels", dest="labels_option", metavar="LABELS",
                        help="labels.json 路径")
    parser.add_argument("-p", "--predictions", dest="predictions_option",
                        metavar="PREDICTIONS", help="predictions.json 路径")
    parser.add_argument("--json", action="store_true", help="输出 JSON 报告")
    parser.add_argument("--strict", action="store_true",
                        help="阈值不达标时以退出码 1 结束")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    labels_path = args.labels_option or args.labels_positional
    predictions_path = args.predictions_option or args.predictions_positional
    if not labels_path or not predictions_path:
        parser.error("需要 labels 和 predictions 两个 JSON 文件路径")

    try:
        report = score_documents(load_json(labels_path),
                                 load_json(predictions_path))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"错误: {error}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print_report(report)

    if args.strict and not report["passed"]:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
