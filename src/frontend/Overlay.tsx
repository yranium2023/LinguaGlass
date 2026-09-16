import { getCurrentWindow } from "@tauri-apps/api/window";
import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { emitTo } from "@tauri-apps/api/event";
import { loadPreferences } from "./preferences";
import { desktop, usePipeline } from "./usePipeline";
import { subtitlePages, type TranscriptGroup } from "./transcript";
import { GripHorizontal } from "lucide-react";
import { WindowControls } from "./WindowControls";

function Card({
  group,
  previous = false,
  solo = false,
}: {
  group: TranscriptGroup;
  previous?: boolean;
  solo?: boolean;
}) {
  const partial = group.rows.some((row) => row.status === "partial");
  return (
    <section
      className={`subtitle-card ${previous ? "previous" : "current"} ${solo ? "solo" : ""}`}
      data-card-id={group.id}
      aria-live={previous ? "off" : "polite"}
    >
      <p className={`english ${partial ? "partial" : ""}`}>{group.en}</p>
      <p className="chinese">
        {group.zh || group.error || (partial ? "正在识别英文…" : "正在翻译…")}
      </p>
    </section>
  );
}

export function Overlay() {
  const view = usePipeline();
  const [collapsed, setCollapsed] = useState(false);
  const [error, setError] = useState("");
  const [pauseSeconds, setPauseSeconds] = useState(
    () => loadPreferences().config.subtitle_pause_seconds,
  );
  useEffect(() => {
    const sync = () => {
      const preferences = loadPreferences();
      document.documentElement.dataset.theme = preferences.appearance.theme;
      document.documentElement.dataset.size = preferences.appearance.size;
      document.documentElement.dataset.accent = preferences.appearance.accent;
      setPauseSeconds(preferences.config.subtitle_pause_seconds);
    };
    sync();
    window.addEventListener("storage", sync);
    return () => window.removeEventListener("storage", sync);
  }, []);
  async function toggle() {
    const compact = !collapsed;
    try {
      if (compact) setCollapsed(true);
      if (desktop) await invoke("compact_overlay", { compact });
      if (!compact) setCollapsed(false);
      setError("");
    } catch {
      setCollapsed(!compact);
      setError("字幕窗口大小调整失败");
    }
  }
  async function closeOverlay() {
    try {
      await getCurrentWindow().hide();
      void emitTo("main", "overlay-visibility", { visible: false }).catch(
        () => {},
      );
      setError("");
    } catch {
      setError("字幕窗口关闭失败");
    }
  }
  const cards = subtitlePages(view.rows, pauseSeconds);
  const current = cards.at(-1);
  const previous = cards.at(-2);
  return (
    <div
      className={`overlay-shell ${collapsed ? "collapsed" : ""}`}
      data-surface="overlay"
    >
      <header
        data-tauri-drag-region
        onPointerDown={(e) => {
          if (desktop && e.target === e.currentTarget)
            void getCurrentWindow().startDragging();
        }}
      >
        <span className="live-dot" />
        <span className="overlay-title">EN → 中</span>
        <GripHorizontal size={16} aria-hidden="true" />
        <WindowControls
          onClose={closeOverlay}
          onMinimize={() => void toggle()}
          collapsed={collapsed}
        />
      </header>
      {!collapsed && (
        <div className="overlay-text">
          {previous && <Card group={previous} previous />}
          {current ? (
            <Card group={current} solo={!previous} />
          ) : (
            <section className="subtitle-card current placeholder">
              <p className="english">Listening starts in the main window.</p>
              <p className="chinese">
                在主窗口开始聆听，双语字幕会显示在这里。
              </p>
            </section>
          )}
          {error && <p role="status">{error}</p>}
        </div>
      )}
    </div>
  );
}
