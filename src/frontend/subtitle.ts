import type { Segment } from "./protocol";
import { groupTranscript } from "./transcript";

export type ReadingState = {
  session: string;
  row?: Segment;
  until: number;
  seen: string[];
};
export const emptyReading: ReadingState = { session: "", until: 0, seen: [] };
export function subtitlePresentation(rows: Segment[], held?: Segment) {
  const groups = groupTranscript(rows);
  const live = groups.at(-1);
  const heldGroup = held
    ? groups.find((group) => group.rows.some((row) => row.id === held.id))
    : undefined;
  const shown = held?.zh ? (heldGroup ?? live) : live;
  const latest = shown?.rows.at(-1);
  return {
    english: shown?.en ?? "",
    chinese: shown?.zh ?? "",
    partial: latest?.status === "partial",
    pending: shown?.pending ?? false,
    error: shown?.error,
  };
}
// A completed translation gets a full reading interval, even if ASR is ahead.
export function advanceReading(
  previous: ReadingState,
  session: string,
  rows: Segment[],
  now: number,
  seconds: number,
): ReadingState {
  let state =
    previous.session === session ? previous : { ...emptyReading, session };
  const current = rows.find((r) => r.id === state.row?.id) ?? state.row;
  const ready = rows.filter(
    (r) => r.status === "translated" && r.zh && !state.seen.includes(r.id),
  );
  if (ready.length && now >= state.until) {
    const row = ready[0];
    return {
      session,
      row,
      until:
        now + Math.max(seconds * 1000, Math.min(20000, row.zh.length * 180)),
      seen: [...state.seen, row.id].slice(-600),
    };
  }
  if (state.seen.length) return { ...state, row: current };
  return { ...state, row: rows.at(-1) };
}
