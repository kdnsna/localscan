import { jsPDF } from "jspdf";
import type { ScanPage } from "@/types/scan";
import { loadImage } from "./filters";

function stamp(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}`;
}

function triggerDownload(url: string, filename: string) {
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}

/** 导出单页为 JPG */
export function exportPageImage(page: ScanPage, index: number) {
  triggerDownload(page.display, `快扫-${stamp()}-第${index + 1}页.jpg`);
}

/** 全部页面导出为图片（逐张下载） */
export function exportAllImages(pages: ScanPage[]) {
  pages.forEach((p, i) => {
    setTimeout(() => exportPageImage(p, i), i * 300);
  });
}

/** 全部页面合成一个 PDF（A4 适配，保持长宽比） */
export async function exportPdf(pages: ScanPage[]): Promise<void> {
  const doc = new jsPDF({ unit: "mm", format: "a4", compress: true });
  const pageW = 210;
  const pageH = 297;
  const margin = 6;

  for (let i = 0; i < pages.length; i++) {
    const page = pages[i];
    const img = await loadImage(page.display);
    const availW = pageW - margin * 2;
    const availH = pageH - margin * 2;
    const ratio = Math.min(availW / img.width, availH / img.height);
    const w = img.width * ratio;
    const h = img.height * ratio;
    const x = (pageW - w) / 2;
    const y = (pageH - h) / 2;
    if (i > 0) doc.addPage();
    doc.addImage(page.display, "JPEG", x, y, w, h, undefined, "FAST");
  }
  doc.save(`快扫-${stamp()}.pdf`);
}
