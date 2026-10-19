import type { Point, Quad } from "@/types/scan";

/* eslint-disable @typescript-eslint/no-explicit-any */
let cvInstance: any = null;
let loading: Promise<any> | null = null;

/** 异步加载 OpenCV（WASM 内嵌单文件），返回 cv 实例 */
export function loadOpenCV(): Promise<any> {
  if (cvInstance) return Promise.resolve(cvInstance);
  if (loading) return loading;
  loading = (async () => {
    const mod: any = await import("@techstark/opencv-js");
    let cv: any = mod.default ?? mod;
    // 兼容三种导出形态：MODULARIZE 工厂函数 / Promise 模块 / 回调式模块
    if (typeof cv === "function") cv = cv();
    if (typeof cv?.then === "function") cv = await cv;
    if (!cv.Mat) {
      await new Promise<void>((resolve) => {
        const done = () => resolve();
        cv.onRuntimeInitialized = done;
        const timer = setInterval(() => {
          if (cv.Mat) {
            clearInterval(timer);
            done();
          }
        }, 200);
      });
    }
    cvInstance = cv;
    return cv;
  })();
  // 30s 超时兜底：超时后拒绝，由调用方走降级路径
  return Promise.race([
    loading,
    new Promise<any>((_, reject) =>
      setTimeout(() => reject(new Error("OpenCV 加载超时")), 30000)
    ),
  ]);
}

export function isCvReady(): boolean {
  return !!cvInstance;
}

/** 将检测点按 左上→右上→右下→左下 排序 */
export function orderPoints(pts: Point[]): Quad {
  const sorted = [...pts].sort((a, b) => a.y - b.y);
  const [t1, t2] = sorted.slice(0, 2).sort((a, b) => a.x - b.x);
  const [b1, b2] = sorted.slice(2, 4).sort((a, b) => a.x - b.x);
  return [t1, t2, b2, b1];
}

/** 默认四边形：向内缩 6% 的安全框 */
export function defaultQuad(w: number, h: number): Quad {
  const mx = w * 0.06;
  const my = h * 0.06;
  return [
    { x: mx, y: my },
    { x: w - mx, y: my },
    { x: w - mx, y: h - my },
    { x: mx, y: h - my },
  ];
}

/**
 * 文档边缘检测：降采样 → 灰度 → 高斯 → Canny → 膨胀 → 最大四边形轮廓
 * 返回原图坐标系下的 Quad；未找到返回 null
 */
export function detectDocumentQuad(
  source: HTMLCanvasElement,
  maxDim = 1080
): Quad | null {
  const cv = cvInstance;
  if (!cv) return null;
  const scale = Math.min(1, maxDim / Math.max(source.width, source.height));
  const w = Math.round(source.width * scale);
  const h = Math.round(source.height * scale);

  const src = cv.imread(source);
  const resized = new cv.Mat();
  const gray = new cv.Mat();
  const blurred = new cv.Mat();
  const edges = new cv.Mat();
  const kernel = cv.Mat.ones(3, 3, cv.CV_8U);
  const contours = new cv.MatVector();
  const hierarchy = new cv.Mat();
  let result: Quad | null = null;

  try {
    cv.resize(src, resized, new cv.Size(w, h), 0, 0, cv.INTER_AREA);
    cv.cvtColor(resized, gray, cv.COLOR_RGBA2GRAY);
    cv.GaussianBlur(gray, blurred, new cv.Size(5, 5), 0);
    cv.Canny(blurred, edges, 60, 180);
    cv.dilate(edges, edges, kernel);
    cv.findContours(
      edges,
      contours,
      hierarchy,
      cv.RETR_LIST,
      cv.CHAIN_APPROX_SIMPLE
    );

    let bestArea = 0;
    let best: Point[] | null = null;
    const minArea = w * h * 0.2; // 至少占画面 20%

    for (let i = 0; i < contours.size(); i++) {
      const cnt = contours.get(i);
      const peri = cv.arcLength(cnt, true);
      const approx = new cv.Mat();
      cv.approxPolyDP(cnt, approx, 0.02 * peri, true);
      const area = cv.contourArea(approx);
      if (approx.rows === 4 && area > minArea && area > bestArea) {
        bestArea = area;
        const pts: Point[] = [];
        for (let j = 0; j < 4; j++) {
          pts.push({
            x: approx.intPtr(j, 0)[0] / scale,
            y: approx.intPtr(j, 0)[1] / scale,
          });
        }
        best = pts;
      }
      approx.delete();
      cnt.delete();
    }
    if (best) result = orderPoints(best);
  } finally {
    src.delete();
    resized.delete();
    gray.delete();
    blurred.delete();
    edges.delete();
    kernel.delete();
    contours.delete();
    hierarchy.delete();
  }
  return result;
}

/** 透视矫正：把 quad 区域拉正为矩形画布 */
export function warpPerspective(
  source: HTMLCanvasElement,
  quad: Quad
): HTMLCanvasElement {
  const cv = cvInstance;
  const [tl, tr, br, bl] = quad;
  const wTop = Math.hypot(tr.x - tl.x, tr.y - tl.y);
  const wBot = Math.hypot(br.x - bl.x, br.y - bl.y);
  const hLeft = Math.hypot(bl.x - tl.x, bl.y - tl.y);
  const hRight = Math.hypot(br.x - tr.x, br.y - tr.y);
  const outW = Math.max(2, Math.round(Math.max(wTop, wBot)));
  const outH = Math.max(2, Math.round(Math.max(hLeft, hRight)));

  if (!cv) {
    // OpenCV 未就绪的兜底：纯 canvas 按包围盒裁剪
    const out = document.createElement("canvas");
    out.width = outW;
    out.height = outH;
    const ctx = out.getContext("2d")!;
    const minX = Math.min(tl.x, bl.x);
    const minY = Math.min(tl.y, tr.y);
    ctx.drawImage(source, minX, minY, outW, outH, 0, 0, outW, outH);
    return out;
  }

  const src = cv.imread(source);
  const dst = new cv.Mat();
  const srcTri = cv.matFromArray(4, 1, cv.CV_32FC2, [
    tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y,
  ]);
  const dstTri = cv.matFromArray(4, 1, cv.CV_32FC2, [
    0, 0, outW, 0, outW, outH, 0, outH,
  ]);
  try {
    const M = cv.getPerspectiveTransform(srcTri, dstTri);
    cv.warpPerspective(
      src,
      dst,
      M,
      new cv.Size(outW, outH),
      cv.INTER_LINEAR,
      cv.BORDER_CONSTANT,
      new cv.Scalar()
    );
    M.delete();
    const out = document.createElement("canvas");
    out.width = outW;
    out.height = outH;
    cv.imshow(out, dst);
    return out;
  } finally {
    src.delete();
    dst.delete();
    srcTri.delete();
    dstTri.delete();
  }
}

/** OpenCV 自适应阈值（黑白文档滤镜） */
export function adaptiveMono(source: HTMLCanvasElement): HTMLCanvasElement {
  const cv = cvInstance;
  const out = document.createElement("canvas");
  out.width = source.width;
  out.height = source.height;
  if (!cv) {
    out.getContext("2d")!.drawImage(source, 0, 0);
    return out;
  }
  const src = cv.imread(source);
  const gray = new cv.Mat();
  const bin = new cv.Mat();
  try {
    cv.cvtColor(src, gray, cv.COLOR_RGBA2GRAY);
    cv.adaptiveThreshold(
      gray,
      bin,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY,
      21,
      12
    );
    cv.imshow(out, bin);
    return out;
  } finally {
    src.delete();
    gray.delete();
    bin.delete();
  }
}
