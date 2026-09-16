import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  defaults,
  loadPreferences,
  savePreferences,
  preferenceKey,
} from "./preferences";
const data = new Map<string, string>();
beforeEach(() => {
  data.clear();
  vi.stubGlobal("localStorage", {
    getItem: (k: string) => data.get(k) ?? null,
    setItem: (k: string, v: string) => data.set(k, v),
  });
});
describe("local preferences", () => {
  it("defaults to system audio and readable text", () => {
    const p = loadPreferences();
    expect(p.config.input_mode).toBe("system");
    expect(p.appearance.size).toBe("standard");
    expect(p.config.subtitle_pause_seconds).toBe(2.2);
    expect(p.config.asr_silence_seconds).toBe(0.9);
    expect(p.config.asr_max_segment_seconds).toBe(20);
    expect(p.config.asr_patience).toBe(1.2);
  });
  it("recovers from damaged settings", () => {
    data.set(preferenceKey, "bad");
    expect(loadPreferences().config).toEqual(defaults);
  });
  it("persists choices but never arbitrary secrets", () => {
    savePreferences(
      {
        ...defaults,
        input_mode: "microphone",
        glossary: "gradient = 梯度",
        subtitle_pause_seconds: 3.4,
        asr_silence_seconds: 1.1,
        asr_max_segment_seconds: 24,
        asr_patience: 1.5,
        key: "DO-NOT-PERSIST",
      } as typeof defaults,
      { size: "extra", theme: "dark", accent: "violet" },
    );
    expect(data.get(preferenceKey)).not.toContain("DO-NOT-PERSIST");
    expect(loadPreferences().config.glossary).toContain("梯度");
    expect(loadPreferences().config.subtitle_pause_seconds).toBe(3.4);
    expect(loadPreferences().config.asr_silence_seconds).toBe(1.1);
    expect(loadPreferences().config.asr_max_segment_seconds).toBe(24);
    expect(loadPreferences().config.asr_patience).toBe(1.5);
    expect(loadPreferences().appearance.size).toBe("extra");
    expect(loadPreferences().appearance.accent).toBe("violet");
  });
});
