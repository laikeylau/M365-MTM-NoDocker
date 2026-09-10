#!/usr/bin/env node
/**
 * Phase 3 批次 3 无头 E2E：报告中心 nameEn/nameZh 对接 + 列头渐进 + 动作 label。
 *
 * 前置（两个终端）:
 *   1. pwsh -File cipp-server.ps1                          # 后端 :7071（可不上数据）
 *   2. DEV_SERVE_FIXTURES=scripts/fixtures/mfa-users.json node scripts/dev-serve.mjs
 *      # 静态 out/ + /api 注入 superadmin；ListMFAUsers 返回 fixture（2 行）
 *
 * 断言:
 *   A. EN 基线: /reports/identity/mfa-state 标题 "MFA Report"、列头 "Account Enabled"
 *   B. ZH 切换: 标题 "MFA 报表"、列头 "账户已启用/已授权/是管理员"、树 "身份与访问"
 *   C. 行内动作菜单 ZH: "设置每用户 MFA"
 *   D. 持久化: 刷新后中文保持
 */
import { createRequire } from "node:module";

// playwright-core 安装在 frontend/node_modules（npm install --no-save playwright-core），
// scripts/ 下 ESM 解析不到，从 frontend 包上下文显式 require。
const frontendRequire = createRequire(
  new URL("../frontend/package.json", import.meta.url)
);
const { chromium } = frontendRequire("playwright-core");

const EXEC = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const BASE = "http://localhost:3000";
const REPORT = "/reports/identity/mfa-state";

const browser = await chromium.launch({ executablePath: EXEC, headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
page.setDefaultTimeout(30000);

const results = [];
const record = (name, ok, detail = "") => {
  results.push({ name, ok });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
};

const visibleTexts = () =>
  [...document.querySelectorAll("body *")]
    .filter((el) => el.children.length === 0)
    .map((el) => (el.textContent ?? "").trim())
    .filter(Boolean);

// 若有弹窗（首登欢迎等）拦截点击，先关闭（Esc + 关闭按钮，双保险）
const closeDialogs = async () => {
  if (!(await page.evaluate(() => !!document.querySelector(".MuiDialog-container")))) return;
  await page.keyboard.press("Escape");
  await page.waitForTimeout(500);
  await page.evaluate(() => {
    const btn = [...document.querySelectorAll(".MuiDialog-container button")].find(
      (b) => /close|dismiss|ok|got it/i.test(b.textContent || "")
    );
    if (btn) btn.click();
  });
  await page.waitForTimeout(800);
};

// ── A. EN 基线 ──────────────────────────────────────────────────────────
await page.goto(BASE + REPORT, { waitUntil: "domcontentloaded" });
await page.waitForSelector("text=MFA Report", { timeout: 30000 });
await page.waitForTimeout(2500);
await closeDialogs();
await page.waitForTimeout(1500);

let texts = await page.evaluate(visibleTexts);
record("A1 EN 标题 MFA Report", texts.includes("MFA Report"));
record("A2 EN 列头 Account Enabled / Is Licensed", texts.includes("Account Enabled") && texts.includes("Is Licensed"));
record("A3 EN 列头双语未激活 (无 账户已启用)", !texts.includes("账户已启用"));
record("A4 EN fixture 数据行 (admin@contoso.com)", texts.includes("admin@contoso.com"));

// ── B. 切换到中文 ────────────────────────────────────────────────────────
await page.evaluate(() => {
  const btn = [...document.querySelectorAll("button")].find((b) =>
    (b.title || "").startsWith("Language:")
  );
  btn.click();
});
await page.waitForSelector("text=MFA 报表", { timeout: 15000 });
await page.waitForTimeout(1500);

texts = await page.evaluate(visibleTexts);
record("B1 ZH 标题 MFA 报表", texts.includes("MFA 报表"));
record("B2 ZH 树导航 身份与访问", texts.includes("身份与访问"));
record("B3 ZH 树导航 MFA 报表 选中项", texts.includes("MFA 报表"));
record("B4 ZH 列头 账户已启用/已授权/是管理员", texts.includes("账户已启用") && texts.includes("已授权") && texts.includes("是管理员"));
record("B5 ZH 列头 MFA 注册状态/条件访问策略", texts.includes("MFA 注册状态") && texts.includes("条件访问策略"));
record("B6 ZH 后无英文列头残留 (Account Enabled)", !texts.includes("Account Enabled"));

// ── C. 行内动作菜单（第一行 action 按钮 → ZH label） ─────────────────────
await closeDialogs();
const actionBtn = page.locator("table tbody tr").first().locator("button").last();
await actionBtn.click();
await page.waitForTimeout(800);
texts = await page.evaluate(visibleTexts);
record("C1 ZH 动作 设置每用户 MFA", texts.includes("设置每用户 MFA"));
record("C2 ZH 动作 重新要求 MFA 注册", texts.includes("重新要求 MFA 注册"));
await page.keyboard.press("Escape");
await page.waitForTimeout(400);

// ── D. 持久化：刷新后中文保持 ────────────────────────────────────────────
await page.reload({ waitUntil: "domcontentloaded" });
await page.waitForTimeout(2500);
texts = await page.evaluate(visibleTexts);
const storedLang = await page.evaluate(() => window.localStorage.getItem("app.language"));
record("D1 localStorage app.language=zh-CN", storedLang === "zh-CN", storedLang);
record("D2 刷新后 ZH 标题保持 MFA 报表", texts.includes("MFA 报表"));
record("D3 刷新后 ZH 列头保持", texts.includes("账户已启用"));

// ── E. 树导航切换报告 → 标题随注册表切换 ─────────────────────────────────
await closeDialogs();
await page.evaluate(() => {
  const item = [...document.querySelectorAll(".MuiListItemButton-root")].find((el) =>
    (el.textContent ?? "").includes("非活跃用户报表")
  );
  item?.click();
});
await page.waitForTimeout(2000);
texts = await page.evaluate(visibleTexts);
record("E1 树切换 → ZH 标题 非活跃用户报表", texts.includes("非活跃用户报表"));

const failed = results.filter((r) => !r.ok).length;
console.log(failed === 0 ? `\nALL ${results.length} PASS ✅` : `\n${failed}/${results.length} FAILED ❌`);
await page.screenshot({ path: "docs/screenshots-phase3/shot-report-center-batch3-zh.png", fullPage: false });
await browser.close();
process.exit(failed === 0 ? 0 : 1);
