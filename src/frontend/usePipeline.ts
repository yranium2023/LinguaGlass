import { useEffect, useState } from "react";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  initialState,
  reduceEvent,
  type PipelineEvent,
  type SessionState,
  type ViewState,
} from "./protocol";

export const desktop = isTauri();
export function usePipeline() {
  const [view, setView] = useState<ViewState>(initialState);
  useEffect(() => {
    if (!desktop) return;
    let disposed = false;
    let unlisten: (() => void) | undefined;
    let loading = true;
    let lastLevelAt = 0;
    const levelTimer = window.setInterval(() => {
      if (!disposed && !loading && performance.now() - lastLevelAt > 400)
        setView((s) => (s.level === 0 ? s : { ...s, level: 0 }));
    }, 250);
    const pending: PipelineEvent[] = [];
    void (async () => {
      unlisten = await listen<PipelineEvent>("pipeline", ({ payload }) => {
        if (disposed) return;
        if (payload.type === "level") lastLevelAt = performance.now();
        if (loading) pending.push(payload);
        else setView((s) => reduceEvent(s, payload));
      });
      if (disposed) {
        unlisten();
        return;
      }
      const snapshot = await invoke<{
        seq: number;
        session_id: string;
        state: SessionState;
        events: PipelineEvent[];
      }>("snapshot");
      if (disposed) return;
      let next = { ...initialState, sessionId: snapshot.session_id };
      for (const event of [...snapshot.events].sort(
        (a, b) => (a.seq ?? 0) - (b.seq ?? 0),
      ))
        next = reduceEvent(next, event);
      next = reduceEvent(next, {
        type: "status",
        state: snapshot.state,
        session_id: snapshot.session_id,
        seq: snapshot.seq + 0.1,
      });
      next.seq = snapshot.seq;
      for (const event of pending) next = reduceEvent(next, event);
      loading = false;
      setView(next);
    })().catch(() => {
      if (!disposed)
        setView((s) => ({ ...s, message: "无法连接桌面服务，请重启应用。" }));
    });
    return () => {
      disposed = true;
      window.clearInterval(levelTimer);
      unlisten?.();
    };
  }, []);
  return view;
}
