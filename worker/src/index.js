const styles = `
:root {
  --bg: #f4f4f2;
  --surface: #ffffff;
  --text: #16161a;
  --muted: #5c5c66;
  --border: #dcdcd6;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #111113;
    --surface: #1b1b1f;
    --text: #ececef;
    --muted: #9a9aa3;
    --border: #2c2c32;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  background: var(--bg);
  color: var(--text);
  font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
a { color: inherit; }
.site-header {
  padding: 16px;
  font-weight: 700;
  letter-spacing: 0.08em;
}
.site-header__link { text-decoration: none; }
.clip {
  flex: 1;
  width: 100%;
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 16px 32px;
}
.clip__media {
  display: block;
  width: 100%;
  max-height: 78vh;
  object-fit: contain;
  background: #000;
  border-radius: 6px;
}
.clip__details {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 16px;
  justify-content: space-between;
  margin-top: 12px;
  color: var(--muted);
  font-size: 14px;
}
.clip__download { color: var(--text); }
.clip__missing { padding: 64px 0; text-align: center; }
.page {
  flex: 1;
  width: 100%;
  max-width: 680px;
  margin: 0 auto;
  padding: 32px 16px 48px;
}
.page__title { margin: 0 0 16px; font-size: 28px; }
.page p, .page li { color: var(--muted); }
.site-footer {
  display: flex;
  gap: 16px;
  padding: 16px;
  border-top: 1px solid var(--border);
  font-size: 14px;
  color: var(--muted);
}
.cookie-banner {
  position: fixed;
  left: 16px;
  right: 16px;
  bottom: 16px;
  max-width: 520px;
  margin: 0 auto;
  display: flex;
  gap: 12px;
  align-items: center;
  padding: 12px 16px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 6px;
  font-size: 14px;
}
.cookie-banner[hidden] { display: none; }
.cookie-banner__button {
  flex-shrink: 0;
  padding: 6px 14px;
  border: 1px solid var(--border);
  border-radius: 4px;
  background: var(--text);
  color: var(--bg);
  font: inherit;
  cursor: pointer;
}
`;

const cookieScript = `
const banner = document.querySelector(".cookie-banner");
try {
  if (!localStorage.getItem("cookieConsent")) banner.hidden = false;
} catch {
  banner.hidden = false;
}
banner.querySelector("button").addEventListener("click", () => {
  try { localStorage.setItem("cookieConsent", "accepted"); } catch {}
  banner.hidden = true;
});
`;

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

function formatSize(bytes) {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(1)} MB`;
  return `${Math.ceil(bytes / 1e3)} KB`;
}

function page({ title, head = "", main }) {
  return `<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
${head}
<style>${styles}</style>
</head>
<body>
<header class="site-header"><a class="site-header__link" href="/">FLINT</a></header>
${main}
<footer class="site-footer">
<a href="/clip/privacy">Privacy Policy</a>
<a href="/clip/terms">Terms of Service</a>
</footer>
<aside class="cookie-banner" hidden>
<p>This page stores one preference in your browser to remember this notice. No tracking or advertising cookies are used.</p>
<button class="cookie-banner__button" type="button">OK</button>
</aside>
<script>${cookieScript}</script>
</body>
</html>`;
}

function renderViewer({ id, fileURL, pageURL, contentType, uploaded, size }) {
  const isVideo = contentType.startsWith("video/");
  const title = isVideo ? "Clip" : "Screenshot";
  const date = uploaded.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });

  // Discord, iMessage and Slack read these tags to embed the clip inline.
  const meta = isVideo
    ? `<meta property="og:type" content="video.other">
<meta property="og:video" content="${fileURL}">
<meta property="og:video:secure_url" content="${fileURL}">
<meta property="og:video:type" content="video/mp4">
<meta property="og:video:width" content="1920">
<meta property="og:video:height" content="1080">
<meta name="twitter:card" content="player">`
    : `<meta property="og:type" content="website">
<meta property="og:image" content="${fileURL}">
<meta name="twitter:card" content="summary_large_image">`;

  const media = isVideo
    ? `<video class="clip__media" src="${fileURL}" controls playsinline preload="metadata"></video>`
    : `<img class="clip__media" src="${fileURL}" alt="Shared screenshot">`;

  const html = page({
    title: `${title} ${id}`,
    head: `<meta property="og:title" content="${title} shared from Ember">
<meta property="og:url" content="${pageURL}">
${meta}`,
    main: `<main class="clip">
${media}
<p class="clip__details">
<span>Shared ${escapeHtml(date)} &middot; ${formatSize(size)}</span>
<a class="clip__download" href="${fileURL}" download="${title.toLowerCase()}-${id}">Download</a>
</p>
</main>`,
  });

  return htmlResponse(html);
}

function htmlResponse(html, status = 200) {
  return new Response(html, { status, headers: { "Content-Type": "text/html; charset=utf-8" } });
}

function renderNotFound() {
  return htmlResponse(page({
    title: "Clip not found",
    main: `<main class="clip"><p class="clip__missing">This link is wrong or the clip has been removed.</p></main>`,
  }), 404);
}

function renderHome() {
  return htmlResponse(page({
    title: "Ember",
    main: `<main class="page">
