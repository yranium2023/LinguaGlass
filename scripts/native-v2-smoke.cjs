const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");
async function selectGlass(page, label, option) {
  await page.getByRole("combobox", { name: label, exact: true }).click();
  await page.getByRole("option", { name: option, exact: true }).click();
}
(async () => {
  const browser = await chromium.connectOverCDP("http://127.0.0.1:9223");
  const pages = browser.contexts().flatMap((c) => c.pages());
  const main = pages.find((p) => !p.url().includes("overlay=1"));
  const overlay = pages.find((p) => p.url().includes("overlay=1"));
  const errors = [];
  main.on("pageerror", (e) => errors.push(e.message));
  const original = await main.evaluate(() =>
    localStorage.getItem("linguaglass.preferences.v2"),
  );
  async function waitState(state, timeout = 60000) {
    await main.waitForFunction(
      (expected) =>
        window.__TAURI_INTERNALS__
          .invoke("snapshot")
          .then((s) => s.state === expected),
      state,
      { timeout },
    );
  }
  try {
    await main.reload();
    await main
      .getByRole("heading", { name: "实时翻译", exact: true })
      .waitFor();
    await main.getByRole("button", { name: "系统音频", exact: true }).click();
    await main.waitForFunction(
      () => !document.querySelector(".primary-button").disabled,
    );
    const devices = await main.evaluate(() =>
      window.__TAURI_INTERNALS__.invoke("devices", { inputMode: "system" }),
    );
    assert(devices.length > 0, "No playback devices");
    await main.getByRole("button", { name: "刷新设备列表" }).click();
    await main.waitForFunction(
      () => !document.querySelector(".primary-button").disabled,
    );
    await selectGlass(main, "文字大小", "特大");
    await main.getByRole("button", { name: "设置", exact: true }).click();
    await main.getByLabel("课程术语表").fill("testterm = 测试词");
    await main.keyboard.press("Escape");
    await main.reload();
    await main.waitForFunction(
      () => !document.querySelector(".primary-button").disabled,
    );
    assert.equal(
      await main.getByRole("combobox", { name: "文字大小" }).textContent(),
      "特大",
    );
    await main.getByRole("button", { name: "设置", exact: true }).click();
    assert.equal(
      await main.getByLabel("课程术语表").inputValue(),
      "testterm = 测试词",
    );
    await main.keyboard.press("Escape");
    await main.getByRole("button", { name: "打开悬浮字幕" }).click();
    await main.getByRole("button", { name: "关闭悬浮字幕" }).waitFor();
    await overlay.getByRole("button", { name: "收起字幕" }).click();
    await overlay.waitForFunction(() => innerWidth <= 240);
    const small = await overlay.evaluate(() => ({
      width: innerWidth,
      height: innerHeight,
    }));
    assert(
      small.height <= 80,
      "Collapsed native window still blocks the screen",
    );
    await overlay.getByRole("button", { name: "展开字幕" }).click();
    await overlay.waitForFunction(() => innerWidth > 300);
    await main.getByRole("button", { name: "设置", exact: true }).click();
    await main.getByLabel("悬浮字幕鼠标穿透", { exact: true }).click();
    await main.waitForFunction(() =>
      window.__TAURI_INTERNALS__
        .invoke("overlay_status")
        .then((s) => s.click_through),
    );
    await main.getByLabel("悬浮字幕鼠标穿透", { exact: true }).click();
    await main.waitForFunction(() =>
      window.__TAURI_INTERNALS__
        .invoke("overlay_status")
        .then((s) => !s.click_through),
    );
    await main.keyboard.press("Escape");
    // Simulates a hide initiated outside React; UI must resynchronize.
    await main.evaluate(() =>
      window.__TAURI_INTERNALS__.invoke("set_overlay", {
        visible: false,
        clickThrough: false,
      }),
    );
    await main.getByRole("button", { name: "打开悬浮字幕" }).waitFor();
    for (const source of ["系统音频", "麦克风"]) {
      await main.getByRole("button", { name: source, exact: true }).click();
      await main.waitForFunction(
        () => !document.querySelector(".primary-button").disabled,
      );
      await main.getByRole("button", { name: "开始聆听", exact: true }).click();
      await waitState("LISTENING");
      assert(
        await main.getByRole("button", { name: "刷新设备列表" }).isDisabled(),
      );
      await main.getByRole("button", { name: "结束聆听", exact: true }).click();
      await waitState("IDLE");
    }
    const exportPath = await main.evaluate(() =>
      window.__TAURI_INTERNALS__.invoke("export_session", { format: "json" }),
    );
    assert(Array.isArray(JSON.parse(fs.readFileSync(exportPath, "utf8"))));
    await main.getByRole("button", { name: "系统音频", exact: true }).click();
    await selectGlass(main, "文字大小", "大");
    await main.screenshot({
      path: "artifacts/native-v2-main.png",
      fullPage: true,
    });
    assert.deepEqual(errors, []);
    fs.writeFileSync(
      "artifacts/native-v2-report.json",
      JSON.stringify(
        {
          playbackDevices: devices.length,
          collapsedSize: small,
          checks:
            "system+mic start/stop, refresh, preferences, keyboard, overlay compact, clickthrough, native state sync, export",
        },
        null,
        2,
      ),
    );
    console.log(
      "NATIVE_V2_OK: system/mic start-stop, preferences, native overlay resize, pass-through and state sync, export.",
    );
  } finally {
    await main
      .evaluate(() =>
        window.__TAURI_INTERNALS__.invoke("set_overlay", {
          visible: false,
          clickThrough: false,
        }),
      )
      .catch(() => {});
    await main.keyboard.press("Escape").catch(() => {});
    await main.evaluate((saved) => {
      if (saved === null) localStorage.removeItem("linguaglass.preferences.v2");
      else localStorage.setItem("linguaglass.preferences.v2", saved);
    }, original);
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
