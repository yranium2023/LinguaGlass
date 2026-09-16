export const defaults = {
  input_mode: "system" as "system" | "microphone",
  device_id: null as string | null,
  gain: 1,
  asr_model: "distil-large-v3",
  compute: "cpu",
  translation_model: "deepseek-v4-flash",
  domain: "General",
  glossary: "",
  context_length: 3,
  subtitle_pause_seconds: 2.2,
  asr_silence_seconds: 0.9,
  asr_max_segment_seconds: 20,
  asr_patience: 1.2,
};
export type Config = typeof defaults;
export const preferenceKey = "linguaglass.preferences.v2";
export type Appearance = {
  size: "standard" | "large" | "extra";
  theme: "light" | "dark";
  accent: Accent;
};
export type Accent = "blue" | "indigo" | "violet" | "rose" | "orange" | "mint";
export function loadPreferences(): { config: Config; appearance: Appearance } {
  const result = {
    config: { ...defaults },
    appearance: {
      size: "standard",
      theme: "light",
      accent: "blue",
    } as Appearance,
  };
  try {
    const raw = JSON.parse(localStorage.getItem(preferenceKey) || "{}");
    const c = raw.config ?? {};
    for (const key of [
      "asr_model",
      "compute",
      "translation_model",
      "domain",
      "glossary",
    ] as const)
      if (typeof c[key] === "string") result.config[key] = c[key];
    if (
      !["distil-large-v3", "distil-medium.en", "distil-small.en"].includes(
        result.config.asr_model,
      )
    )
      result.config.asr_model = defaults.asr_model;
    if (!["cpu", "cuda"].includes(result.config.compute))
      result.config.compute = "cpu";
    if (
      !["deepseek-v4-flash", "deepseek-v4-pro"].includes(
        result.config.translation_model,
      )
    )
      result.config.translation_model = defaults.translation_model;
    if (c.input_mode === "microphone") result.config.input_mode = "microphone";
    if (typeof c.device_id === "string") result.config.device_id = c.device_id;
    if (typeof c.gain === "number" && c.gain >= 0 && c.gain <= 2)
      result.config.gain = c.gain;
    if ([0, 2, 3, 4].includes(c.context_length))
      result.config.context_length = c.context_length;
    if (
      typeof c.subtitle_pause_seconds === "number" &&
      c.subtitle_pause_seconds >= 0.5 &&
      c.subtitle_pause_seconds <= 4
    )
      result.config.subtitle_pause_seconds =
        Math.round(c.subtitle_pause_seconds * 10) / 10;
    if (
      typeof c.asr_silence_seconds === "number" &&
      c.asr_silence_seconds >= 0.4 &&
      c.asr_silence_seconds <= 2
    )
      result.config.asr_silence_seconds =
        Math.round(c.asr_silence_seconds * 10) / 10;
    if (
      typeof c.asr_max_segment_seconds === "number" &&
      c.asr_max_segment_seconds >= 8 &&
      c.asr_max_segment_seconds <= 30
    )
      result.config.asr_max_segment_seconds = Math.round(
        c.asr_max_segment_seconds,
      );
    if (
      typeof c.asr_patience === "number" &&
      c.asr_patience >= 1 &&
      c.asr_patience <= 2
    )
      result.config.asr_patience = Math.round(c.asr_patience * 10) / 10;
    result.config.glossary = result.config.glossary.slice(0, 4000);
    result.config.domain = result.config.domain.slice(0, 100);
    if (["standard", "large", "extra"].includes(raw.appearance?.size))
      result.appearance.size = raw.appearance.size;
    if (raw.appearance?.theme === "dark") result.appearance.theme = "dark";
    if (
      ["blue", "indigo", "violet", "rose", "orange", "mint"].includes(
        raw.appearance?.accent,
      )
    )
      result.appearance.accent = raw.appearance.accent;
  } catch {
    /* Fall back safely when old settings are damaged. */
  }
  return result;
}
export function savePreferences(config: Config, appearance: Appearance) {
  // Construct an allowlist; secrets can never be persisted through this path.
  const safe = Object.fromEntries(
    Object.keys(defaults).map((key) => [key, config[key as keyof Config]]),
  );
  try {
    localStorage.setItem(
      preferenceKey,
      JSON.stringify({ config: safe, appearance }),
    );
    return true;
  } catch {
    return false;
  }
}
