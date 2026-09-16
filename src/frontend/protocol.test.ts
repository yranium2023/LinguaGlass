import { describe, expect, it } from "vitest";
import { initialState, reduceEvent } from "./protocol";

describe("independent subtitles", () => {
  it("clears stale warnings on a new session but retains failures at stop", () => {
    let state = reduceEvent(initialState, {
      type: "error",
      message: "Offline",
    });
    state = reduceEvent(state, { type: "status", state: "IDLE" });
    expect(state.message).toBe("Offline");
    state = reduceEvent(state, { type: "status", state: "INITIALIZING" });
    expect(state.message).toBe("");
  });
  it("retains English when translation fails and rejects late partials", () => {
    let state = reduceEvent(initialState, {
      type: "asr_final",
      id: "a",
      text: "Gradient descent",
      seq: 1,
    });
    state = reduceEvent(state, {
      type: "translation_error",
      id: "a",
      message: "Offline",
      seq: 2,
    });
    state = reduceEvent(state, {
      type: "asr_partial",
      id: "a",
      text: "Gradient",
      seq: 3,
    });
    expect(state.rows[0]).toMatchObject({
      en: "Gradient descent",
      status: "error",
      error: "Offline",
    });
  });
  it("correlates out-of-order translation by ID", () => {
    let state = initialState;
    for (const id of ["a", "b"])
      state = reduceEvent(state, { type: "asr_final", id, text: id });
    state = reduceEvent(state, {
      type: "translation_done",
      id: "a",
      text: "甲",
    });
    expect(state.rows.map((r) => r.zh)).toEqual(["甲", ""]);
  });
  it("keeps updating one row after a provisional translation", () => {
    let state = reduceEvent(initialState, {
      type: "asr_partial",
      id: "a",
      text: "We choose",
      end: 2.1,
    });
    state = reduceEvent(state, {
      type: "translation_done",
      id: "a",
      text: "我们选择",
    });
    state = reduceEvent(state, {
      type: "asr_partial",
      id: "a",
      text: "We choose to go to the moon",
      end: 4.2,
    });
    expect(state.rows).toHaveLength(1);
    expect(state.rows[0]).toMatchObject({
      en: "We choose to go to the moon",
      zh: "我们选择",
      finalized: false,
    });
  });
  it("bounds the live view and resets across sessions", () => {
    let state = initialState;
    for (let i = 0; i < 2000; i++)
      state = reduceEvent(state, {
        type: "asr_final",
        id: String(i),
        text: "text",
        seq: i + 1,
        session_id: "one",
      });
    expect(state.rows).toHaveLength(300);
    state = reduceEvent(state, {
      type: "status",
      state: "INITIALIZING",
      session_id: "two",
      seq: 2001,
    });
    expect(state.rows).toHaveLength(0);
  });
  it("ignores duplicate snapshot/live events", () => {
    const state = reduceEvent(initialState, {
      type: "asr_final",
      id: "a",
      text: "final",
      seq: 10,
    });
    expect(
      reduceEvent(state, { type: "asr_partial", id: "a", text: "old", seq: 9 }),
    ).toBe(state);
  });
  it("clears partials and marks unfinished translation on stop", () => {
    let state = reduceEvent(initialState, {
      type: "asr_partial",
      id: "a",
      text: "partial",
    });
    state = reduceEvent(state, { type: "asr_final", id: "b", text: "final" });
    state = reduceEvent(state, { type: "status", state: "IDLE" });
    expect(state.rows).toHaveLength(1);
    expect(state.rows[0].status).toBe("error");
  });
});
