#!/usr/bin/env python3
"""处理耗时统计：读取 predictions.json 或 timings.json 的 ms 字段。

输出 count / P50 / P95 / max，并对照 docs/PLAN.md M1 目标：
P50 <= 1000 ms，P95 <= 1500 ms。

百分位采用 nearest-rank（最近秩）定义：排序后取
ceil(p / 100 * N) - 1 处的值；数据量很小或正好落点时的行为是确定的。
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from typing import Any, Dict, List, Optional, Sequence

P50_TARGET_MS = 1000.0
P95_TARGET_MS = 1500.0


def percentile(values: Sequence[float], percent: float) -> Optional[float]:
    """nearest-rank 百分位；空序列返回 None。"""
    if not values:
        return None
    ordered = sorted(float(value) for value in values)
    if percent <= 0:
        return ordered[0]
    if percent >= 100:
        return ordered[-1]
    rank = math.ceil(percent / 100.0 * len(ordered))
    index = min(len(ordered) - 1, max(0, rank - 1))
    return ordered[index]


def _records(document: Any) -> List[Any]:
    if isinstance(document, list):
        return document
    if isinstance(document, dict):
        for key in ("images", "timings"):
            if key in document:
                value = document[key]
                return value if isinstance(value, list) else [value]
        if "ms" in document:
            value = document["ms"]
            return value if isinstance(value, list) else [document]
    raise ValueError("JSON 顶层应为数组，或包含 images/timings/ms 字段")


def extract_ms(document: Any) -> List[float]:
    """从 predictions.json / timings.json 中提取所有有效 ms。"""
    values: List[float] = []
    for index, record in enumerate(_records(document)):
        if isinstance(record, dict):
            if "ms" not in record:
                continue
            raw = record["ms"]
        elif isinstance(record, (int, float)) and not isinstance(record, bool):
            raw = record
        else:
            continue
        try:
            value = float(raw)
        except (TypeError, ValueError) as error:
            raise ValueError(f"第 {index} 条记录的 ms 不是数字: {raw!r}") from error
        if not math.isfinite(value) or value < 0:
            raise ValueError(f"第 {index} 条记录的 ms 无效: {raw!r}")
        values.append(value)
    if not values:
        raise ValueError("没有找到任何 ms 字段")
    return values


def summarize(values: Sequence[float]) -> Dict[str, Any]:
    p50 = percentile(values, 50)
    p95 = percentile(values, 95)
    maximum = max(values) if values else None
    passed = bool(p50 is not None and p95 is not None
                  and p50 <= P50_TARGET_MS and p95 <= P95_TARGET_MS)
    return {
        "count": len(values),
        "p50_ms": p50,
        "p95_ms": p95,
        "max_ms": maximum,
        "targets": {"p50_ms": P50_TARGET_MS, "p95_ms": P95_TARGET_MS},
        "passed": passed,
    }


def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def _fmt(value: Optional[float]) -> str:
    return "N/A" if value is None else f"{value:.1f}"


def print_report(report: Dict[str, Any]) -> None:
    p50_ok = report["p50_ms"] is not None and report["p50_ms"] <= P50_TARGET_MS
    p95_ok = report["p95_ms"] is not None and report["p95_ms"] <= P95_TARGET_MS
    print(f"样本数: {report['count']}")
    print(f"P50: {_fmt(report['p50_ms'])} ms"
          f"（目标 <= {P50_TARGET_MS:.0f} ms：{'PASS' if p50_ok else 'FAIL'}）")
    print(f"P95: {_fmt(report['p95_ms'])} ms"
          f"（目标 <= {P95_TARGET_MS:.0f} ms：{'PASS' if p95_ok else 'FAIL'}）")
    print(f"Max: {_fmt(report['max_ms'])} ms")
    print(f"结论: {'PASS' if report['passed'] else 'FAIL'}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="统计 predictions.json / timings.json 的处理耗时。")
    parser.add_argument("input", nargs="?", metavar="JSON",
                        help="predictions.json 或 timings.json")
    parser.add_argument("-i", "--input", dest="input_option", metavar="JSON",
                        help="同位置参数")
    parser.add_argument("--json", action="store_true", help="输出 JSON 报告")
    parser.add_argument("--strict", action="store_true",
                        help="目标不达标时以退出码 1 结束")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    path = args.input_option or args.input
    if not path:
        parser.error("需要 predictions.json 或 timings.json 路径")

    try:
        report = summarize(extract_ms(load_json(path)))
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
