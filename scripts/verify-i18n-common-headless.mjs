import { createRequire } from "node:module";
const { chromium } = createRequire(new URL("../frontend/package.json", import.meta.url))("playwright-core");

const EXEC = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const BASE = "http://localhost:3000";

const browser = await chromium.launch({ executablePath: EXEC, headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
page.setDefaultTimeout(30000);

// ── EN 基线 ─────────────────────────────────────────────────────────────
await page.goto(BASE + "/identity/administration/users", { waitUntil: "domcontentloaded" });
await page.waitForSelector("text=Identity Management", { timeout: 30000 });
await page.waitForTimeout(2500);
await page.keyboard.press("Escape"); // 关闭首登弹窗
await page.waitForTimeout(800);

const findVisible = (text) =>
  [...document.querySelectorAll("button, span, input, p, div")]
    .filter((el) => ["button", "span", "p", "input", "div"].includes(el.tagName.toLowerCase()))
    .some((el) => (el.placeholder ?? el.textContent ?? "").trim() === text);

const enChecks = await page.evaluate((findVisibleSrc) => {
  const findVisible = new Function(`return (${findVisibleSrc})`)();
  return ["Filters", "Columns", "Export"].map((t) => (findVisible(t) ? t : `MISSING: ${t}`));
}, findVisible.toString());
console.log("EN toolbar:", enChecks.join(" | "));

const enPlaceholder = await page.evaluate(
  () => document.querySelector('input[placeholder="Search input"]')?.placeholder || "NO-PLACEHOLDER"
);
console.log("EN search placeholder:", enPlaceholder);

// ── 切换到中文 ──────────────────────────────────────────────────────────
await page.evaluate(() => {
  const btn = [...document.querySelectorAll("button")].find((b) =>
    (b.title || "").startsWith("Language:")
  );
  btn.click();
});
await page.waitForSelector("text=身份管理", { timeout: 15000 });
await page.waitForTimeout(1500);

const zhChecks = await page.evaluate((findVisibleSrc) => {
  const findVisible = new Function(`return (${findVisibleSrc})`)();
  return ["筛选", "列", "导出"].map((t) => (findVisible(t) ? t : `MISSING: ${t}`));
}, findVisible.toString());
console.log("ZH toolbar:", zhChecks.join(" | "));

const zhPlaceholder = await page.evaluate(
  () => document.querySelector('input[placeholder="搜索"]')?.placeholder || "NO-PLACEHOLDER"
);
console.log("ZH search placeholder:", zhPlaceholder);

// ── 列菜单（preferred columns 文案） ────────────────────────────────────
await page.evaluate(() => {
  const btn = [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "列");
  btn.click();
});
await page.waitForTimeout(600);
const zhColumnMenu = await page.evaluate(() => {
  const texts = [...document.querySelectorAll(".MuiMenu-root [role=menuitem] .MuiListItemText-primary")].map(
    (el) => el.textContent.trim()
  );
  const hits = ["恢复首选列设置", "保存为首选列设置", "删除首选列设置"].filter((t) =>
    texts.includes(t)
  );
  return { hits, total: texts.length };
});
console.log(
  "ZH columns menu:",
  `${zhColumnMenu.hits.length}/3 命中（菜单共 ${zhColumnMenu.total} 项）→`,
  zhColumnMenu.hits.join(" | ")
);
await page.keyboard.press("Escape");
await page.waitForTimeout(400);

// ── MRT zh-Hans 内置本地化 + 租户 alert ─────────────────────────────
const zhMrt = await page.evaluate(() => {
  const text = document.body.innerText || "";
  return {
    mrtActions: text.includes("操作"),
    mrtRowsPerPage: text.includes("每页行数"),
    tenantAlert: text.includes("尚未选择租户"),
  };
});
console.log("ZH MRT 本地化:", JSON.stringify(zhMrt));

await page.screenshot({ path: "docs/screenshots-phase3/zh-management-toolbar.png" });

// ── 判定 ────────────────────────────────────────────────────────────────
const allHit =
  enChecks.every((s) => !s.startsWith("MISSING")) &&
  enChecks.length === 3 &&
  enPlaceholder === "Search input" &&
  zhChecks.every((s) => !s.startsWith("MISSING")) &&
  zhChecks.length === 3 &&
  zhPlaceholder === "搜索" &&
  zhColumnMenu.hits.length === 3 &&
  zhMrt.mrtActions &&
  zhMrt.mrtRowsPerPage &&
  zhMrt.tenantAlert;

console.log(allHit ? "RESULT: PASS ✅" : "RESULT: FAIL ❌");
await browser.close();
process.exit(allHit ? 0 : 1);
