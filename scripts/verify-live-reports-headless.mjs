#!/usr/bin/env node
/**
 * ② 真实租户联调 — 前端无头 E2E（报告中心 + 生产真实数据）
 *
 * 前置:
 *   1. frontend/out 已构建
 *   2. CIPP_API_ORIGIN=https://mtm.cxty.de node scripts/dev-serve.mjs
 *   3. LIVE_TENANT=<domain> node scripts/verify-live-reports-headless.mjs
 *
 * 设计: 确定性等待 —— 每个断言前等待「目标 API 响应」与「期望文本出现」，
 *       不用固定时长采样（修复跨页导航骨架态/分页页脚渲染时序 flake）。
 * 全程只读（打开菜单 DOM，不发 POST）。
 */
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const TENANT = process.env.LIVE_TENANT || "lenitech.onmicrosoft.com";
const BASE = "http://localhost:3000";

function resolvePlaywright() {
  try {
    return require.resolve("playwright-core");
  } catch {}
  const candidates = [
    path.resolve(import.meta.dirname, "..", "frontend", "node_modules", "playwright-core"),
  ];
  try {
    const globalDir = execFileSync("npm.cmd", ["root", "-g"], { encoding: "utf8" }).trim();
    candidates.push(path.join(globalDir, "playwright-core"));
    candidates.push(path.join(globalDir, "node_modules", "playwright-core"));
  } catch {}
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  throw new Error("playwright-core 不可用 —— 复跑 E2E 前需重装: cd frontend && npm i --no-save playwright-core");
}
const { chromium } = require(resolvePlaywright());

