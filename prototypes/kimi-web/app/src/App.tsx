import { useCallback, useEffect, useRef, useState } from "react";
import { Toaster, toast } from "sonner";
import type { Quad, ScanPage, FilterId } from "@/types/scan";
import { uid } from "@/types/scan";
import {
  loadOpenCV,
  detectDocumentQuad,
  defaultQuad,
  warpPerspective,
} from "@/lib/scanner/cv";
import { applyFilter } from "@/lib/scanner/filters";
import { recognizeText } from "@/lib/scanner/ocr";
import { exportAllImages, exportPdf } from "@/lib/scanner/exporter";
import HomeScreen from "@/sections/HomeScreen";
import CameraScreen from "@/sections/CameraScreen";
import CropEditor from "@/components/CropEditor";
import Workspace from "@/sections/Workspace";

type Stage = "home" | "camera" | "crop" | "workspace";

interface PendingCrop {
  dataUrl: string;
  width: number;
  height: number;
  quad: Quad;
  canvas: HTMLCanvasElement;
  origin: "camera" | "upload";
}

/** 图片文件 → canvas（处理 EXIF 方向） */
async function fileToCanvas(file: File): Promise<HTMLCanvasElement> {
  try {
    const bmp = await createImageBitmap(file, { imageOrientation: "from-image" });
    const c = document.createElement("canvas");
    c.width = bmp.width;
    c.height = bmp.height;
    c.getContext("2d")!.drawImage(bmp, 0, 0);
    bmp.close();
    return c;
  } catch {
    const url = URL.createObjectURL(file);
    try {
      const img = await new Promise<HTMLImageElement>((res, rej) => {
        const i = new Image();
        i.onload = () => res(i);
        i.onerror = rej;
        i.src = url;
      });
      const c = document.createElement("canvas");
      c.width = img.naturalWidth;
      c.height = img.naturalHeight;
      c.getContext("2d")!.drawImage(img, 0, 0);
      return c;
    } finally {
      URL.revokeObjectURL(url);
    }
  }
}

