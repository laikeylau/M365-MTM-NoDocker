import { createRequire } from "node:module";
const { chromium } = createRequire(new URL("../frontend/package.json", import.meta.url))("playwright-core");

const EXEC = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const BASE = "http://localhost:3000";

const browser = await chromium.launch({ executablePath: EXEC, headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
page.setDefaultTimeout(30000);

await page.goto(BASE + "/identity/administration/users", { waitUntil: "domcontentloaded" });
await page.waitForSelector("text=Identity Management", { timeout: 30000 });
await page.waitForTimeout(2000);

// 关闭首登弹窗（Esc → 若仍在则点关闭按钮）
await page.keyboard.press("Escape");
await page.waitForTimeout(800);
const dialogGone = await page.evaluate(
  () => !document.querySelector(".MuiDialog-container")
);
if (!dialogGone) {
  await page.screenshot({ path: "shot-dialog.png" });
  await page.evaluate(() => {
    const btn = [...document.querySelectorAll(".MuiDialog-container button")].find((b) =>
      /close|dismiss|ok|got it/i.test(b.textContent || "") || b.textContent.trim() === "Close"
    );
    if (btn) btn.click();
  });
  await page.waitForTimeout(800);
}
console.log(
  "dialog still open:",
  await page.evaluate(() => !!document.querySelector(".MuiDialog-container"))
);

// EN 截图 + 断言
await page.screenshot({ path: "shot-nav-en.png" });
const enTexts = await page.evaluate(() =>
  ["Identity Management", "Dashboard", "Security & Compliance", "Email & Exchange"].map((t) => {
    const el = [...document.querySelectorAll("span")].find((s) => s.textContent.trim() === t);
    return el ? t : `MISSING: ${t}`;
  })
);
console.log("EN:", enTexts.join(" | "));

// JS 直点语言按钮（绕过 overlay 检查）；重试规避首登弹窗/hydration 时序
let langClicked = false;
for (let i = 0; i < 10 && !langClicked; i++) {
  langClicked = await page.evaluate(() => {
    const btn = [...document.querySelectorAll("button")].find((b) =>
      (b.title || "").includes("Language")
    );
    if (!btn) return false;
    btn.click();
    return true;
  });
  if (!langClicked) await page.waitForTimeout(1000);
}
if (!langClicked) throw new Error("language button not found");
await page.waitForSelector("text=身份管理", { timeout: 15000 });
await page.waitForTimeout(1500);
await page.screenshot({ path: "shot-nav-zh.png" });

const zhTexts = await page.evaluate(() =>
  ["身份管理", "仪表板", "安全与合规", "邮件与 Exchange"].map((t) => {
    const el = [...document.querySelectorAll("span")].find((s) => s.textContent.trim() === t);
    return el ? t : `MISSING: ${t}`;
  })
);
console.log("ZH:", zhTexts.join(" | "));
console.log(
  "localStorage app.language =",
  await page.evaluate(() => localStorage.getItem("app.language"))
);

// 刷新 → 持久化生效仍为中文
await page.reload({ waitUntil: "domcontentloaded" });
await page.waitForTimeout(3500);
await page.keyboard.press("Escape");
await page.waitForTimeout(500);
await page.screenshot({ path: "shot-dash-zh.png" });
const persisted = await page.evaluate(() =>
  [...document.querySelectorAll("span")].some((s) => s.textContent.trim() === "仪表板")
);
console.log("刷新后中文保持:", persisted);

await browser.close();
console.log("ALL DONE");
