import { useEffect, useRef, useState } from "react";
import { X, ImagePlus, Check } from "lucide-react";

interface Props {
  pageCount: number;
  onCapture: (canvas: HTMLCanvasElement) => void;
  onUpload: (files: FileList) => void;
  onDone: () => void;
  onClose: () => void;
}

export default function CameraScreen({
  pageCount,
  onCapture,
  onUpload,
  onDone,
  onClose,
}: Props) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    navigator.mediaDevices
      ?.getUserMedia({
        video: { facingMode: "environment", width: { ideal: 1920 } },
        audio: false,
      })
      .then((stream) => {
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }
        streamRef.current = stream;
        if (videoRef.current) videoRef.current.srcObject = stream;
      })
      .catch(() => {
        if (!cancelled) setError("无法访问相机");
      });
    return () => {
      cancelled = true;
      streamRef.current?.getTracks().forEach((t) => t.stop());
    };
  }, []);

  const capture = () => {
    const video = videoRef.current;
    if (!video || !video.videoWidth) return;
    const canvas = document.createElement("canvas");
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    canvas.getContext("2d")!.drawImage(video, 0, 0);
    onCapture(canvas);
  };

  return (
    <div className="relative flex h-full flex-col bg-black">
      {/* 取景画面 */}
      <div className="relative flex-1 overflow-hidden">
        {error ? (
          <div className="flex h-full flex-col items-center justify-center gap-4 px-8 text-center">
            <p className="text-sm leading-relaxed text-muted-foreground">
              {error}，请检查浏览器相机权限，
              <br />
              或直接从相册导入图片
            </p>
            <label className="flex h-12 cursor-pointer items-center gap-2 rounded-full bg-primary px-6 font-medium text-primary-foreground transition-transform active:scale-95">
              <ImagePlus className="h-5 w-5" />
              从相册导入
              <input
                type="file"
                accept="image/*"
                multiple
                className="sr-only"
                onChange={(e) => {
                  if (e.target.files?.length) onUpload(e.target.files);
                  e.target.value = "";
                }}
              />
            </label>
          </div>
        ) : (
          <>
            <video
              ref={videoRef}
              autoPlay
              playsInline
              muted
              className="h-full w-full object-cover"
            />
            {/* 取景角标 */}
            <span className="viewfinder-corner left-6 top-6 rounded-tl-xl border-l-4 border-t-4" />
            <span className="viewfinder-corner right-6 top-6 rounded-tr-xl border-r-4 border-t-4" />
            <span className="viewfinder-corner bottom-6 left-6 rounded-bl-xl border-b-4 border-l-4" />
            <span className="viewfinder-corner bottom-6 right-6 rounded-br-xl border-b-4 border-r-4" />
            <p className="absolute inset-x-0 top-1/4 text-center text-sm text-white/70">
              将文档置于框内，保持平稳
            </p>
          </>
        )}
      </div>

      {/* 顶栏 */}
      <div className="safe-top absolute inset-x-0 top-0 flex items-center justify-between bg-gradient-to-b from-black/60 to-transparent px-4 pb-8 pt-3">
        <button
          onClick={onClose}
          className="flex h-11 w-11 items-center justify-center rounded-full bg-black/50 text-white transition-colors hover:bg-black/70 focus-visible:outline-2 focus-visible:outline-ring"
          aria-label="关闭相机"
        >
          <X className="h-5 w-5" />
        </button>
        <span className="rounded-full bg-black/50 px-3.5 py-1.5 text-sm text-white/90 tabular">
          已扫 {pageCount} 页
        </span>
      </div>

      {/* 底部操作 */}
      <div className="safe-bottom relative flex items-center justify-between bg-gradient-to-t from-black/70 to-transparent px-8 pb-7 pt-10">
        <label
          className="flex h-12 w-12 cursor-pointer items-center justify-center rounded-xl border border-white/25 bg-black/40 text-white transition-colors hover:bg-black/60 focus-within:outline-2 focus-within:outline-ring"
          aria-label="从相册导入"
        >
          <ImagePlus className="h-5 w-5" />
          <input
            type="file"
            accept="image/*"
            multiple
            className="sr-only"
            onChange={(e) => {
              if (e.target.files?.length) onUpload(e.target.files);
              e.target.value = "";
            }}
          />
        </label>

        <button
          onClick={capture}
          disabled={!!error}
          className="flex h-[72px] w-[72px] items-center justify-center rounded-full border-4 border-white bg-white/15 transition-transform active:scale-90 disabled:opacity-40 focus-visible:outline-2 focus-visible:outline-ring"
          aria-label="拍照"
        >
          <span className="h-14 w-14 rounded-full bg-white" />
        </button>

        <button
          onClick={onDone}
          disabled={pageCount === 0}
          className="flex h-12 min-w-12 items-center justify-center gap-1 rounded-full bg-primary px-4 text-sm font-medium text-primary-foreground transition-transform active:scale-95 disabled:opacity-40 focus-visible:outline-2 focus-visible:outline-ring"
        >
          <Check className="h-4 w-4" />
          完成
        </button>
      </div>
    </div>
  );
}
