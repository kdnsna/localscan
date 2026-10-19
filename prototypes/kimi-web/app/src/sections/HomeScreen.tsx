import { Camera, ImagePlus, Zap, ScanLine, FileText, ShieldCheck } from "lucide-react";

interface Props {
  onCamera: () => void;
  onUpload: (files: FileList) => void;
}

export default function HomeScreen({ onCamera, onUpload }: Props) {
  return (
    <div className="flex h-full flex-col">
      {/* 顶栏 */}
      <header className="safe-top flex items-center justify-between px-5 py-4">
        <div className="flex items-baseline gap-2">
          <span className="text-xl font-semibold tracking-tight">快扫</span>
          <span className="text-xs text-muted-foreground">AI 扫描仪</span>
        </div>
        <span className="flex items-center gap-1.5 rounded-full border border-border px-3 py-1 text-xs text-muted-foreground">
          <ShieldCheck className="h-3.5 w-3.5 text-primary" />
          本地处理 · 零上传
        </span>
      </header>

      {/* 主视觉 */}
      <main className="flex flex-1 flex-col justify-center px-6 pb-8">
        <div className="relative mx-auto mb-10 w-full max-w-sm">
          {/* 文档示意 + 扫描光束 */}
          <div className="relative mx-auto aspect-[3/4] w-56 overflow-hidden rounded-2xl border border-border bg-card">
            <div className="absolute inset-5 flex flex-col gap-2.5 pt-2">
              <div className="h-2.5 w-3/5 rounded-full bg-foreground/25" />
              <div className="h-1.5 w-full rounded-full bg-foreground/10" />
              <div className="h-1.5 w-full rounded-full bg-foreground/10" />
              <div className="h-1.5 w-4/5 rounded-full bg-foreground/10" />
              <div className="mt-2 h-1.5 w-full rounded-full bg-foreground/10" />
              <div className="h-1.5 w-3/5 rounded-full bg-foreground/10" />
              <div className="mt-3 h-2 w-2/5 rounded-full bg-primary/70" />
              <div className="h-1.5 w-full rounded-full bg-foreground/10" />
              <div className="h-1.5 w-5/6 rounded-full bg-foreground/10" />
            </div>
            <div className="scanbeam" />
            {/* 取景角标 */}
            <span className="viewfinder-corner left-2 top-2 rounded-tl-lg border-l-[3px] border-t-[3px]" />
            <span className="viewfinder-corner right-2 top-2 rounded-tr-lg border-r-[3px] border-t-[3px]" />
            <span className="viewfinder-corner bottom-2 left-2 rounded-bl-lg border-b-[3px] border-l-[3px]" />
            <span className="viewfinder-corner bottom-2 right-2 rounded-br-lg border-b-[3px] border-r-[3px]" />
          </div>
        </div>

        <h1 className="text-center text-3xl font-semibold leading-tight tracking-tight">
          对准文档，
          <br />
          剩下的交给 AI
        </h1>
        <p className="mx-auto mt-3 max-w-xs text-center text-sm leading-relaxed text-muted-foreground">
          自动找边、透视矫正、画质增强、文字识别——全部在本地完成，导出图片与 PDF。
        </p>

        {/* 主操作 */}
        <div className="mx-auto mt-9 flex w-full max-w-sm flex-col gap-3">
          <button
            onClick={onCamera}
            className="flex h-14 items-center justify-center gap-2.5 rounded-full bg-primary text-lg font-medium text-primary-foreground transition-transform active:scale-[0.97] focus-visible:outline-2 focus-visible:outline-ring"
          >
            <Camera className="h-5 w-5" />
            拍照扫描
          </button>
          <label className="flex h-14 cursor-pointer items-center justify-center gap-2.5 rounded-full border border-border bg-secondary text-lg font-medium text-secondary-foreground transition-colors hover:bg-muted focus-within:outline-2 focus-within:outline-ring">
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

        {/* 能力点 */}
        <div className="mx-auto mt-10 grid w-full max-w-sm grid-cols-3 gap-2 text-center">
          {[
            { icon: ScanLine, t: "智能裁边" },
            { icon: Zap, t: "画质增强" },
            { icon: FileText, t: "文字识别" },
          ].map(({ icon: Icon, t }) => (
            <div key={t} className="flex flex-col items-center gap-1.5 py-2">
              <Icon className="h-5 w-5 text-primary" />
              <span className="text-xs text-muted-foreground">{t}</span>
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}
