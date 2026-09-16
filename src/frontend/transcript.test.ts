import { expect, it } from "vitest";
import { groupTranscript, subtitlePages } from "./transcript";
import type { Segment } from "./protocol";

const part = (id: string, groupId: string, en: string, zh = ""): Segment => ({
  id,
  groupId,
  start: Number(id),
  end: Number(id) + 1,
  en,
  zh,
  status: zh ? "translated" : "translating",
});

it("keeps nearby API chunks in one readable card", () => {
  const groups = groupTranscript([
    part("1", "talk", "A long sentence", "一个长句"),
    part("2", "talk", "continues here.", "在这里继续。"),
    part("10", "next", "After a pause."),
  ]);
  expect(groups).toHaveLength(2);
  expect(groups[0].en).toBe("A long sentence continues here.");
  expect(groups[0].zh).toBe("一个长句在这里继续。");
  expect(groups[1].pending).toBe(true);
});

it("joins chunks separated by short natural pauses", () => {
  const groups = groupTranscript([
    part("1", "a", "Ask not."),
    part("2", "b", "What your country can do for you."),
  ]);
  expect(groups).toHaveLength(1);
  expect(groups[0].en).toContain("Ask not. What");
});

it("does not break a long sentence at a comma pause", () => {
  const first = part("1", "a", "A sufficiently long academic clause that keeps developing over time, ");
  first.end = 12;
  const second = part("12.5", "b", "and finishes only after the pause.");
  const groups = groupTranscript([first, second]);
  expect(groups).toHaveLength(1);
  expect(groups[0].en).toContain("time, and finishes");
});

it("splits continuous speech before a card grows without limit", () => {
  const rows = Array.from({ length: 18 }, (_, index) =>
    part(String(index * 2), "continuous", `Chunk ${index} has several words.`),
  );
  const groups = groupTranscript(rows);
  expect(groups.length).toBeGreaterThan(1);
  expect(groups.every((group) => group.rows.length <= 8)).toBe(true);
  expect(groups.every((group) => group.end - group.start <= 30)).toBe(true);
  expect(new Set(groups.map((group) => group.id)).size).toBe(groups.length);
});

it("keeps semantic transcript together and paginates all overlay copy", () => {
  const rows = Array.from({ length: 5 }, (_, index) =>
    part(String(index * 2), "continuous", `Sentence part ${index}.`, `第${index}段。`),
  );
  const groups = groupTranscript(rows);
  expect(groups).toHaveLength(1);
  expect(groups[0].rows).toHaveLength(5);
  const pages = subtitlePages(rows);
  expect(pages).toHaveLength(2);
  expect(pages.flatMap((page) => page.rows.map((row) => row.id))).toEqual(
    rows.map((row) => row.id),
  );
  expect(pages[0].en).toBe("Sentence part 0. Sentence part 1. Sentence part 2.");
  expect(pages[1].en).toBe("Sentence part 3. Sentence part 4.");
});

it("does not turn every short speaking pause into a new overlay page", () => {
  const rows = [
    part("1", "a", "We choose to go."),
    part("3", "b", "Not because it is easy."),
    part("5", "c", "But because it is hard."),
  ];
  expect(subtitlePages(rows)).toHaveLength(1);
  expect(subtitlePages(rows, 0.5)).toHaveLength(3);
});

it("keeps a card id stable while its translation streams", () => {
  const original = part("1", "talk", "We choose to go to the moon.");
  const translated = { ...original, zh: "我们选择登上月球。", status: "translated" as const };
  expect(groupTranscript([original])[0].id).toBe(groupTranscript([translated])[0].id);
});
