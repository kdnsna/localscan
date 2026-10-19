export type Point = { x: number; y: number };
export type Quad = [Point, Point, Point, Point]; // TL, TR, BR, BL

export type FilterId = "original" | "enhance" | "mono" | "gray";

export interface ScanPage {
  id: string;
  /** 透视矫正后的原图（未加滤镜） */
  rectified: string; // dataURL
  width: number;
  height: number;
  filter: FilterId;
  /** 应用当前滤镜后的展示图 */
  display: string; // dataURL
  ocrText: string | null;
  ocrStatus: "idle" | "running" | "done" | "error";
}

export const FILTERS: { id: FilterId; label: string }[] = [
  { id: "original", label: "原图" },
  { id: "enhance", label: "智能增强" },
  { id: "mono", label: "黑白文档" },
  { id: "gray", label: "灰度" },
];

export function uid(): string {
  return Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
}
