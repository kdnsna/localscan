export default function ScanBeam({ label }: { label?: string }) {
  return (
    <div className="absolute inset-0 z-20 overflow-hidden rounded-[inherit] bg-black/45 backdrop-blur-[1px]">
      <div className="scanbeam" />
      {label && (
        <div className="absolute inset-x-0 bottom-6 flex justify-center">
          <span className="rounded-full bg-black/70 px-4 py-1.5 text-sm text-white/90 tabular">
            {label}
          </span>
        </div>
      )}
    </div>
  );
}
