const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const assert = require("node:assert/strict");

(async () => {
  const browser = await chromium.connectOverCDP("http://127.0.0.1:9223");
  try {
    const pages = browser.contexts().flatMap((context) => context.pages());
    const main = pages.find((page) => !page.url().includes("overlay=1"));
    const overlay = pages.find((page) => page.url().includes("overlay=1"));
    assert(main && overlay, "LinguaGlass native windows were not discovered");

    await main.getByRole("heading", { name: "实时翻译" }).waitFor();
    await main.getByRole("button", { name: "打开悬浮字幕" }).click();
    await main.getByRole("button", { name: "关闭悬浮字幕" }).waitFor();
    await overlay.getByRole("button", { name: "收起字幕" }).click();
    await overlay.waitForFunction(() => innerWidth <= 240 && innerHeight <= 80);
    const compact = await overlay.evaluate(() => ({
      width: innerWidth,
      height: innerHeight,
      scrollWidth: document.documentElement.scrollWidth,
      scrollHeight: document.documentElement.scrollHeight,
      shell: (() => {
        const rect = document.querySelector(".overlay-shell").getBoundingClientRect();
        return [rect.x, rect.y, rect.width, rect.height];
      })(),
    }));
    assert(compact.width >= 180 && compact.height >= 56);
    assert(compact.scrollWidth <= compact.width);
    assert(compact.scrollHeight <= compact.height);
    assert.equal(compact.shell[0], 0);
    assert.equal(compact.shell[1], 0);
    assert(Math.abs(compact.shell[2] - compact.width) < 1);
    assert(Math.abs(compact.shell[3] - compact.height) < 1);
    await overlay.screenshot({ path: "artifacts/native-ui-v3-collapsed.png" });

    await overlay.getByRole("button", { name: "展开字幕" }).click();
    await overlay.waitForFunction(() => innerWidth > 300 && innerHeight > 200);
    await overlay.getByRole("button", { name: "关闭" }).click();
    await main.waitForFunction(() =>
      window.__TAURI_INTERNALS__.invoke("overlay_status").then((state) => !state.visible),
    );
    console.log(
      `NATIVE_UI_V3_OK: compact ${compact.width}x${compact.height}, no overflow, expand and close passed.`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
