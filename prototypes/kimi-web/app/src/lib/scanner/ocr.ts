import { createWorker, type Worker } from "tesseract.js";

let worker: Worker | null = null;
let creating: Promise<Worker> | null = null;

/** 懒加载中英文 OCR worker（首次调用时下载语言包，之后常驻） */
export async function getOcrWorker(
  onProgress?: (pct: number) => void
): Promise<Worker> {
  if (worker) return worker;
  if (creating) return creating;
  creating = createWorker(["chi_sim", "eng"], 1, {
    logger: (m) => {
      if (m.status === "recognizing text" && onProgress) {
        onProgress(Math.round(m.progress * 100));
      }
    },
  }).then((w) => {
    worker = w;
    return w;
  });
  return creating;
}

/** 对一张图片（dataURL）做 OCR，返回纯文本 */
export async function recognizeText(
  image: string,
  onProgress?: (pct: number) => void
): Promise<string> {
  const w = await getOcrWorker(onProgress);
  const { data } = await w.recognize(image);
  return data.text.trim();
}

/** 预加载（空闲时调用，缩短首次 OCR 等待） */
export function warmupOcr(): void {
  getOcrWorker().catch(() => {
    // 静默失败：网络不可用时不影响其他功能
  });
}
