import type { Segment } from "./protocol";

export type TranscriptGroup = {
  id: string;
  start: number;
  end: number;
  rows: Segment[];
  en: string;
  zh: string;
  pending: boolean;
  error?: string;
};

export const TRANSCRIPT_CARD_LIMITS = {
  targetDurationSeconds: 9,
  targetEnglishCharacters: 180,
  maxDurationSeconds: 30,
  maxEnglishCharacters: 520,
  maxRows: 8,
  naturalPauseSeconds: 1.6,
} as const;

function joinedEnglish(rows: Segment[]) {
  return rows
    .map((item) => item.en.trim())
    .filter(Boolean)
    .join(" ");
}

function canAppend(group: TranscriptGroup, row: Segment) {
  const sameSpeechGroup =
    group.rows.at(-1)?.groupId === (row.groupId || row.id);
  if (!sameSpeechGroup && row.start - group.end > TRANSCRIPT_CARD_LIMITS.naturalPauseSeconds)
    return false;
  // A VAD endpoint is a safe visual break once the current card is readable.
  // Forced ASR commits retain the same group id, so they never create arbitrary
  // two-second rows in the middle of a sentence.
  if (
    !sameSpeechGroup &&
    /[.!?][\"')\]]?$/.test(group.en.trim()) &&
    (group.end - group.start >= TRANSCRIPT_CARD_LIMITS.targetDurationSeconds ||
      group.en.length >= TRANSCRIPT_CARD_LIMITS.targetEnglishCharacters)
  )
    return false;
  if (group.rows.length >= TRANSCRIPT_CARD_LIMITS.maxRows) return false;
  if (row.end - group.start > TRANSCRIPT_CARD_LIMITS.maxDurationSeconds)
    return false;
  return (
    joinedEnglish([...group.rows, row]).length <=
    TRANSCRIPT_CARD_LIMITS.maxEnglishCharacters
  );
}

export function subtitlePages(
  rows: Segment[],
  pauseSeconds = 2.2,
): TranscriptGroup[] {
  const pauseLimit = Math.min(4, Math.max(0.5, pauseSeconds));
  const pages: TranscriptGroup[] = [];
  for (const row of rows) {
    let page = pages.at(-1);
    const nextEnglish = page ? joinedEnglish([...page.rows, row]) : row.en;
    const followsClosely = !!page && row.start - page.end <= pauseLimit;
    const fits =
      !!page &&
      followsClosely &&
      page.rows.length < 3 &&
      row.end - page.start <= 14 &&
      nextEnglish.length <= 180;
    if (!page || !fits) {
      page = {
        id: row.id,
        start: row.start,
        end: row.end,
        rows: [],
        en: "",
        zh: "",
        pending: false,
      };
      pages.push(page);
    }
    page.rows.push(row);
    page.end = Math.max(page.end, row.end);
    page.en = joinedEnglish(page.rows);
    page.zh = page.rows
      .map((item) => item.zh)
      .filter(Boolean)
      .join("");
    page.pending = page.rows.some(
      (item) => ["final", "queued", "translating"].includes(item.status) && !item.zh,
    );
    page.error = page.rows.find((item) => item.status === "error")?.error;
  }
  return pages;
}

export function groupTranscript(rows: Segment[]): TranscriptGroup[] {
  const groups: TranscriptGroup[] = [];
  for (const row of rows) {
    let group = groups.at(-1);
    if (!group || !canAppend(group, row)) {
      group = {
        // A continuous speaker group may become several bounded cards. The first
        // row id keeps each card stable while partial text and translations update.
        id: row.id,
        start: row.start,
        end: row.end,
        rows: [],
        en: "",
        zh: "",
        pending: false,
      };
      groups.push(group);
    }
    group.rows.push(row);
    group.end = Math.max(group.end, row.end);
    group.en = joinedEnglish(group.rows);
    group.zh = group.rows
      .map((item) => item.zh)
      .filter(Boolean)
      .join("");
    group.pending = group.rows.some(
      (item) =>
        ["final", "queued", "translating"].includes(item.status) && !item.zh,
    );
    group.error = group.rows.find((item) => item.status === "error")?.error;
  }
  return groups;
}
