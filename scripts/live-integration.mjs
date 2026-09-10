#!/usr/bin/env node
/**
 * ② 真实租户联调 — B1–B3 数据列 + 执行链就绪检查（对生产 CIPP API）
 *
 * 用法:
 *   node scripts/live-integration.mjs --tenant <domain> [--base <url>] [--json <out>]
 *
 * 示例:
 *   node scripts/live-integration.mjs --tenant lenitech.onmicrosoft.com
 *   node scripts/live-integration.mjs --tenant lenitech.onmicrosoft.com --base https://mtm.cxty.de
 *
 * 检查项（全部只读，不触发任何破坏性动作）:
 *   A. ListTenants 概览（租户数 / GDAP 状态 / Graph 错误）
 *   B. 39 份注册表报告逐一联调（镜像 CippDataTable 真实请求链: axios GET + params）:
 *      - ListX 报告: GET <url>?tenantFilter=X[&apiData...] → 状态/形态/行数/列匹配
 *      - ListX+ReportDB 报告: 追加 &UseReportDB=true 验证缓存直读
 *      - DBCache 报告: GET /api/ListDBCache?tenantFilter=X&type=C → Results 行数
 *   C. B3 行内动作端点存在性: 对注册表引用的 /api/Exec* 发 OPTIONS 探测
 *      （405/200 = 端点存在；404 = 缺端点。不发 POST，不执行动作）
 *
 * 注意:
 *   - 生产 API 位于 Cloudflare/nginx 之后，须携带浏览器 UA（否则 CF 1010 拦截）
 *   - nginx 限流 10 r/s → 顺序请求 + 250ms 间隔
 *   - EXO 类端点可能很慢 → 单请求超时 90s
 */
import { execFileSync } from "node:child_process";
import { writeFileSync, readFileSync } from "node:fs";
import path from "node:path";

// ── 参数 ────────────────────────────────────────────────────────
const args = process.argv.slice(2);
function argOf(name, def) {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
}
const BASE = argOf("--base", "https://mtm.cxty.de");
const TENANT = argOf("--tenant", "");
const JSON_OUT = argOf("--json", "");
const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
const DELAY_MS = Number(argOf("--delay", "250"));
const TIMEOUT_S = Number(argOf("--timeout", "90"));

if (!TENANT) {
  console.error("用法: node scripts/live-integration.mjs --tenant <domain> [--base <url>]");
  process.exit(1);
}

// ── 注册表（从 report-registry.js 提取，避免 import ESM 依赖前端构建链）──
// 直接读取源文件并解析（无 JSX，纯数据）——比手工维护副本更不易漂移
function loadRegistry() {
  const src = readFileSync(
    path.resolve(import.meta.dirname, "..", "frontend", "src", "data", "report-registry.js"),
    "utf8"
  );
  // 报告条目在 `export const REPORTS = [...]`；去掉注释后 eval 该数组
  const m = src.match(/export const REPORTS = (\[[\s\S]*?\n\])/);
  if (!m) throw new Error("无法解析 report-registry.js 的 REPORTS 数组");
  // 提供注册表源文件中的两个 helper stub（ListX / DBCache，定义在 REPORTS 之前）
  const noComments = m[1].replace(/^\s*\/\/.*$/gm, "");
  // eslint-disable-next-line no-new-func
  return new Function(
    "ListX",
    "DBCache",
    `return ${noComments}`
  )(
    (url, extra = {}) => ({ type: "ListX", url, ...extra }),
    (cache) => ({ type: "DBCache", cache })
  );
}
const REPORTS = loadRegistry();

