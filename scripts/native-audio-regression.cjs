const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const assert = require("node:assert/strict");

(async () => {
  const browser = await chromium.connectOverCDP("http://127.0.0.1:9223");
  const pages = browser.contexts().flatMap((context) => context.pages());
  const main = pages.find((page) => !page.url().includes("overlay=1"));
  assert(main, "Main webview is missing");
  try {
    await main.evaluate(() =>
      window.__TAURI_INTERNALS__.invoke("set_overlay", {
        visible: true,
        clickThrough: false,
      }),
    );
    await new Promise((resolve) => setTimeout(resolve, 500));
    const overlay = browser
      .contexts()
      .flatMap((context) => context.pages())
      .find((page) => page.url().includes("overlay=1"));
    assert(overlay, "Overlay webview is missing after it was shown");
    await main.evaluate(() =>
      window.__TAURI_INTERNALS__.invoke("start_session", {
        config: {
          input_mode: "system",
          device_id: null,
          gain: 1,
          asr_model: "distil-large-v3",
          compute: "cuda",
          translation_model: "deepseek-v4-flash",
          domain: "General",
          glossary: "",
          context_length: 2,
        },
      }),
    );
    await main.waitForFunction(
      () =>
        window.__TAURI_INTERNALS__
          .invoke("snapshot")
          .then((s) => s.state === "LISTENING"),
      null,
      { timeout: 90000 },
    );
    await overlay.locator(".overlay-text").waitFor({ state: "visible" });

    await main.evaluate(async () => {
      const player = new Audio("/test-audio.wav");
      window.__linguaGlassTestPlayer = player;
      await player.play();
    });
    const observed = new Set();
    const cardIds = new Set();
    const overlayHeights = new Set();
    let layoutSamples = 0;
    let sawPreviousCard = false;
    while (!(await main.evaluate(() => window.__linguaGlassTestPlayer?.ended))) {
      observed.add(
        (await overlay.locator(".overlay-text .english").allTextContents()).join(" | ").trim(),
      );
      for (const id of await overlay.locator(".subtitle-card").evaluateAll((cards) =>
        cards.map((card) => card.getAttribute("data-card-id")).filter(Boolean),
      )) cardIds.add(id);
      sawPreviousCard ||= (await overlay.locator(".subtitle-card.previous").count()) === 1;
      layoutSamples += 1;
      if (layoutSamples > 5)
        overlayHeights.add(
          Math.round(await overlay.locator(".overlay-text").evaluate((node) => node.getBoundingClientRect().height)),
        );
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    await main.waitForFunction(
      () =>
        window.__TAURI_INTERNALS__
          .invoke("snapshot")
          .then((s) =>
            s.events.some((event) => event.type === "asr_final"),
          ),
      null,
      { timeout: 90000 },
    );
    for (let index = 0; index < 25; index++) {
      observed.add(
        (await overlay.locator(".overlay-text .english").allTextContents()).join(" | ").trim(),
      );
      for (const id of await overlay.locator(".subtitle-card").evaluateAll((cards) =>
        cards.map((card) => card.getAttribute("data-card-id")).filter(Boolean),
      )) cardIds.add(id);
      sawPreviousCard ||= (await overlay.locator(".subtitle-card.previous").count()) === 1;
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    const snapshot = await main.evaluate(() =>
      window.__TAURI_INTERNALS__.invoke("snapshot"),
    );
    const finals = snapshot.events.filter(
      (event) => event.type === "asr_final",
    );
    const latencies = snapshot.events.filter((event) => event.type === "latency");
    const previewLatencies = latencies.filter((event) => event.provisional);
    const visibleGroups = await main.locator(".transcript-row").count();
    const transcriptEnglish = await main.locator(".transcript-row .row-en").allTextContents();
    assert(visibleGroups >= 2, "Long speech did not create bounded transcript cards");
    assert(
      transcriptEnglish.slice(0, -1).every((text) => !text.trim().endsWith(",")),
      "Conversation transcript split a sentence immediately after a comma",
    );
    assert(sawPreviousCard, "Overlay never retained the previous subtitle card");
    assert(cardIds.size >= 2, "Overlay card did not advance during continuous speech");
    assert(cardIds.size < finals.length, "Short pauses caused nearly every ASR segment to change page");
    assert((await overlay.locator(".subtitle-card").count()) <= 2, "Overlay rendered more than two cards");
    assert(overlayHeights.size <= 1, `Overlay text area changed height: ${[...overlayHeights]}`);
    assert(
      await overlay.evaluate(() =>
        document.scrollingElement.scrollHeight <= window.innerHeight + 1,
      ),
      "Overlay document developed a scrollbar",
    );
    assert.equal(
      await overlay.locator(".subtitle-card .english, .subtitle-card .chinese").evaluateAll(
        (lines) => lines.filter((line) => line.scrollHeight > line.clientHeight + 1).length,
      ),
      0,
      "Overlay hid the beginning or end of a subtitle line",
    );
    assert(
      [...observed].some((text) => !text.includes("Listening starts")),
      `Overlay did not receive English: ${JSON.stringify([...observed])}`,
    );
    assert(
      ![...observed].every((text) => text.includes("Listening starts")),
      "Overlay stayed on placeholder",
    );
    assert(latencies.length > 0, "No completed API translation latency was recorded");
    assert(previewLatencies.length > 0, "No two-second provisional translation completed");
    const firstToken = latencies.map((event) => event.first_token_ms).sort((a, b) => a - b);
    const totals = latencies.map((event) => event.total_ms).sort((a, b) => a - b);
    const median = (values) => values[Math.floor(values.length / 2)];
    await overlay.screenshot({ path: "artifacts/native-overlay-audio.png" });
    await main.screenshot({ path: "artifacts/native-audio-main.png" });
    console.log(
      `NATIVE_AUDIO_OK finals=${finals.length} visibleCards=${visibleGroups} overlayCards=${cardIds.size} ` +
        `overlayUpdates=${observed.size} apiSamples=${latencies.length} previews=${previewLatencies.length} ` +
        `firstTokenMedianMs=${median(firstToken)} totalMedianMs=${median(totals)} ` +
        `queueMaxMs=${Math.max(...latencies.map((event) => event.queue_ms))}`,
    );
  } finally {
    await main
      .evaluate(() => window.__TAURI_INTERNALS__.invoke("stop_session"))
      .catch(() => {});
    await main
      .evaluate(() =>
        window.__TAURI_INTERNALS__.invoke("set_overlay", {
          visible: false,
          clickThrough: false,
        }),
      )
      .catch(() => {});
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
