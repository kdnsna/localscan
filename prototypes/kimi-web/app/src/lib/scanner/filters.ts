import type { FilterId } from "@/types/scan";
import { adaptiveMono } from "./cv";

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}

/** 智能增强：白平衡（灰度世界）+ 对比度拉伸 + 轻微锐化 */
function enhance(canvas: HTMLCanvasElement): HTMLCanvasElement {
  const ctx = canvas.getContext("2d")!;
  const { width: w, height: h } = canvas;
  const imageData = ctx.getImageData(0, 0, w, h);
  const d = imageData.data;

  // 1) 灰度世界白平衡
  let sumR = 0, sumG = 0, sumB = 0;
  const n = w * h;
  for (let i = 0; i < d.length; i += 4) {
    sumR += d[i]; sumG += d[i + 1]; sumB += d[i + 2];
  }
  const avgR = sumR / n, avgG = sumG / n, avgB = sumB / n;
  const avgAll = (avgR + avgG + avgB) / 3;
  const kR = avgAll / (avgR || 1), kG = avgAll / (avgG || 1), kB = avgAll / (avgB || 1);

  // 2) 亮度直方图 1%–99% 拉伸（按灰度）
  const hist = new Uint32Array(256);
  const lum = new Uint8Array(n);
  for (let p = 0, i = 0; p < n; p++, i += 4) {
    const g = Math.round(0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]);
    lum[p] = g;
    hist[g]++;
  }
  let lo = 0, hi = 255, acc = 0;
  const loT = n * 0.01, hiT = n * 0.99;
  for (let v = 0; v < 256; v++) {
    acc += hist[v];
    if (acc >= loT) { lo = v; break; }
  }
  acc = 0;
  for (let v = 0; v < 256; v++) {
    acc += hist[v];
    if (acc >= hiT) { hi = v; break; }
  }
  const range = Math.max(1, hi - lo);
  const map = new Float32Array(256);
  for (let v = 0; v < 256; v++) {
    map[v] = Math.min(255, Math.max(0, ((v - lo) / range) * 255));
  }

  for (let p = 0, i = 0; p < n; p++, i += 4) {
    const l = lum[p];
    const ratio = l > 0 ? map[l] / l : 1;
    d[i] = Math.min(255, d[i] * kR * ratio * 1.02);
    d[i + 1] = Math.min(255, d[i + 1] * kG * ratio * 1.02);
    d[i + 2] = Math.min(255, d[i + 2] * kB * ratio * 1.02);
  }
  ctx.putImageData(imageData, 0, 0);

  // 3) 轻微锐化（unsharp mask 简化版）
  const sharpened = ctx.getImageData(0, 0, w, h);
  const src = new Uint8ClampedArray(sharpened.data);
  const sd = sharpened.data;
  const amount = 0.35;
  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      const i = (y * w + x) * 4;
      for (let c = 0; c < 3; c++) {
        const center = src[i + c] * 5;
        const neighbors =
          src[i - 4 + c] + src[i + 4 + c] + src[i - w * 4 + c] + src[i + w * 4 + c];
        sd[i + c] = Math.min(
          255,
          Math.max(0, src[i + c] + ((center - neighbors) / 4) * amount * 4)
        );
      }
    }
  }
  ctx.putImageData(sharpened, 0, 0);
  return canvas;
}

/** 灰度 */
function grayscale(canvas: HTMLCanvasElement): HTMLCanvasElement {
  const ctx = canvas.getContext("2d")!;
  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const d = imageData.data;
  for (let i = 0; i < d.length; i += 4) {
    const g = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
    d[i] = d[i + 1] = d[i + 2] = g;
  }
  ctx.putImageData(imageData, 0, 0);
  return canvas;
}

function dataUrlToCanvas(dataUrl: string, w: number, h: number): Promise<HTMLCanvasElement> {
  return loadImage(dataUrl).then((img) => {
    const c = document.createElement("canvas");
    c.width = w;
    c.height = h;
    c.getContext("2d")!.drawImage(img, 0, 0, w, h);
    return c;
  });
}

/** 对矫正后的图片应用滤镜，返回 dataURL */
export async function applyFilter(
  rectifiedDataUrl: string,
  width: number,
  height: number,
  filter: FilterId
): Promise<string> {
  if (filter === "original") return rectifiedDataUrl;
  const canvas = await dataUrlToCanvas(rectifiedDataUrl, width, height);
  let out: HTMLCanvasElement;
  switch (filter) {
    case "enhance":
      out = enhance(canvas);
      break;
    case "mono":
      out = adaptiveMono(canvas);
      break;
    case "gray":
      out = grayscale(canvas);
      break;
    default:
      out = canvas;
  }
  return out.toDataURL("image/jpeg", 0.92);
}

export { loadImage, dataUrlToCanvas };
