// ============================================================================
// JOGA BONITO — API simulada para os testes ponta a ponta (E2E)
//
// Servidor HTTP da loja de demonstração: serve o site e responde /api e /health
// com o motor Javascript/loja-demo.js — o mesmo que roda no site público.
// O contrato (rotas, códigos HTTP, JSON, regras) espelha a API .NET, para que o
// front-end seja testado com Playwright em qualquer máquina, sem .NET nem SQL Server.
// Os produtos vêm de Javascript/catalogo-local.js (mesma fonte do seed.sql).
//
// Uso:  node Site/tests/e2e/mock-api.js [pastaSite] [porta]
// ============================================================================
"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");

const RAIZ = path.resolve(process.argv[2] || path.join(__dirname, "..", ".."));
const PORTA = Number(process.argv[3] || 5000);

// Mesma política do CabecalhosSegurancaMiddleware.cs
const CSP = [
  "default-src 'self'",
  "script-src 'self' https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/ 'unsafe-eval' 'wasm-unsafe-eval'",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/",
  "font-src 'self' data: https://fonts.gstatic.com https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/",
  "img-src 'self' data: blob: https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/",
  "media-src 'self' blob: https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/",
  "connect-src 'self' https://viacep.com.br https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/",
  "worker-src 'self' blob:",
  "frame-src 'self' https://vlibras.gov.br https://*.vlibras.gov.br https://cdn.jsdelivr.net/gh/spbgovbr-vlibras/",
  "object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self'"
].join("; ");

const fonte = fs.readFileSync(path.join(RAIZ, "Javascript/catalogo-local.js"), "utf8");
const produtos = JSON.parse(fonte.slice(fonte.indexOf("["), fonte.indexOf("\n];") + 2));

const { criarLoja } = require(path.join(RAIZ, "Javascript", "loja-demo.js"));
const loja = criarLoja(produtos);

const TIPOS = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".json": "application/json",
  ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".avif": "image/avif",
  ".gif": "image/gif", ".svg": "image/svg+xml", ".ico": "image/x-icon"
};

http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  let corpo = "";
  req.on("data", c => { corpo += c; if (corpo.length > 1_048_576) req.destroy(); });
  req.on("end", () => {
    const cab = {
      "X-Content-Type-Options": "nosniff", "X-Frame-Options": "SAMEORIGIN",
      "Referrer-Policy": "strict-origin-when-cross-origin", "Content-Security-Policy": CSP
    };
    // CORS igual ao da API em Development: só origens do próprio computador, com cookie de sessão
    const origem = req.headers.origin;
    if (origem && /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(origem)) {
      cab["Access-Control-Allow-Origin"] = origem;
      cab["Access-Control-Allow-Credentials"] = "true";
      cab["Vary"] = "Origin";
    }
    if (req.method === "OPTIONS") {
      if (cab["Access-Control-Allow-Origin"]) {
        cab["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE";
        cab["Access-Control-Allow-Headers"] = "Authorization, Content-Type, X-JB-Requisicao, X-JB-Cliente";
      }
      res.writeHead(204, cab); return res.end();
    }
    const responder = (st, dados) => {
      const texto = typeof dados === "string";
      res.writeHead(st, { ...cab, "Content-Type": texto ? "text/plain" : "application/json" });
      res.end(dados === undefined ? "" : texto ? dados : JSON.stringify(dados));
    };
    try {
      if (!url.pathname.startsWith("/api/") && !url.pathname.startsWith("/health")) {
        const rel = decodeURIComponent(url.pathname === "/" ? "/HTML/inicial.html" : url.pathname);
        const arq = path.join(RAIZ, rel);
        const publico = ["HTML", "CSS", "Javascript", "IMG"].some(d => arq.startsWith(path.join(RAIZ, d) + path.sep));
        if (!publico || !fs.existsSync(arq) || fs.statSync(arq).isDirectory()) { res.writeHead(404, cab); return res.end(); }
        res.writeHead(200, { ...cab, "Content-Type": TIPOS[path.extname(arq)] || "application/octet-stream" });
        return fs.createReadStream(arq).pipe(res);
      }
      const b = corpo ? JSON.parse(corpo) : {};
      const r = loja.pedir({ metodo: req.method, url, corpo: b, cabecalhos: req.headers,
                             ip: req.socket.remoteAddress, host: req.headers.host });
      if (r.cookies.length) res.setHeader("Set-Cookie", r.cookies);
      responder(r.status, r.dados);
    } catch (e) {
      if (Array.isArray(e)) return responder(e[0], e[1] ? { mensagem: e[1] } : undefined);
      console.error(e);
      responder(500, { mensagem: "Erro interno. Tente novamente em instantes." });
    }
  });
}).listen(PORTA, () => console.log(`API simulada em http://localhost:${PORTA} (site: ${RAIZ})`));
