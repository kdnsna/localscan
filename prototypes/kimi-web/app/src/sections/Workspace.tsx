import { useState } from "react";
import type { ScanPage, FilterId } from "@/types/scan";
import { FILTERS } from "@/types/scan";
import ScanBeam from "@/components/ScanBeam";
import {
  ChevronLeft,
  ChevronRight,
  Camera,
  ImagePlus,
  ScanText,
  Copy,
  X,
  Download,
  FileDown,
  Trash2,
  RotateCw,
  Check,
} from "lucide-react";

interface Props {
  pages: ScanPage[];
  selectedId: string | null;
  ocrProgress: number | null;
  exporting: boolean;
  onSelect: (id: string) => void;
  onFilter: (id: string, filter: FilterId) => void;
  onRotate: (id: string) => void;
  onDelete: (id: string) => void;
  onMove: (id: string, dir: -1 | 1) => void;
  onOcr: (id: string) => void;
  onClearOcr: (id: string) => void;
  onAddCamera: () => void;
  onAddUpload: (files: FileList) => void;
  onExportImages: () => void;
  onExportPdf: () => void;
  onHome: () => void;
}

export default function Workspace({
  pages,
  selectedId,
  ocrProgress,
  exporting,
  onSelect,
  onFilter,
  onRotate,
  onDelete,
  onMove,
  onOcr,
  onClearOcr,
  onAddCamera,
  onAddUpload,
  onExportImages,
  onExportPdf,
  onHome,
}: Props) {
  const page = pages.find((p) => p.id === selectedId) ?? pages[0];
  const [copied, setCopied] = useState(false);
  const index = page ? pages.indexOf(page) : -1;

  if (!page) return null;

  const copyText = async () => {
    if (!page.ocrText) return;
    try {
      await navigator.clipboard.writeText(page.ocrText);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // 剪贴板不可用时静默
    }
  };

  return (
    <div className="flex h-full flex-col">
      {/* 顶栏 */}
      <header className="safe-top flex items-center justify-between border-b border-border px-4 py-3">
        <div className="flex items-center gap-3">
          <button
            onClick={onHome}
            className="flex h-10 w-10 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground focus-visible:outline-2 focus-visible:outline-ring"
            aria-label="返回首页"
          >
            <ChevronLeft className="h-5 w-5" />
          </button>
          <h1 className="text-base font-semibold tracking-tight">
            扫描稿
            <span className="ml-2 text-sm font-normal text-muted-foreground tabular">
              {pages.length} 页
            </span>
          </h1>
        </div>
        <div className="flex items-center gap-2">
          <label
            className="flex h-10 w-10 cursor-pointer items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground focus-within:outline-2 focus-within:outline-ring"
            aria-label="导入图片"
          >
            <ImagePlus className="h-5 w-5" />
            <input
              type="file"
              accept="image/*"
              multiple
              className="sr-only"
              onChange={(e) => {
                if (e.target.files?.length) onAddUpload(e.target.files);
                e.target.value = "";
              }}
            />
          </label>
          <button
            onClick={onAddCamera}
            className="flex h-10 items-center gap-1.5 rounded-full bg-secondary px-4 text-sm font-medium text-secondary-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-ring"
          >
            <Camera className="h-4 w-4" />
            继续扫描
          </button>
        </div>
      </header>

      {/* 主区 */}
      <div className="flex min-h-0 flex-1 flex-col lg:flex-row">
        {/* 预览舞台 */}
        <div className="relative flex min-h-0 flex-1 items-center justify-center overflow-hidden bg-black/40 p-4">
          <div className="relative max-h-full max-w-full overflow-hidden rounded-lg shadow-[0_8px_40px_rgba(0,0,0,0.55)]">
            <img
              src={page.display}
              alt={`第 ${index + 1} 页`}
              className="max-h-[52vh] w-auto max-w-full select-none object-contain lg:max-h-[calc(100dvh-220px)]"
              draggable={false}
            />
            {(page.ocrStatus === "running" || exporting) && (
              <ScanBeam
                label={
                  exporting
                    ? "正在生成文件…"
                    : `识别中 ${ocrProgress ?? 0}%`
                }
              />
            )}
          </div>
          {/* 页码角标 */}
          <span className="absolute left-6 top-6 rounded-full bg-black/60 px-3 py-1 text-xs text-white/85 tabular">
            {index + 1} / {pages.length}
          </span>
        </div>

        {/* 控制面板 */}
        <div className="flex shrink-0 flex-col border-t border-border lg:w-80 lg:border-l lg:border-t-0">
          {/* 滤镜 */}
          <div className="px-4 pt-4">
            <p className="mb-2 text-xs text-muted-foreground">画质</p>
            <div className="grid grid-cols-4 gap-1.5">
              {FILTERS.map((f) => (
                <button
                  key={f.id}
                  onClick={() => onFilter(page.id, f.id)}
                  className={`h-11 rounded-lg text-sm transition-colors focus-visible:outline-2 focus-visible:outline-ring ${
                    page.filter === f.id
                      ? "bg-primary font-medium text-primary-foreground"
                      : "bg-secondary text-secondary-foreground hover:bg-muted"
                  }`}
                >
                  {f.label}
                </button>
              ))}
            </div>
          </div>

          {/* 页面操作 */}
          <div className="flex gap-1.5 px-4 pt-3">
            <button
              onClick={() => onRotate(page.id)}
              className="flex h-11 flex-1 items-center justify-center gap-1.5 rounded-lg bg-secondary text-sm text-secondary-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-ring"
            >
              <RotateCw className="h-4 w-4" />
              旋转
            </button>
            <button
              onClick={() => onOcr(page.id)}
              disabled={page.ocrStatus === "running"}
              className="flex h-11 flex-1 items-center justify-center gap-1.5 rounded-lg bg-secondary text-sm text-secondary-foreground transition-colors hover:bg-muted disabled:opacity-50 focus-visible:outline-2 focus-visible:outline-ring"
            >
              <ScanText className="h-4 w-4" />
              {page.ocrStatus === "running" ? "识别中…" : "识别文字"}
            </button>
            <button
              onClick={() => onDelete(page.id)}
              className="flex h-11 w-12 items-center justify-center rounded-lg bg-secondary text-destructive transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-ring"
              aria-label="删除本页"
            >
              <Trash2 className="h-4 w-4" />
            </button>
          </div>

          {/* 页列表 */}
          <div className="min-h-0 flex-1 px-4 pt-4">
            <p className="mb-2 text-xs text-muted-foreground">全部页面</p>
            <div className="no-scrollbar flex gap-2 overflow-x-auto pb-2 lg:grid lg:grid-cols-3 lg:overflow-visible">
              {pages.map((p, i) => (
                <div
                  key={p.id}
                  className={`group relative shrink-0 overflow-hidden rounded-lg border-2 transition-colors ${
                    p.id === page.id
                      ? "border-primary"
                      : "border-transparent hover:border-border"
                  }`}
                >
                  <button
                    onClick={() => onSelect(p.id)}
                    className="block h-24 w-[72px] focus-visible:outline-2 focus-visible:outline-ring lg:w-full"
                    aria-label={`选择第 ${i + 1} 页`}
                  >
                    <img
                      src={p.display}
                      alt=""
                      className="h-full w-full object-cover"
                      draggable={false}
                    />
                  </button>
                  <span className="absolute bottom-1 left-1 rounded bg-black/65 px-1.5 py-0.5 text-[10px] text-white tabular">
                    {i + 1}
                  </span>
                  {p.id === page.id && pages.length > 1 && (
                    <span className="absolute right-1 top-1 flex gap-0.5">
                      <button
                        onClick={() => onMove(p.id, -1)}
                        disabled={i === 0}
                        className="flex h-8 w-8 items-center justify-center rounded bg-black/65 text-white disabled:opacity-30 focus-visible:outline-2 focus-visible:outline-ring"
                        aria-label="前移"
                      >
                        <ChevronLeft className="h-3.5 w-3.5" />
                      </button>
                      <button
                        onClick={() => onMove(p.id, 1)}
                        disabled={i === pages.length - 1}
                        className="flex h-8 w-8 items-center justify-center rounded bg-black/65 text-white disabled:opacity-30 focus-visible:outline-2 focus-visible:outline-ring"
                        aria-label="后移"
                      >
                        <ChevronRight className="h-3.5 w-3.5" />
                      </button>
                    </span>
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* 导出 */}
          <div className="safe-bottom flex gap-2 border-t border-border p-4">
            <button
              onClick={onExportImages}
              disabled={exporting}
              className="flex h-12 flex-1 items-center justify-center gap-2 rounded-full bg-secondary text-sm font-medium text-secondary-foreground transition-colors hover:bg-muted disabled:opacity-50 focus-visible:outline-2 focus-visible:outline-ring"
            >
              <Download className="h-4 w-4" />
              导出图片
            </button>
            <button
              onClick={onExportPdf}
              disabled={exporting}
              className="flex h-12 flex-1 items-center justify-center gap-2 rounded-full bg-primary text-sm font-medium text-primary-foreground transition-transform active:scale-[0.97] disabled:opacity-50 focus-visible:outline-2 focus-visible:outline-ring"
            >
              <FileDown className="h-4 w-4" />
              导出 PDF
            </button>
          </div>
        </div>
      </div>

      {/* OCR 结果面板 */}
      {page.ocrStatus === "done" && page.ocrText !== null && (
        <div className="fixed inset-x-0 bottom-0 z-30 mx-auto max-w-2xl rounded-t-2xl border-t border-border bg-popover shadow-[0_-8px_40px_rgba(0,0,0,0.5)]">
          <div className="flex items-center justify-between px-5 pb-2 pt-4">
            <h2 className="text-sm font-semibold">识别结果 · 第 {index + 1} 页</h2>
            <div className="flex items-center gap-1">
              <button
                onClick={copyText}
                className="flex h-9 items-center gap-1.5 rounded-full bg-secondary px-3.5 text-sm text-secondary-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-ring"
              >
                {copied ? (
                  <Check className="h-4 w-4 text-primary" />
                ) : (
                  <Copy className="h-4 w-4" />
                )}
                {copied ? "已复制" : "复制"}
              </button>
              <button
                onClick={() => onClearOcr(page.id)}
                className="flex h-9 w-9 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-secondary focus-visible:outline-2 focus-visible:outline-ring"
                aria-label="关闭识别结果"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          </div>
          <div className="max-h-[42vh] overflow-y-auto px-5 pb-6">
            {page.ocrText ? (
              <p className="whitespace-pre-wrap text-sm leading-relaxed text-foreground/90">
                {page.ocrText}
              </p>
            ) : (
              <p className="text-sm text-muted-foreground">
                未识别到文字，可尝试切换「智能增强」滤镜后重新识别。
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
