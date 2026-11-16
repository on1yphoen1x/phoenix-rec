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

function page({ siteURL, title, head = "", main }) {
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
<header class="site-header"><a class="site-header__link" href="${siteURL}">PHOENIX</a></header>
${main}
<footer class="site-footer">
<a href="${siteURL}/privacy">Privacy Policy</a>
<a href="${siteURL}/terms">Terms of Service</a>
</footer>
<aside class="cookie-banner" hidden>
<p>This page stores one preference in your browser to remember this notice. No tracking or advertising cookies are used.</p>
<button class="cookie-banner__button" type="button">OK</button>
</aside>
<script>${cookieScript}</script>
</body>
</html>`;
}

export function renderViewer({ siteURL, id, fileURL, pageURL, contentType, uploaded, size }) {
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
    siteURL,
    title: `${title} ${id}`,
    head: `<meta property="og:title" content="${title} shared from Phoenix">
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

  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

export function renderNotFound(siteURL) {
  const html = page({
    siteURL,
    title: "Clip not found",
    main: `<main class="clip"><p class="clip__missing">This link is wrong or the clip has been removed.</p></main>`,
  });
  return new Response(html, { status: 404, headers: { "Content-Type": "text/html; charset=utf-8" } });
}
