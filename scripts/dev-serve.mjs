#!/usr/bin/env node
/**
 * Windows 本机体验栈：静态托管 frontend/out + /api 反代到 cipp-server (:7071)。
 *
 * 用法:  node scripts/dev-serve.mjs
 *   前置:  pwsh -File cipp-server.ps1        (后端 API, 端口 7071)
 *   前置:  cd frontend && npm run build      (生成 out/)
 *
 * 浏览器访问 http://localhost:3000
 * 所有 /api 请求自动注入 SWA 风格 x-ms-client-principal 头（superadmin），
 * 与 Phase 1 冒烟验证方式一致 —— 本机免登录体验完整界面。
 */
import http from "node:http";
import { promises as fsp } from "node:fs";
import path from "node:path";

const PORT = Number(process.env.DEV_SERVE_PORT || 3000);
const API_TARGET = process.env.CIPP_API_ORIGIN || "http://127.0.0.1:7071";
const OUT_DIR = path.resolve(import.meta.dirname, "..", "frontend", "out");

// SWA principal: superadmin → /api/me 返回完整权限主体，免登录
const MOCK_PRINCIPAL = Buffer.from(
  JSON.stringify({
    identityProvider: "local",
    userDetails: "admin@local",
    userId: "00000000-0000-0000-0000-000000000001",
    userRoles: ["authenticated", "superadmin"],
  })
).toString("base64");

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".map": "application/json",
  ".txt": "text/plain; charset=utf-8",
  ".webmanifest": "application/manifest+json",
};

async function resolveStaticFile(urlPath) {
  let pathname = decodeURIComponent(urlPath.split("?")[0]);
  if (pathname.endsWith("/")) pathname += "index.html";
  const safe = path.normalize(pathname).replace(/^(\.\.[/\\])+/, "");
  const candidates = [
    path.join(OUT_DIR, safe),
    pathname === "/" ? null : path.join(OUT_DIR, safe + ".html"),
    pathname === "/" ? null : path.join(OUT_DIR, safe, "index.html"),
    path.join(OUT_DIR, "404.html"),
  ].filter(Boolean);
  for (const candidate of candidates) {
    try {
      const stat = await fsp.stat(candidate);
      if (stat.isFile()) return candidate;
    } catch {
      // try next candidate
    }
  }
  return null;
}

function proxyApi(req, res) {
  const headers = { ...req.headers };
  headers.host = new URL(API_TARGET).host;
  if (!headers["x-ms-client-principal"]) {
    headers["x-ms-client-principal"] = MOCK_PRINCIPAL;
  }
  headers["x-forwarded-for"] = headers["x-forwarded-for"] || "127.0.0.1";

  const upstream = new URL(req.url, API_TARGET);
  const proxyReq = http.request(
    upstream,
    { method: req.method, headers },
    (proxyRes) => {
      res.writeHead(proxyRes.statusCode || 502, proxyRes.headers);
      proxyRes.pipe(res);
    }
  );
  proxyReq.on("error", (err) => {
    res.writeHead(503, { "content-type": "application/json; charset=utf-8" });
    res.end(
      JSON.stringify({
        error: "API 不可达 —— 请先启动后端: pwsh -File cipp-server.ps1",
        detail: String(err && err.message),
      })
    );
  });
  req.pipe(proxyReq);
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.url.startsWith("/api/")) {
      return proxyApi(req, res);
    }
    const file = await resolveStaticFile(req.url);
    if (!file) {
      res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      return res.end("404");
    }
    const body = await fsp.readFile(file);
    res.writeHead(200, {
      "content-type": MIME[path.extname(file).toLowerCase()] || "application/octet-stream",
      "cache-control": file.includes(`${path.sep}_next${path.sep}`)
        ? "public, max-age=31536000, immutable"
        : "no-cache",
    });
    res.end(body);
  } catch (err) {
    res.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
    res.end(String(err && err.message));
  }
});

server.listen(PORT, () => {
  console.log(`[dev-serve] http://localhost:${PORT}  (静态: ${OUT_DIR})`);
  console.log(`[dev-serve] /api/* → ${API_TARGET}  (注入 superadmin principal)`);
});
