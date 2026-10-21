"""eval/ 脚本的单元测试：全部用合成数字，不读取任何图片。"""

import math
import sys
import unittest
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parents[1]
if str(EVAL_DIR) not in sys.path:
    sys.path.insert(0, str(EVAL_DIR))

import score_iou  # noqa: E402
import timing_report  # noqa: E402


def square(left, top, right, bottom):
    return [[left, top], [right, top], [right, bottom], [left, bottom]]


def label_image(file, width, height, quad):
    return {"file": file, "width": width, "height": height, "quad": quad}


class PolygonIoUTests(unittest.TestCase):
    def test_identical_quads_have_iou_one(self):
        quad = square(10, 20, 210, 120)
        self.assertAlmostEqual(score_iou.polygon_iou(quad, quad), 1.0, places=9)

    def test_disjoint_quads_have_iou_zero(self):
        first = square(0, 0, 100, 100)
        second = square(200, 200, 300, 300)
        self.assertEqual(score_iou.polygon_iou(first, second), 0.0)

    def test_half_overlap_is_one_third(self):
        # 两个 2x2 方块错开一半：交集 2，并集 6，IoU = 1/3。
        first = square(0, 0, 2, 2)
        second = square(1, 0, 3, 2)
        self.assertAlmostEqual(score_iou.polygon_iou(first, second),
                               1.0 / 3.0, places=6)

    def test_degenerate_quad_is_zero(self):
        degenerate = [[0, 0], [0, 0], [0, 0], [0, 0]]
        self.assertEqual(score_iou.polygon_iou(degenerate,
                                               square(0, 0, 10, 10)), 0.0)


class ScoreDocumentTests(unittest.TestCase):
    def test_prediction_is_scaled_to_label_size(self):
        labels = {"images": [
            label_image("001.jpg", 1000, 800,
                        square(100, 80, 900, 720)),
        ]}
        predictions = {"images": [
            # 宽高各是标注的一半，坐标也按比例减半。
            label_image("001.jpg", 500, 400,
                        square(50, 40, 450, 360)),
        ]}
        report = score_iou.score_documents(labels, predictions)
        self.assertEqual(report["count"], 1)
        self.assertAlmostEqual(report["images"][0]["iou"], 1.0, places=9)
        self.assertFalse(report["images"][0]["missing"])
        self.assertTrue(report["passed"])

    def test_missing_prediction_counts_as_zero_iou(self):
        labels = {"images": [
            label_image("001.jpg", 100, 100, square(0, 0, 100, 100)),
            label_image("002.jpg", 100, 100, square(0, 0, 100, 100)),
        ]}
        predictions = {"images": [
            label_image("001.jpg", 100, 100, square(0, 0, 100, 100)),
        ]}
        report = score_iou.score_documents(labels, predictions)
        self.assertEqual(report["count"], 2)
        self.assertEqual(report["missing_predictions"], 1)
        self.assertEqual(report["images"][1]["iou"], 0.0)
        self.assertTrue(report["images"][1]["missing"])
        self.assertAlmostEqual(report["failure_rate"], 0.5)
        self.assertFalse(report["passed"])

    def test_median_and_failure_thresholds(self):
        labels = {"images": [
            label_image("001.jpg", 100, 100, square(0, 0, 100, 100)),
            label_image("002.jpg", 100, 100, square(0, 0, 100, 100)),
            label_image("003.jpg", 100, 100, square(0, 0, 100, 100)),
        ]}
        predictions = {"images": [
            label_image("001.jpg", 100, 100, square(0, 0, 100, 100)),
            label_image("002.jpg", 100, 100, square(0, 0, 100, 100)),
            # 003 缺失 -> IoU 0。
        ]}
        report = score_iou.score_documents(labels, predictions)
        self.assertAlmostEqual(report["median_iou"], 1.0)
        self.assertAlmostEqual(report["failure_rate"], 1.0 / 3.0)
        self.assertFalse(report["passed"])


class PercentileTests(unittest.TestCase):
    def test_nearest_rank_p50_and_p95(self):
        values = [10, 20, 30, 40]
        self.assertEqual(timing_report.percentile(values, 50), 20)
        self.assertEqual(timing_report.percentile(values, 95), 40)
        self.assertEqual(timing_report.percentile([1, 2, 3, 4, 5], 50), 3)
        self.assertEqual(timing_report.percentile([1, 2, 3, 4, 5], 95), 5)

    def test_percentile_of_empty_and_single_value(self):
        self.assertIsNone(timing_report.percentile([], 50))
        self.assertEqual(timing_report.percentile([42], 50), 42)
        self.assertEqual(timing_report.percentile([42], 95), 42)

    def test_summary_targets(self):
        report = timing_report.summarize([900, 1000, 1200, 1500])
        self.assertEqual(report["count"], 4)
        self.assertEqual(report["p50_ms"], 1000)
        self.assertEqual(report["p95_ms"], 1500)
        self.assertEqual(report["max_ms"], 1500)
        self.assertTrue(report["passed"])

        over = timing_report.summarize([1001, 1501])
        self.assertFalse(over["passed"])

    def test_extract_ms_from_predictions_and_timings(self):
        predictions = {"images": [
            {"file": "a.jpg", "ms": 10},
            {"file": "b.jpg"},
            {"file": "c.jpg", "ms": 30.5},
        ]}
        self.assertEqual(timing_report.extract_ms(predictions), [10.0, 30.5])
        timings = {"timings": [{"ms": 5}, {"ms": 7}]}
        self.assertEqual(timing_report.extract_ms(timings), [5.0, 7.0])
        self.assertTrue(math.isclose(
            timing_report.extract_ms({"ms": [1, 2]})[0], 1.0))


if __name__ == "__main__":
    unittest.main()