const results = [];
function record(name, pass, detail = "") {
  results.push({ name, pass, detail });
  console.log(`${pass ? "✅ PASS" : "❌ FAIL"}  ${name}${detail ? `  (${detail})` : ""}`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let page;

// 等待 body 文本包含 str（确定性断言原语；ignoreCase 用于 CSS uppercase 的树分类标签）
async function waitText(str, timeout = 20000, { ignoreCase = false } = {}) {
  const needle = ignoreCase ? str.toLowerCase() : str;
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const text = await page.locator("body").innerText().catch(() => "");
    const hay = ignoreCase ? text.toLowerCase() : text;
    if (hay.includes(needle)) return true;
    await sleep(500);
  }
  return false;
}

// 打开报告页: 注入租户/语言 → 等目标 API 响应 → 等表格稳定（行文本签名连续两次一致）
async function openReport(service, reportId, { apiHint, lang = "en" } = {}) {
  await page.goto(BASE, { waitUntil: "domcontentloaded", timeout: 30000 });
  await page.evaluate(({ t, l }) => {
    localStorage.setItem("app.language", l);
    const settings = JSON.parse(localStorage.getItem("app.settings") || "{}");
    settings.currentTenant = t;
    localStorage.setItem("app.settings", JSON.stringify(settings));
  }, { t: TENANT, l: lang });
  const respP = page
    .waitForResponse(
      (r) =>
        r.url().includes("/api/") &&
        r.request().method() === "GET" &&
        (!apiHint || r.url().includes(apiHint)),
      { timeout: 60000 }
    )
    .catch(() => null);
  await page.goto(`${BASE}/reports/${service}/${reportId}`, { waitUntil: "domcontentloaded", timeout: 30000 });
  await respP;
  await sleep(1200);
  // 行文本签名稳定（防骨架态/过渡态）
  let prev = null;
  for (let i = 0; i < 12; i++) {
    await sleep(1000);
    const rows = await page.locator("table tbody tr").count();
    const first = rows > 0 ? await page.locator("table tbody tr").first().innerText().catch(() => "") : "";
    const sig = `${rows}|${first}`;
    if (sig === prev && (rows > 0 || i >= 4)) break;
    prev = sig;
  }
  return page;
}

async function main() {
  const browser = await chromium.launch({
    channel: "chrome",
    headless: true,
    args: ["--disable-blink-features=AutomationControlled", "--no-sandbox"],
  });
  page = await browser.newPage({ viewport: { width: 1600, height: 950 } });

  const consoleErrors = [];
  page.on("console", (msg) => {
    if (msg.type() === "error") consoleErrors.push(msg.text().slice(0, 200));
  });
  page.on("pageerror", (err) => consoleErrors.push(`pageerror: ${String(err).slice(0, 200)}`));

  // ── 基线（第一批） ──────────────────────────────
  await openReport("identity", "mfa-state", { apiHint: "ListMFAUsers" });
  let rows = await page.locator("table tbody tr").count();
  record("mfa-state 渲染真实数据", rows >= 5, `行数=${rows} 租户=${TENANT}`);
  record("mfa-state 列头命中（真实字段）", await waitText("UPN"), "");

  await openReport("identity", "users-cache", { apiHint: "ListDBCache" });
  rows = await page.locator("table tbody tr").count();
  record("users-cache（DBCache 行数据 + Results 解包修复）", rows >= 5, `行数=${rows}`);

  await openReport("identity", "groups-cache", { apiHint: "ListDBCache" });
  rows = await page.locator("table tbody tr").count();
  record("groups-cache 渲染", rows >= 3, `行数=${rows}`);

  await openReport("endpoint", "managed-devices-cache", { apiHint: "ListDBCache" });
  rows = await page.locator("table tbody tr").count();
  const mdText = await page.locator("body").innerText();
  record("managed-devices-cache（单对象退化形态）正常渲染", rows >= 0 && !mdText.includes("Error Loading"), `行数=${rows}`);

  await openReport("email", "cas-mailboxes-cache", { apiHint: "ListDBCache" });
  // 生产该类型 Results=null → 归一化后为 MRT 空状态（确定性等待空态文本）
  const casEmpty = await waitText("No records to display", 15000);
  record("cas-mailboxes-cache（Results:null 归一化）空状态", casEmpty, casEmpty ? "" : "未见空态文本");

  await openReport("security", "conditional-access-cache", { apiHint: "ListDBCache" });
  rows = await page.locator("table tbody tr").count();
  record("conditional-access-cache 渲染", rows >= 1, `行数=${rows}`);

  // ── B3 行内动作菜单（重试 2 次） ────────────────
  await openReport("identity", "mfa-state", { apiHint: "ListMFAUsers" });
  {
    let opened = false;
    let menuItems = 0;
    for (let attempt = 0; attempt < 2 && !opened; attempt++) {
      try {
        await page.locator("table tbody tr").first().waitFor({ timeout: 10000 });
        const actionBtn = page.locator('button[aria-label="Row Actions"]').first();
        await actionBtn.scrollIntoViewIfNeeded();
        await actionBtn.click({ timeout: 6000, force: attempt === 1 });
        await sleep(1000);
        menuItems = await page.locator('[role="menuitem"], [role="menu"] li').count();
        opened = menuItems > 0;
      } catch {}
      if (!opened) {
        await page.keyboard.press("Escape");
        await openReport("identity", "mfa-state", { apiHint: "ListMFAUsers" });
      }
    }
    record("mfa-state 行内动作菜单可打开（B3 菜单渲染）", opened, opened ? `菜单项=${menuItems}` : "");
    await page.keyboard.press("Escape");
  }

  // ── ZH 语言切换（Phase 3 回归） ────────────────
  await page.evaluate(() => localStorage.setItem("app.language", "zh-CN"));
  await page.reload({ waitUntil: "domcontentloaded" });
  const zhOk = (await waitText("MFA 报表", 15000)) || (await waitText("筛选", 3000)) || (await waitText("每页行数", 3000));
  record("ZH 语言切换（MFA 报表标题）", zhOk, "");

  // ── 第二批扩充（AdminDroid 对标） ────────────────
  await openReport("identity", "service-principals-cache", { apiHint: "ListDBCache" });
  const spOk = await waitText("293", 15000); // MRT 分页页脚总数
  record("第二批: service-principals-cache（293 企业应用）", spOk, spOk ? "" : "分页总数 293 未出现");

  await openReport("security", "secure-score-controls-cache", { apiHint: "ListDBCache" });
  const ctrlOk = (await waitText("460", 15000)) && (await waitText("Control Category", 5000));
  record("第二批: secure-score-controls-cache（460 控制项 + 精选列）", ctrlOk, "");

  await openReport("identity", "user-registration-details-cache", { apiHint: "ListDBCache" });
  const regOk = await waitText("MFA", 10000);
  record("第二批: user-registration-details-cache（精选列）", regOk, "");

  // 新分类树: 树只展开当前服务 → 分别在两个服务的报告页断言
  await openReport("identity", "roles-cache", { apiHint: "ListDBCache", lang: "zh-CN" });
  const treeId = (await waitText("角色与管理员", 10000)) && (await waitText("目录角色（缓存）", 5000));
  record("第二批: identity 树 ZH（角色与管理员 + 目录角色）", treeId, "");

  await openReport("collab", "office-activations-cache", { apiHint: "ListDBCache", lang: "zh-CN" });
  const treeCollab =
    (await waitText("Office 应用", 10000, { ignoreCase: true })) && (await waitText("Office 激活（缓存）", 5000));
  record("第二批: collab 树 ZH（Office 应用 + Office 激活）", treeCollab, "");

  await page.screenshot({ path: "docs/screenshots-phase3/shot-report-center-batch2-expand-zh.png" });

  // console 错误审计
  const relevant = consoleErrors.filter(
    (e) => !e.includes("favicon") && !e.includes("net::ERR") && !e.includes("Load failed")
  );
  record("console 零严重错误", relevant.length === 0, relevant.length > 0 ? relevant.slice(0, 3).join(" | ") : "");

  await browser.close();

  const pass = results.filter((r) => r.pass).length;
  console.log(`\n══ ${pass}/${results.length} PASS ══`);
  process.exit(pass === results.length ? 0 : 2);
}

main().catch((err) => {
  console.error("E2E fatal:", err);
  process.exit(1);
});
