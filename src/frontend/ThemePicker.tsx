import { Check, Palette } from "lucide-react";
import { useEffect, useRef, useState, type CSSProperties } from "react";
import type { Accent } from "./preferences";

export const accents: { value: Accent; label: string; color: string }[] = [
  { value: "blue", label: "海蓝", color: "#0a84ff" },
  { value: "indigo", label: "靛青", color: "#5e5ce6" },
  { value: "violet", label: "紫罗兰", color: "#af52de" },
  { value: "rose", label: "玫瑰", color: "#ff375f" },
  { value: "orange", label: "暖橙", color: "#ff9f0a" },
  { value: "mint", label: "薄荷", color: "#30b0c7" },
];

export function ThemePicker({
  value,
  onChange,
}: {
  value: Accent;
  onChange: (value: Accent) => void;
}) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const close = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [open]);
  return (
    <div className="theme-picker" data-open={open} ref={root}>
      <button
        type="button"
        className="icon-button theme-picker-trigger"
        aria-label="选择主题色"
        aria-expanded={open}
        onClick={() => setOpen((current) => !current)}
      >
        <Palette size={18} />
        <span
          className="theme-color-dot"
          style={{
            background: accents.find((item) => item.value === value)?.color,
          }}
        />
      </button>
      <div className="theme-picker-menu" aria-hidden={!open}>
        <p>主题色</p>
        <div>
          {accents.map((accent) => (
            <button
              type="button"
              key={accent.value}
              title={accent.label}
              aria-label={`主题色：${accent.label}`}
              aria-pressed={value === accent.value}
              style={{ "--swatch": accent.color } as CSSProperties}
              onClick={() => {
                onChange(accent.value);
                setOpen(false);
              }}
            >
              {value === accent.value && <Check size={14} />}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