export default function App() {
  const [stage, setStage] = useState<Stage>("home");
  const [pages, setPages] = useState<ScanPage[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [pending, setPending] = useState<PendingCrop | null>(null);
  const [ocrProgress, setOcrProgress] = useState<number | null>(null);
  const [exporting, setExporting] = useState(false);
  const uploadQueue = useRef<HTMLCanvasElement[]>([]);
  const pendingCanvasRef = useRef<HTMLCanvasElement | null>(null);

  // 启动即预载 OpenCV 引擎，保证首次拍照时检测可用
  useEffect(() => {
    loadOpenCV().catch(() => toast.error("识别引擎加载失败，仍可手动框选"));
  }, []);

  const prepareCrop = useCallback(
    async (canvas: HTMLCanvasElement, origin: "camera" | "upload") => {
      try {
        await loadOpenCV();
      } catch {
        /* 引擎失败时用默认框 */
      }
      const quad =
        detectDocumentQuad(canvas) ?? defaultQuad(canvas.width, canvas.height);
      pendingCanvasRef.current = canvas;
      setPending({
        dataUrl: canvas.toDataURL("image/jpeg", 0.9),
        width: canvas.width,
        height: canvas.height,
        quad,
        canvas,
        origin,
      });
      setStage("crop");
    },
    []
  );

  const handleUploadFiles = useCallback(
    async (files: FileList, origin: "camera" | "upload" = "upload") => {
      const list = Array.from(files).filter((f) => f.type.startsWith("image/"));
      if (!list.length) return;
      toast.loading("正在读取图片…", { id: "load-img" });
      try {
        const canvases = await Promise.all(list.map(fileToCanvas));
        uploadQueue.current = canvases.slice(1);
        toast.dismiss("load-img");
        await prepareCrop(canvases[0], origin);
      } catch {
        toast.dismiss("load-img");
        toast.error("图片读取失败，请换一张试试");
      }
    },
    [prepareCrop]
  );

  const confirmCrop = useCallback(
    (quad: Quad) => {
      if (!pending) return;
      const rectified = warpPerspective(pending.canvas, quad);
      const dataUrl = rectified.toDataURL("image/jpeg", 0.92);
      const page: ScanPage = {
        id: uid(),
        rectified: dataUrl,
        width: rectified.width,
        height: rectified.height,
        filter: "original",
        display: dataUrl,
        ocrText: null,
        ocrStatus: "idle",
      };
      setPages((ps) => [...ps, page]);
      setSelectedId(page.id);
      setPending(null);
      pendingCanvasRef.current = null;

      // 队列里还有导入的图片 → 继续裁下一张
      if (uploadQueue.current.length) {
        const next = uploadQueue.current.shift()!;
        prepareCrop(next, "upload");
        return;
      }
      // 相机流程：回到取景器继续连拍；导入流程：进入工作台
      setStage(pending.origin === "camera" ? "camera" : "workspace");
    },
    [pending, prepareCrop]
  );

  const handleFilter = useCallback(async (id: string, filter: FilterId) => {
    setPages((ps) => ps.map((p) => (p.id === id ? { ...p, filter } : p)));
    const page = pages.find((p) => p.id === id);
    if (!page) return;
    const display = await applyFilter(page.rectified, page.width, page.height, filter);
    setPages((ps) =>
      ps.map((p) =>
        p.id === id
          ? { ...p, display, ocrText: null, ocrStatus: "idle" as const }
          : p
      )
    );
  }, [pages]);

  const handleRotate = useCallback(
    async (id: string) => {
      const page = pages.find((p) => p.id === id);
      if (!page) return;
      const img = await new Promise<HTMLImageElement>((res, rej) => {
        const i = new Image();
        i.onload = () => res(i);
        i.onerror = rej;
        i.src = page.rectified;
      });
      const c = document.createElement("canvas");
      c.width = img.height;
      c.height = img.width;
      const ctx = c.getContext("2d")!;
      ctx.translate(c.width / 2, c.height / 2);
      ctx.rotate(Math.PI / 2);
      ctx.drawImage(img, -img.width / 2, -img.height / 2);
      const rectified = c.toDataURL("image/jpeg", 0.92);
      const display = await applyFilter(rectified, c.width, c.height, page.filter);
      setPages((ps) =>
        ps.map((p) =>
          p.id === id
            ? {
                ...p,
                rectified,
                display,
                width: c.width,
                height: c.height,
                ocrText: null,
                ocrStatus: "idle" as const,
              }
            : p
        )
      );
    },
    [pages]
  );

  const handleDelete = useCallback(
    (id: string) => {
      setPages((ps) => {
        const next = ps.filter((p) => p.id !== id);
        if (!next.length) {
          setStage("home");
          setSelectedId(null);
        } else if (selectedId === id) {
          setSelectedId(next[0].id);
        }
        return next;
      });
    },
    [selectedId]
  );

  const handleMove = useCallback((id: string, dir: -1 | 1) => {
    setPages((ps) => {
      const i = ps.findIndex((p) => p.id === id);
      const j = i + dir;
      if (i < 0 || j < 0 || j >= ps.length) return ps;
      const next = [...ps];
      [next[i], next[j]] = [next[j], next[i]];
      return next;
    });
  }, []);

  const handleOcr = useCallback(async (id: string) => {
    setPages((ps) =>
      ps.map((p) => (p.id === id ? { ...p, ocrStatus: "running" as const } : p))
    );
    setOcrProgress(0);
    try {
      const current = await new Promise<ScanPage | undefined>((res) => {
        setPages((ps) => {
          res(ps.find((p) => p.id === id));
          return ps;
        });
      });
      if (!current) throw new Error("页面不存在");
      const text = await recognizeText(current.display, setOcrProgress);
      setPages((ps) =>
        ps.map((p) =>
          p.id === id ? { ...p, ocrText: text, ocrStatus: "done" as const } : p
        )
      );
    } catch {
      setPages((ps) =>
        ps.map((p) => (p.id === id ? { ...p, ocrStatus: "idle" as const } : p))
      );
      toast.error("文字识别失败，请检查网络后重试（首次需加载语言包）");
    } finally {
      setOcrProgress(null);
    }
  }, []);

  const handleClearOcr = useCallback((id: string) => {
    setPages((ps) =>
      ps.map((p) =>
        p.id === id ? { ...p, ocrText: null, ocrStatus: "idle" as const } : p
      )
    );
  }, []);

  const handleExportImages = useCallback(() => {
    if (!pages.length) return;
    exportAllImages(pages);
    toast.success(`已导出 ${pages.length} 张图片`);
  }, [pages]);

  const handleExportPdf = useCallback(async () => {
    if (!pages.length || exporting) return;
    setExporting(true);
    try {
      await exportPdf(pages);
      toast.success("PDF 已导出");
    } catch {
      toast.error("PDF 生成失败");
    } finally {
      setExporting(false);
    }
  }, [pages, exporting]);

  return (
    <div className="h-dvh w-full overflow-hidden bg-background text-foreground">
      {stage === "home" && (
        <HomeScreen
          onCamera={() => setStage("camera")}
          onUpload={(f) => handleUploadFiles(f)}
        />
      )}

      {stage === "camera" && (
        <CameraScreen
          pageCount={pages.length}
          onCapture={(canvas) => prepareCrop(canvas, "camera")}
          onUpload={(f) => handleUploadFiles(f, "camera")}
          onDone={() => setStage("workspace")}
          onClose={() => setStage(pages.length ? "workspace" : "home")}
        />
      )}

      {stage === "crop" && pending && (
        <CropEditor
          imageUrl={pending.dataUrl}
          width={pending.width}
          height={pending.height}
          initialQuad={pending.quad}
          canvasRef={pendingCanvasRef}
          onConfirm={confirmCrop}
          onCancel={() => {
            setPending(null);
            pendingCanvasRef.current = null;
            uploadQueue.current = [];
            setStage(pending.origin === "camera" ? "camera" : pages.length ? "workspace" : "home");
          }}
        />
      )}

      {stage === "workspace" && pages.length > 0 && (
        <Workspace
          pages={pages}
          selectedId={selectedId}
          ocrProgress={ocrProgress}
          exporting={exporting}
          onSelect={setSelectedId}
          onFilter={handleFilter}
          onRotate={handleRotate}
          onDelete={handleDelete}
          onMove={handleMove}
          onOcr={handleOcr}
          onClearOcr={handleClearOcr}
          onAddCamera={() => setStage("camera")}
          onAddUpload={(f) => handleUploadFiles(f)}
          onExportImages={handleExportImages}
          onExportPdf={handleExportPdf}
          onHome={() => setStage("home")}
        />
      )}

      <Toaster
        theme="dark"
        position="top-center"
        toastOptions={{
          style: {
            background: "hsl(28 7% 10%)",
            border: "1px solid hsl(30 6% 18%)",
            color: "hsl(40 30% 97%)",
          },
        }}
      />
    </div>
  );
}
