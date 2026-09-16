import { getCurrentWindow } from "@tauri-apps/api/window";
import { Maximize2, Minus, X } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { desktop } from "./usePipeline";

export function WindowControls({
  onClose,
  onMinimize,
  collapsed = false,
}: {
  onClose?: () => void;
  onMinimize?: () => void;
  collapsed?: boolean;
}) {
  const [maximized, setMaximized] = useState(false);
  const win = useMemo(() => (desktop ? getCurrentWindow() : null), []);

  useEffect(() => {
    if (!win) return;
    let cancelled = false;
    const sync = () => {
      void win
        .isMaximized()
        .then((value) => {
          if (!cancelled) setMaximized(value);
        })
        .catch(() => {});
    };
    sync();
    const timer = window.setInterval(sync, 1200);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [win]);

  async function minimize() {
    if (onMinimize) return onMinimize();
    if (win) await win.minimize();
  }
  async function maximize() {
    if (win) await win.toggleMaximize();
    setMaximized((value) => !value);
  }
  async function close() {
    if (onClose) return onClose();
    if (win) await win.close();
  }

  return (
    <div className="window-controls" aria-label="窗口控制">
      <button
        className="minimize"
        type="button"
        title={onMinimize ? (collapsed ? "展开字幕" : "收起字幕") : "最小化"}
        aria-label={
          onMinimize ? (collapsed ? "展开字幕" : "收起字幕") : "最小化"
        }
        onClick={() => void minimize()}
      >
        {onMinimize && collapsed ? (
          <Maximize2 size={14} />
        ) : (
          <Minus size={16} />
        )}
      </button>
      <button
        className="maximize"
        type="button"
        title={maximized ? "还原" : "最大化"}
        aria-label={maximized ? "还原" : "最大化"}
        onClick={() => void maximize()}
      >
        <Maximize2 size={14} />
      </button>
      <button
        type="button"
        className="close"
        title="关闭"
        aria-label="关闭"
        onClick={() => void close()}
      >
        <X size={16} />
      </button>
    </div>
  );
}
