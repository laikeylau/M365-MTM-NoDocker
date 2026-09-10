#!/usr/bin/env node
/**
 * Phase 3 批次 3 字典完整性校验（node 直跑，无需浏览器）。
 *
 * 校验项：
 *  1. 三个 locale JSON 可解析且值非空
 *  2. 报告注册表 nameEn 无重复（i18n/report-name.js 的 Map 查找依赖唯一性）
 *  3. 注册表内联 rowActions 的 label 全部有 common.json 词条
 *  4. 注册表显式 columns 美化后的英文列头全部有 columns.json 词条
 *  5. report-name.js 的注册表查找规模一致（SERVICES + CATEGORIES + REPORTS 全覆盖）
 *
 * 用法: node scripts/verify-i18n-dicts.mjs
 */
import { readFileSync } from "node:fs";
import path from "node:path";

const ROOT = path.resolve(import.meta.dirname, "..");
const I18N = path.join(ROOT, "frontend", "src", "i18n");
const registrySrc = readFileSync(
  path.join(ROOT, "frontend", "src", "data", "report-registry.js"),
  "utf8"
);

let failures = 0;
const check = (ok, label, detail = "") => {
  console.log(`${ok ? "PASS" : "FAIL"}  ${label}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures++;
};

const loadJson = (p) => JSON.parse(readFileSync(p, "utf8"));
const nav = loadJson(path.join(I18N, "locales/zh-CN/nav.json"));
const common = loadJson(path.join(I18N, "locales/zh-CN/common.json"));
const columns = loadJson(path.join(I18N, "locales/zh-CN/columns.json"));

// 1. JSON 非空
for (const [name, dict] of [
  ["nav", nav],
  ["common", common],
  ["columns", columns],
]) {
  const empty = Object.entries(dict).filter(([, v]) => typeof v !== "string" || v.trim() === "");
  check(empty.length === 0, `${name}.json 全部词条非空`, empty.length ? empty.map(([k]) => k).join(", ") : `${Object.keys(dict).length} 词条`);
}

// 2. 注册表 nameEn 唯一性 + nameEn/nameZh 配对完整
const reportBlocks = [...registrySrc.matchAll(/\{\s*id:\s*'([^']+)'[\s\S]*?\n  \},/g)].map((m) => m[0]);
const nameEnSeen = new Map();
let dup = [];
let missingPair = [];
for (const block of reportBlocks) {
  const id = block.match(/id:\s*'([^']+)'/)?.[1];
  const nameEn = block.match(/nameEn:\s*'([^']+)'/)?.[1];
  const nameZh = block.match(/nameZh:\s*'([^']+)'/)?.[1];
  if (!nameEn || !nameZh) missingPair.push(id);
  if (nameEn) {
    if (nameEnSeen.has(nameEn)) dup.push(`${nameEn} (${nameEnSeen.get(nameEn)} / ${id})`);
    nameEnSeen.set(nameEn, id);
  }
}
check(dup.length === 0, "报告/服务 nameEn 无重复", dup.join("; ") || `${nameEnSeen.size} 条`);
check(missingPair.length === 0, "报告 nameEn/nameZh 配对完整", missingPair.join(", ") || "OK");

// 3. 内联 rowActions label → common.json
const inlineLabels = [
  ...registrySrc.matchAll(/rowActions:\s*\[\s*\{[\s\S]*?label:\s*'([^']+)'/g),
].map((m) => m[1]);
const missingLabels = inlineLabels.filter((l) => common[l] === undefined);
check(
  missingLabels.length === 0,
  `内联 rowActions label 已收录 common.json (${inlineLabels.length} 条)`,
  missingLabels.join(", ") || "OK"
);

// 4. 显式 columns 美化键 → columns.json（与 get-cipp-translation.js 美化规则一致）
const beautify = (field) =>
  field
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1 $2")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/(^|\.)(\w)/g, (_, dot, char) => dot + char.toUpperCase())
    .replace(/[_]/g, " ")
    .replace(/\./g, " - ")
    .replace(/([a-z])([A-Z])/g, "$1 $2");

const columnBlocks = [...registrySrc.matchAll(/columns:\s*\[([^\]]*)\]/g)].map((m) =>
  m[1]
    .split(",")
    .map((s) => s.trim().replace(/^'([^']*)'$/, "$1"))
    .filter(Boolean)
);
const allFields = [...new Set(columnBlocks.flat())];
const missingColumns = allFields.map(beautify).filter((k) => columns[k] === undefined);
check(
  missingColumns.length === 0,
  `注册表显式 columns 列头已收录 columns.json (${allFields.length} 字段)`,
  missingColumns.join(", ") || "OK"
);

// 5. report-name.js 查找规模（报告 + 服务 + 分类三类来源都要遍历）
const servicesEn = [...registrySrc.matchAll(/id:\s*'([a-z-]+)',\s*\n\s*nameEn:/g)].length;
const categoriesEn = [...registrySrc.matchAll(/^\s{2}[a-zA-Z]+:\s*\{\s*nameEn:/gm)].length;
const expected = nameEnSeen.size + servicesEn + categoriesEn;
const reportNameSrc = readFileSync(path.join(I18N, "report-name.js"), "utf8");
const hasAllThreeSources =
  /of SERVICES/.test(reportNameSrc) &&
  /of Object\.values\(CATEGORIES\)/.test(reportNameSrc) &&
  /of REPORTS/.test(reportNameSrc);
check(
  hasAllThreeSources,
  `report-name.js 覆盖 SERVICES/CATEGORIES/REPORTS 三类来源（报告 ${nameEnSeen.size - servicesEn} + 服务 ${servicesEn} + 分类 ${categoriesEn}）`
);

// 6. nav.json 报告中心入口
check(nav["Reports"] !== undefined, "nav.json 收录报告中心入口 (Reports)", String(nav["Reports"]));

console.log(failures === 0 ? "\nALL PASS ✅" : `\n${failures} FAILURES ❌`);
process.exit(failures === 0 ? 0 : 1);
