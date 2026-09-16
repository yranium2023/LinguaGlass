import { expect, it } from "vitest";
import { advanceReading, emptyReading, subtitlePresentation } from "./subtitle";
import type { Segment } from "./protocol";
const row = (
  id: string,
  status: Segment["status"] = "translated",
): Segment => ({
  id,
  groupId: id,
  start: 0,
  end: 1,
  en: id,
  zh: status === "translated" ? "中文" : "",
  status,
});
it("holds a complete translation while new speech arrives", () => {
  const first = advanceReading(emptyReading, "s", [row("a")], 0, 8);
  const next = advanceReading(
    first,
    "s",
    [row("a"), row("b", "partial")],
    1000,
    8,
  );
  expect(next.row?.id).toBe("a");
  expect(advanceReading(next, "s", [row("a"), row("b")], 7999, 8).row?.id).toBe(
    "a",
  );
  expect(advanceReading(next, "s", [row("a"), row("b")], 8000, 8).row?.id).toBe(
    "b",
  );
});
it("shows delayed translations in order and resets for a new session", () => {
  const first = advanceReading(
    emptyReading,
    "s",
    [row("a", "queued"), row("b", "partial")],
    0,
    8,
  );
  const translated = advanceReading(first, "s", [row("a"), row("b")], 1000, 8);
  expect(translated.row?.id).toBe("a");
  expect(advanceReading(translated, "new", [], 2000, 8).row).toBeUndefined();
});
it("keeps readable Chinese while live English continues", () => {
  const translated = row("a");
  const partial = row("b", "partial");
  const shown = subtitlePresentation([translated, partial], translated);
  expect(shown.english).toBe("a b");
  expect(shown.chinese).toBe("中文");
});