// ── HTTP（curl 子进程，绕过 CF TLS 指纹拦截）──────────────────
function httpGet(url) {
  const t0 = Date.now();
  try {
    const stdout = execFileSync(
      "curl",
      [
        "-s",
        "-S",
        "-A",
        UA,
        "-H",
        "Accept: application/json",
        "-H",
        `Referer: ${BASE}/`,
        "--max-time",
        String(TIMEOUT_S),
        "-w",
        "\n__HTTP__%{http_code}",
        url,
      ],
      { encoding: "utf8", maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] }
    );
    const i = stdout.lastIndexOf("\n__HTTP__");
    const body = stdout.slice(0, i);
    const status = Number(stdout.slice(i + 9).trim());
    return { status, body, ms: Date.now() - t0 };
  } catch (err) {
    const stderr = err.stderr ? String(err.stderr).slice(0, 200) : "";
    return { status: 0, body: "", ms: Date.now() - t0, error: `${stderr || err.message}`.slice(0, 160) };
  }
}
function httpOptions(url) {
  // CF/nginx 可能拒绝 OPTIONS；改用 GET 探测：404 = 缺端点，其余状态 = 存在
  const r = httpGet(url);
  return r.status;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── 解析响应形态 ───────────────────────────────────────────────
function parseBody(body) {
  try {
    return JSON.parse(body);
  } catch {
    return null;
  }
}
function describeShape(data) {
  if (Array.isArray(data)) return { shape: "array", rows: data };
  if (data && Array.isArray(data.Results)) return { shape: "Results", rows: data.Results };
  if (data && Array.isArray(data.Results?.Results)) return { shape: "Results.Results", rows: data.Results.Results };
  if (data && typeof data === "object") {
    // 某些端点直接返回单对象或 { Key: [...] } 形态
    for (const [k, v] of Object.entries(data)) {
      if (Array.isArray(v)) return { shape: `object.${k}`, rows: v };
    }
    return { shape: "object", rows: data ? [data] : [] };
  }
  return { shape: "unknown", rows: [] };
}

// ── 镜像 CippDataTable 请求链: axios GET + params（query string）──
function buildReportUrl(report, { useReportDB = false } = {}) {
  const u = new URL(BASE + report.apiUrl);
  u.searchParams.set("tenantFilter", TENANT);
  // apiData 逐键展开为 query param（axios params 行为一致）
  const apiData = reportToTableApiData(report);
  if (report.source?.type === "DBCache") u.searchParams.set("type", report.source.cache);
  for (const [k, v] of Object.entries(apiData)) {
    if (v !== undefined && v !== null) u.searchParams.set(k, String(v));
  }
  if (useReportDB) u.searchParams.set("UseReportDB", "true");
  return u.toString();
}
// 注册表 source 形态: ListX('/api/...', { apiData: {...} }) → 提取 apiData
function reportToTableApiData(report) {
  const s = report.source;
  if (!s) return {};
  if (s.apiData) return s.apiData;
  return {};
}
function reportCacheName(report) {
  const s = report.source;
  if (s?.type === "DBCache") return s.cache;
  if (s?.useReportDB?.cacheName) return s.useReportDB.cacheName;
  if (report.syncCache) return report.syncCache;
  return null;
}

// ── 主流程 ─────────────────────────────────────────────────────
const results = [];
function record(entry) {
  results.push(entry);
  const mark = { PASS: "✅", EMPTY: "⚠️ ", DATAKEY: "🧩", FAIL: "❌", SKIP: "⏭️ " }[entry.mark] || "  ";
  console.log(
    `${mark} [${entry.id}] ${entry.nameEn}  →  ${entry.detail}` +
      (entry.columnsMatch !== undefined ? `  | 列匹配: ${entry.columnsMatch}` : "")
  );
}

console.log(`\n════════════════════════════════════════════════════`);
console.log(`② 真实租户联调  base=${BASE}  tenant=${TENANT}`);
console.log(`════════════════════════════════════════════════════\n`);

// A. 租户概览
console.log("── A. 租户概览 ──");
{
  const r = httpGet(`${BASE}/api/ListTenants`);
  const data = parseBody(r.body);
  if (Array.isArray(data)) {
    const me = data.find((t) => [t.defaultDomainName, t.initialDomainName, t.customerId].includes(TENANT));
    if (!me) {
      console.log(`❌ 租户 ${TENANT} 不在 ListTenants 返回中（共 ${data.length} 租户）`);
    } else {
      console.log(
        `✅ 租户命中: ${me.displayName} | GDAP=${me.delegatedPrivilegeStatus || "(无)"} | 累积Graph错误=${me.GraphErrorCount}`
      );
    }
    record({ id: "_overview", nameEn: `ListTenants (${data.length} tenants)`, mark: "PASS", detail: `${data.length} 租户` });
  } else {
    record({ id: "_overview", nameEn: "ListTenants", mark: "FAIL", detail: `HTTP ${r.status} (非数组)` });
  }
}
await sleep(DELAY_MS);

// B. 逐报告联调
console.log(`\n── B. 报告数据列联调（${REPORTS.length} 份）──`);
const perReport = [];
for (const report of REPORTS) {
  const s = report.source;
  const cacheName = reportCacheName(report);

  if (s?.type === "DBCache") {
    // DBCache: /api/ListDBCache?tenantFilter=&type=
    const url = buildReportUrl({ ...report, apiUrl: "/api/ListDBCache", source: { ...s, type: "DBCache", cache: s.cache } });
    const r = httpGet(url);
    const data = parseBody(r.body);
    const { shape, rows } = describeShape(data);
    const n = Array.isArray(rows) ? rows.length : 0;
    const isResults = shape === "Results" || shape === "array";
    const mark = r.status !== 200 ? "FAIL" : n > 0 ? (isResults ? "PASS" : "DATAKEY") : "EMPTY";
    const detail =
      r.status !== 200
        ? `HTTP ${r.status} ${r.error || r.body.slice(0, 60)}`
        : `HTTP 200 形态=${shape} 行数=${n}` + (n === 0 ? "（缓存空 → 需 ExecCIPPDBCache 同步或服务器 Sync-AllCache）" : "");
    record({ id: report.id, nameEn: report.nameEn, kind: "DBCache", cache: s.cache, mark, detail, rows: n, httpStatus: r.status, shape });
  } else if (s?.url) {
    // ListX（含 useReportDB 变体）
    for (const mode of s.useReportDB ? [false, true] : [false]) {
      // mode=false 在线直读；mode=true UseReportDB=true 缓存直读
      const url = buildReportUrl({ ...report, apiUrl: s.url }, { useReportDB: mode });
      const r = httpGet(url);
      const data = parseBody(r.body);
      const { shape, rows } = describeShape(data);
      const n = Array.isArray(rows) ? rows.length : 0;
      // 列匹配: 注册表 columns 与行字段交集
      let colsMatch = "";
      if (n > 0 && Array.isArray(rows[0]) === false && typeof rows[0] === "object" && rows[0]) {
        const keys = new Set(Object.keys(rows[0]));
        const cols = report.columns ?? [];
        if (cols.length > 0) {
          const hit = cols.filter((c) => keys.has(c) || keys.has(c.split(".")[0]));
          colsMatch = `${hit.length}/${cols.length}`;
        }
      }
      const modeTag = mode ? "+UseReportDB" : "";
      const mark = r.status !== 200 ? "FAIL" : n > 0 ? "PASS" : shape === "unknown" ? "FAIL" : "EMPTY";
      const detail =
        r.status !== 200
          ? `HTTP ${r.status} ${r.error || r.body.slice(0, 60)}`
          : `HTTP 200 形态=${shape} 行数=${n}${modeTag}`;
      record({ id: report.id, nameEn: report.nameEn + modeTag, kind: "ListX", mark, detail, rows: n, httpStatus: r.status, shape, columnsMatch: colsMatch });
      await sleep(DELAY_MS);
    }
  } else {
    record({ id: report.id, nameEn: report.nameEn, kind: "?", mark: "SKIP", detail: "注册表条目无 source.url / DBCache（跳过）" });
  }
  perReport.push(results[results.length - 1]);
}

// C. B3 动作端点存在性（OPTIONS 探测，不发 POST）
console.log("\n── C. B3 行内动作端点存在性（OPTIONS 探测）──");
const execEndpoints = new Set();
for (const report of REPORTS) {
  const acts = [];
  const ra = report.rowActions;
  if (Array.isArray(ra)) acts.push(...ra.filter((a) => a.url));
  if (ra?.preset) {
    // preset: user / device —— 引用既有 hook 的权威 action 集，不在此展开（只校验内联自定义端点）
  }
  for (const a of acts) execEndpoints.add(a.url);
}
{
  const out = [];
  for (const url of [...execEndpoints].sort()) {
    const st = httpOptions(BASE + url);
    const exists = st > 0 && st !== 404;
    const mark = exists ? "✅" : "❌";
    console.log(`${mark} GET 探测 ${url} → ${st || "无响应"}${exists ? "（端点存在）" : "（端点缺失！）"}`);
    out.push({ url, status: st, exists });
    await sleep(DELAY_MS);
  }
  record({ id: "_execEndpoints", nameEn: `Exec 端点探测 (${out.length})`, mark: out.every((e) => e.exists) ? "PASS" : "FAIL", detail: out.map((e) => `${e.url.split("/").pop()}=${e.status}`).join(" ") });
  results.push({ _execEndpointDetail: out });
}

// D. 汇总
const summary = results.filter((r) => r.mark);
const pass = summary.filter((r) => r.mark === "PASS").length;
const empty = summary.filter((r) => r.mark === "EMPTY").length;
const fail = summary.filter((r) => r.mark === "FAIL").length;
const datakey = summary.filter((r) => r.mark === "DATAKEY").length;
console.log(`\n══ 汇总 ══`);
console.log(`✅ PASS(有数据): ${pass}   ⚠️ EMPTY(空数据/缓存未同步): ${empty}   🧩 DATAKEY(包裹形态): ${datakey}   ❌ FAIL: ${fail}`);

if (JSON_OUT) {
  writeFileSync(JSON_OUT, JSON.stringify({ base: BASE, tenant: TENANT, at: new Date().toISOString(), results }, null, 2));
  console.log(`\n结果已写入: ${JSON_OUT}`);
}
process.exit(fail > 0 ? 2 : 0);
