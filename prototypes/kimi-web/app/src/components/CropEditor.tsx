import { useCallback, useEffect, useRef, useState } from "react";
import type { Quad } from "@/types/scan";
import { detectDocumentQuad } from "@/lib/scanner/cv";
import { ScanSearch, Check, X } from "lucide-react";

interface Props {
  imageUrl: string;
  width: number;
  height: number;
  initialQuad: Quad;
  canvasRef: React.RefObject<HTMLCanvasElement | null>;
  onConfirm: (quad: Quad) => void;
  onCancel: () => void;
}

const CORNER_LABELS = ["左上", "右上", "右下", "左下"];

export default function CropEditor({
  imageUrl,
  width,
  height,
  initialQuad,
  canvasRef,
  onConfirm,
  onCancel,
}: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [quad, setQuad] = useState<Quad>(initialQuad);
  const [scale, setScale] = useState(1);
  const dragIndex = useRef<number | null>(null);

  // 计算图片在容器中的实际显示缩放
  const measure = useCallback(() => {
    const el = containerRef.current;
    if (!el) return;
    const s = Math.min(el.clientWidth / width, el.clientHeight / height);
    setScale(s);
  }, [width, height]);

  useEffect(() => {
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, [measure]);

  const toImageCoords = useCallback(
    (clientX: number, clientY: number) => {
      const el = containerRef.current;
      if (!el) return { x: 0, y: 0 };
      const rect = el.getBoundingClientRect();
      const offsetX = (rect.width - width * scale) / 2;
      const offsetY = (rect.height - height * scale) / 2;
      return {
        x: Math.min(width, Math.max(0, (clientX - rect.left - offsetX) / scale)),
        y: Math.min(height, Math.max(0, (clientY - rect.top - offsetY) / scale)),
      };
    },
    [width, height, scale]
  );

  const onPointerDown = (i: number) => (e: React.PointerEvent) => {
    e.preventDefault();
    dragIndex.current = i;
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
  };
  const onPointerMove = (e: React.PointerEvent) => {
    if (dragIndex.current === null) return;
    const p = toImageCoords(e.clientX, e.clientY);
    setQuad((q) => {
      const next = [...q] as Quad;
      next[dragIndex.current!] = p;
      return next;
    });
  };
  const onPointerUp = () => {
    dragIndex.current = null;
  };

  const redetect = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const found = detectDocumentQuad(canvas);
    if (found) setQuad(found);
  };

  const dispW = width * scale;
  const dispH = height * scale;
  const pts = quad.map((p) => `${p.x * scale},${p.y * scale}`).join(" ");

  return (
    <div className="flex h-full flex-col">
      {/* 顶栏 */}
      <div className="safe-top flex items-center justify-between px-4 py-3">
        <button
          onClick={onCancel}
          className="flex h-11 w-11 items-center justify-center rounded-full bg-secondary text-secondary-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-ring"
          aria-label="取消"
        >
          <X className="h-5 w-5" />
        </button>
        <span className="text-sm text-muted-foreground">拖动角点调整选区</span>
        <button
          onClick={redetect}
          className="flex h-11 items-center gap-1.5 rounded-full bg-secondary px-4 text-sm text-secondary-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-ring"
        >
          <ScanSearch className="h-4 w-4" />
          重新检测
        </button>
      </div>

      {/* 图片 + 四边形 */}
      <div
        ref={containerRef}
        className="relative flex flex-1 touch-none items-center justify-center overflow-hidden px-2"
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
      >
        <div className="relative" style={{ width: dispW, height: dispH }}>
          <img
            src={imageUrl}
            alt="待裁剪文档"
            className="block h-full w-full select-none"
            draggable={false}
          />
          <svg
            className="pointer-events-none absolute inset-0 h-full w-full"
            viewBox={`0 0 ${dispW} ${dispH}`}
          >
            <polygon
              points={pts}
              fill="hsl(9 76% 48% / 0.12)"
              stroke="hsl(9 76% 48%)"
              strokeWidth={2}
              strokeLinejoin="round"
            />
          </svg>
          {quad.map((p, i) => (
            <button
              key={i}
              aria-label={`拖动${CORNER_LABELS[i]}角点`}
              onPointerDown={onPointerDown(i)}
              className="corner-handle absolute z-10 flex h-11 w-11 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full focus-visible:outline-2 focus-visible:outline-ring"
              style={{ left: p.x * scale, top: p.y * scale }}
            >
              <span className="block h-5 w-5 rounded-full border-[3px] border-primary bg-white shadow-[0_1px_6px_rgba(0,0,0,0.5)]" />
            </button>
          ))}
        </div>
      </div>

      {/* 底部确认 */}
      <div className="safe-bottom flex justify-center px-4 pb-5 pt-3">
        <button
          onClick={() => onConfirm(quad)}
          className="flex h-12 min-w-44 items-center justify-center gap-2 rounded-full bg-primary px-8 text-base font-medium text-primary-foreground transition-transform active:scale-95 focus-visible:outline-2 focus-visible:outline-ring"
        >
          <Check className="h-5 w-5" />
          确认裁剪
        </button>
      </div>
    </div>
  );
}