<h1 class="page__title">Ember</h1>
<p>Ember is a Mac app that keeps the last few seconds of your screen so you can save a clip after something happens. Clips and screenshots shared from it are hosted here.</p>
<p>Nothing is uploaded unless someone presses Copy Link on a capture.</p>
</main>`,
  }));
}

function renderPrivacy() {
  return htmlResponse(page({
    title: "Privacy Policy",
    main: `<main class="page">
<h1 class="page__title">Privacy Policy</h1>
<p>This site stores the clips and screenshots that Ember users choose to share, and serves them to anyone with the link.</p>
<ul>
<li>No accounts, analytics, advertising or tracking cookies.</li>
<li>Your browser keeps one local setting so the cookie notice is only shown once.</li>
<li>Cloudflare, which hosts this site, may keep standard request logs such as IP addresses for security.</li>
<li>To have a shared clip removed, ask the person who sent you the link.</li>
</ul>
</main>`,
  }));
}

function renderTerms() {
  return htmlResponse(page({
    title: "Terms of Service",
    main: `<main class="page">
<h1 class="page__title">Terms of Service</h1>
<ul>
<li>Only share captures you have the right to share.</li>
<li>Illegal, abusive or infringing uploads are removed when reported.</li>
<li>Clips are kept without an expiry date, but the service is provided as is with no guarantee it stays available.</li>
</ul>
</main>`,
  }));
}

const allowedTypes = ["image/png", "video/mp4"];
const maxUploadBytes = 100 * 1000 * 1000;
const idAlphabet = "abcdefghjkmnpqrstuvwxyz23456789";

function makeId(length = 8) {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (b) => idAlphabet[b % idAlphabet.length]).join("");
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function isAuthorised(request, env) {
  if (!env.UPLOAD_TOKEN) return false;
  const header = request.headers.get("Authorization") ?? "";
  const expected = `Bearer ${env.UPLOAD_TOKEN}`;
  if (header.length !== expected.length) return false;

  const a = new TextEncoder().encode(header);
  const b = new TextEncoder().encode(expected);
  return crypto.subtle.timingSafeEqual(a, b);
}

async function upload(request, env) {
  if (!isAuthorised(request, env)) return json({ error: "The upload token is wrong. Check it in Ember's Settings." }, 401);

  const contentType = request.headers.get("Content-Type") ?? "";
  if (!allowedTypes.includes(contentType)) {
    return json({ error: "Only PNG screenshots and MP4 clips can be shared" }, 400);
  }
  const size = Number(request.headers.get("Content-Length"));
  if (!size) return json({ error: "Missing file" }, 411);
  if (size > maxUploadBytes) return json({ error: "File is over 100 MB" }, 413);

  let id = makeId();
  while (await env.CLIPS.head(id)) id = makeId();

  await env.CLIPS.put(id, request.body, { httpMetadata: { contentType } });

  const origin = new URL(request.url).origin;
  return json({ shareURL: `${origin}/clip/${id}` });
}

async function serveFile(id, request, env) {
  const object = await env.CLIPS.get(id, {
    range: request.headers,
    onlyIf: request.headers,
  });
  if (!object) return new Response("Not found", { status: 404 });

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("ETag", object.httpEtag);
  headers.set("Accept-Ranges", "bytes");
  headers.set("Cache-Control", "public, max-age=86400");

  if (!("body" in object)) return new Response(null, { status: 304, headers });

  // Browsers seek through video with Range requests, so partial reads need a
  // proper 206 or Safari refuses to play the file at all.
  if (object.range && request.headers.has("Range")) {
    const { offset = 0, length = object.size - offset } = object.range;
    headers.set("Content-Range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set("Content-Length", String(length));
    return new Response(object.body, { status: 206, headers });
  }

  headers.set("Content-Length", String(object.size));
  return new Response(object.body, { headers });
}

async function serveViewer(id, request, env) {
  const object = await env.CLIPS.head(id);
  if (!object) return renderNotFound();

  const origin = new URL(request.url).origin;
  return renderViewer({
    id,
    fileURL: `${origin}/clip/${id}/file`,
    pageURL: `${origin}/clip/${id}`,
    contentType: object.httpMetadata?.contentType ?? "application/octet-stream",
    uploaded: object.uploaded,
    size: object.size,
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);

    if (parts[0] === "clip" && parts[1] === "upload") {
      if (request.method !== "PUT") return new Response("Method not allowed", { status: 405 });
      return upload(request, env);
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405 });
    }

    // The Worker only runs on flint.men/clip*, so the rest of the site is left alone.
    if (parts[0] !== "clip") return renderNotFound();
    if (parts.length === 1) return renderHome();
    if (parts[1] === "privacy" && parts.length === 2) return renderPrivacy();
    if (parts[1] === "terms" && parts.length === 2) return renderTerms();
    if (!/^[a-z0-9]{8}$/.test(parts[1])) return renderNotFound();
    if (parts[2] === "file") return serveFile(parts[1], request, env);
    return serveViewer(parts[1], request, env);
  },
};
