const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const assert = require("node:assert/strict");
async function selectGlass(page, label, option) {
  await page.getByRole("combobox", { name: label, exact: true }).click();
  await page.getByRole("option", { name: option, exact: true }).click();
}
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 1000 },
    });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.goto("http://127.0.0.1:1420", { waitUntil: "networkidle" });
    assert(
      await page
        .getByRole("button", { name: "开始聆听", exact: true })
        .isDisabled(),
    );
    assert.equal(await page.evaluate(() => scrollY), 0);
    await page.screenshot({ path: "artifacts/ui-v2-main.png", fullPage: true });
    await page.getByRole("combobox", { name: "导出格式" }).click();
    await page.waitForTimeout(220);
    await page.screenshot({ path: "artifacts/ui-v2-select-open.png" });
    await page.keyboard.press("Escape");
    await selectGlass(page, "文字大小", "特大");
    assert.equal(
      await page.evaluate(
        () => getComputedStyle(document.documentElement).fontSize,
      ),
      "22px",
    );
    await page.getByRole("button", { name: "选择主题色" }).click();
    await page.getByRole("button", { name: "主题色：紫罗兰" }).click();
    assert.equal(
      await page.locator("html").getAttribute("data-accent"),
      "violet",
    );
    await page.getByRole("button", { name: "麦克风", exact: true }).click();
    await page.getByRole("button", { name: "设置", exact: true }).click();
    await page.getByLabel("课程术语表").fill("gradient = 梯度");
    await page.keyboard.press("Escape");
    assert(!(await page.locator("dialog").isVisible()));
    await page.reload({ waitUntil: "networkidle" });
    assert.equal(
      await page
        .getByRole("button", { name: "麦克风", exact: true })
        .getAttribute("aria-pressed"),
      "true",
    );
    assert.equal(
      await page.getByRole("combobox", { name: "文字大小" }).textContent(),
      "特大",
    );
    assert.equal(
      await page.locator("html").getAttribute("data-accent"),
      "violet",
    );
    await page.getByRole("button", { name: "设置", exact: true }).click();
    assert.equal(
      await page.getByLabel("课程术语表").inputValue(),
      "gradient = 梯度",
    );
    await page
      .getByLabel("DeepSeek API Key", { exact: false })
      .fill("not-a-real-key");
    await page.waitForTimeout(260);
    await page.screenshot({
      path: "artifacts/ui-v2-settings.png",
      fullPage: true,
    });
    await page.getByRole("button", { name: "完成", exact: true }).click();
    await page.getByRole("button", { name: "设置", exact: true }).click();
    assert.equal(
      await page.getByLabel("DeepSeek API Key", { exact: false }).inputValue(),
      "",
    );
    await page.keyboard.press("Escape");
    await page.setViewportSize({ width: 900, height: 760 });
    assert(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    );
    await page.screenshot({
      path: "artifacts/ui-v2-compact.png",
      fullPage: true,
    });
    await page.setViewportSize({ width: 3840, height: 2160 });
    await selectGlass(page, "文字大小", "大");
    await page.screenshot({ path: "artifacts/ui-v2-4k.png" });
    await page.getByRole("button", { name: "切换深色外观" }).click();
    await page.screenshot({ path: "artifacts/ui-v2-dark.png" });
    const overlay = await context.newPage();
    await overlay.setViewportSize({ width: 900, height: 330 });
    await overlay.goto("http://127.0.0.1:1420?overlay=1", {
      waitUntil: "networkidle",
    });
    assert.equal(
      await overlay.locator("html").getAttribute("data-theme"),
      "dark",
    );
    assert.deepEqual(
      await overlay.locator(".overlay-shell").evaluate((element) => {
        const rect = element.getBoundingClientRect();
        return [rect.x, rect.y, rect.width, rect.height];
      }),
      [0, 0, 900, 330],
    );
    assert.equal(
      await overlay.evaluate(
        () => document.documentElement.scrollHeight <= innerHeight,
      ),
      true,
    );
    await overlay.getByRole("button", { name: "关闭" }).waitFor();
    await overlay.screenshot({ path: "artifacts/ui-v2-overlay-dark.png" });
    await overlay.evaluate(() => {
      const key = "linguaglass.preferences.v2";
      const preferences = JSON.parse(localStorage.getItem(key) || "{}");
      preferences.appearance = { ...preferences.appearance, theme: "light" };
      localStorage.setItem(key, JSON.stringify(preferences));
    });
    await overlay.reload({ waitUntil: "networkidle" });
    assert.equal(
      await overlay.locator("html").getAttribute("data-theme"),
      "light",
    );
    await overlay.screenshot({ path: "artifacts/ui-v2-overlay-light.png" });
    await overlay.getByRole("button", { name: "收起字幕" }).click();
    await overlay.setViewportSize({ width: 200, height: 64 });
    assert.deepEqual(
      await overlay.locator(".overlay-shell").evaluate((element) => {
        const rect = element.getBoundingClientRect();
        return [rect.x, rect.y, rect.width, rect.height];
      }),
      [0, 0, 200, 64],
    );
    await overlay.getByRole("button", { name: "展开字幕" }).waitFor();
    await overlay.getByRole("button", { name: "关闭" }).waitFor();
    await overlay.screenshot({ path: "artifacts/ui-v2-overlay-collapsed.png" });
    await overlay.close();
    assert.deepEqual(errors, []);
    console.log(
      "UI_V2_OK: 4K/compact, text scale, persisted settings, Escape, password cleanup, no page errors.",
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
