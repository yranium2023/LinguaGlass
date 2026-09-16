export type SessionState = "IDLE" | "INITIALIZING" | "LISTENING" | "STOPPING";
export interface PipelineEvent {
  type: string;
  seq?: number;
  session_id?: string;
  id?: string;
  group_id?: string;
  text?: string;
  message?: string;
  state?: SessionState;
  start?: number;
  end?: number;
  value?: number;
  queue_ms?: number;
  first_token_ms?: number;
  total_ms?: number;
  provisional?: boolean;
}
export interface Segment {
  id: string;
  groupId: string;
  start: number;
  end: number;
  en: string;
  zh: string;
  finalized?: boolean;
  status:
    "partial" | "final" | "queued" | "translating" | "translated" | "error";
  error?: string;
}
export interface ViewState {
  seq: number;
  sessionId: string;
  state: SessionState;
  rows: Segment[];
  message: string;
  level: number;
}
export const initialState: ViewState = {
  seq: 0,
  sessionId: "",
  state: "IDLE",
  rows: [],
  message: "",
  level: 0,
};
export function reduceEvent(
  previous: ViewState,
  event: PipelineEvent,
): ViewState {
  if (event.seq !== undefined && event.seq <= previous.seq) return previous;
  const changed = event.session_id && event.session_id !== previous.sessionId;
  const state: ViewState = {
    ...(changed ? initialState : previous),
    seq: event.seq ?? previous.seq,
    sessionId: event.session_id ?? previous.sessionId,
  };
  if (event.type === "status")
    return {
      ...state,
      state: event.state ?? "IDLE",
      level: event.state === "IDLE" ? 0 : state.level,
      rows:
        event.state === "IDLE"
          ? state.rows
              .filter((r) => r.status !== "partial")
              .map((r) =>
                ["queued", "translating", "final"].includes(r.status)
                  ? {
                      ...r,
                      status: "error" as const,
                      error: "会话已结束，翻译未完成",
                    }
                  : r,
              )
          : state.rows,
      message: event.state === "INITIALIZING" ? "" : state.message,
    };
  if (event.type === "level") return { ...state, level: event.value ?? 0 };
  if (event.type === "warning" || event.type === "error")
    return { ...state, message: event.message ?? "" };
  if (!event.id) return state;
  const rows = [...state.rows];
  const index = rows.findIndex((row) => row.id === event.id);
  if (event.type === "asr_clear")
    return {
      ...state,
      rows: rows.filter((r) => r.id !== event.id || r.status !== "partial"),
    };
  if (event.type === "asr_partial" || event.type === "asr_final") {
    const existing = index >= 0 ? rows[index] : undefined;
    if (event.type === "asr_partial" && existing?.finalized) return state;
    const row: Segment = {
      id: event.id,
      groupId: event.group_id ?? event.id,
      start: event.start ?? 0,
      end: event.end ?? 0,
      en: event.text ?? "",
      zh: existing?.zh ?? "",
      finalized: event.type === "asr_final",
      status:
        event.type === "asr_partial"
          ? existing?.status === "error"
            ? "partial"
            : (existing?.status ?? "partial")
          : "final",
    };
    if (index >= 0) rows[index] = row;
    else rows.push(row);
  } else if (index >= 0) {
    const row = { ...rows[index] };
    if (event.type === "translation_queued") row.status = "queued";
    if (
      event.type === "translation_started" ||
      event.type === "translation_delta"
    )
      row.status = "translating";
    if (event.type === "translation_delta") row.zh = event.text ?? "";
    if (event.type === "translation_done") {
      row.status = "translated";
      row.zh = event.text ?? "";
    }
    if (event.type === "translation_error") {
      row.status = "error";
      row.error = event.message;
    }
    rows[index] = row;
  }
  return { ...state, rows: rows.slice(-300) };
}
export function timecode(seconds: number) {
  return new Date(Math.max(0, seconds) * 1000).toISOString().slice(11, 19);
}
