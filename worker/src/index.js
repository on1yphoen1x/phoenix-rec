import { AwsClient } from "aws4fetch";
import { renderViewer, renderNotFound } from "./viewer.js";

const allowedTypes = {
  png: "image/png",
  mp4: "video/mp4",
};

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
  const header = request.headers.get("Authorization") ?? "";
  const expected = `Bearer ${env.UPLOAD_TOKEN}`;
  if (header.length !== expected.length) return false;

  const a = new TextEncoder().encode(header);
  const b = new TextEncoder().encode(expected);
  return crypto.subtle.timingSafeEqual(a, b);
}

async function createUpload(request, env) {
  if (!isAuthorised(request, env)) return json({ error: "Unauthorised" }, 401);

  const { extension, contentType, size } = await request.json();
  if (allowedTypes[extension] !== contentType) {
    return json({ error: "Only PNG screenshots and MP4 clips can be shared" }, 400);
  }
  if (Number(size) > Number(env.MAX_UPLOAD_BYTES)) {
    return json({ error: "File is too large to share" }, 413);
  }

  const id = makeId();
  const r2 = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    service: "s3",
    region: "auto",
  });

  const target = new URL(`https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.BUCKET_NAME}/${id}`);
  target.searchParams.set("X-Amz-Expires", "900");

  const signed = await r2.sign(
    new Request(target, { method: "PUT", headers: { "Content-Type": contentType } }),
    { aws: { signQuery: true } }
  );

  const origin = new URL(request.url).origin;
  return json({ uploadURL: signed.url, shareURL: `${origin}/${id}` });
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
  if (!object) return renderNotFound(env.SITE_URL);

  const origin = new URL(request.url).origin;
  return renderViewer({
    siteURL: env.SITE_URL,
    id,
    fileURL: `${origin}/${id}/file`,
    pageURL: `${origin}/${id}`,
    contentType: object.httpMetadata?.contentType ?? "application/octet-stream",
    uploaded: object.uploaded,
    size: object.size,
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const [id, action] = url.pathname.slice(1).split("/");

    if (request.method === "POST" && id === "uploads") return createUpload(request, env);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405 });
    }

    if (!id) return Response.redirect(env.SITE_URL, 302);
    if (!/^[a-z0-9]{8}$/.test(id)) return renderNotFound(env.SITE_URL);
    if (action === "file") return serveFile(id, request, env);
    return serveViewer(id, request, env);
  },
};
