/**
 * Cloudflare Worker (Plan Gratuito — 100.000 req/día) para recibir reportes de bugs
 * desde MacFileExplorer sin pedir cuenta de GitHub al usuario y sin exponer jamás
 * ningún token dentro de la app ni del repositorio.
 *
 * Cómo desplegarlo en 3 minutos cuando quieras activar envío 100% automático:
 * 1. Creá un Fine-Grained Personal Access Token en GitHub con permiso ÚNICAMENTE:
 *      Repository: romeroluisjavier/MacFileExplorer -> Issues: Read and write
 * 2. Creá un Worker gratis en https://dash.cloudflare.com -> Workers & Pages -> Create Worker
 *    y pegá este archivo.
 * 3. En Settings -> Variables and Secrets del Worker agregá el Secret:
 *      GITHUB_TOKEN = <tu_fine_grained_token>
 * 4. Copiá la URL de tu Worker (ej. https://mfe-bug-relay.<tu-subdominio>.workers.dev)
 *    y pegala en `BugReportService.defaultRelayEndpointURL` dentro de Swift.
 */

const REPO_OWNER = "romeroluisjavier";
const REPO_NAME = "MacFileExplorer";
const ALLOWED_LABELS = new Set(["bug", "enhancement", "question", "auto-bug"]);
const MAX_BODY_CHARS = 12000;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json({ ok: false, error: "Method not allowed" }, 405);
    }

    if (!env.GITHUB_TOKEN) {
      return json({ ok: false, error: "Missing GITHUB_TOKEN secret" }, 500);
    }

    const ua = request.headers.get("user-agent") || "";
    if (!ua.startsWith("MacFileExplorer/")) {
      return json({ ok: false, error: "Unsupported client" }, 403);
    }

    let payload;
    try {
      payload = await request.json();
    } catch {
      return json({ ok: false, error: "Invalid JSON" }, 400);
    }

    const title = String(payload.title || "").trim().slice(0, 180);
    const body = String(payload.body || "").trim().slice(0, MAX_BODY_CHARS);
    const fingerprint = payload.fingerprint ? String(payload.fingerprint).replace(/[^a-f0-9]/gi, "").slice(0, 32) : "";
    const labels = Array.isArray(payload.labels)
      ? payload.labels.map(String).filter((l) => ALLOWED_LABELS.has(l))
      : ["bug"];

    if (!title || !body) {
      return json({ ok: false, error: "Title and body are required" }, 400);
    }

    const ghHeaders = {
      "Authorization": `Bearer ${env.GITHUB_TOKEN}`,
      "Accept": "application/vnd.github+json",
      "User-Agent": "MacFileExplorer-BugRelay/1.0",
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json"
    };

    // 1. Deduplicación inteligente: si ya existe un Issue abierto con el mismo fingerprint, agregar un comentario +1.
    if (fingerprint) {
      const q = encodeURIComponent(`repo:${REPO_OWNER}/${REPO_NAME} is:issue is:open "auto-bug-fp:${fingerprint}" in:body`);
      const searchRes = await fetch(`https://api.github.com/search/issues?q=${q}&per_page=1`, { headers: ghHeaders });
      if (searchRes.ok) {
        const searchData = await searchRes.json();
        const existing = searchData.items && searchData.items[0];
        if (existing && existing.number) {
          const commentBody = [
            `+1 reporte adicional coincidente (\`auto-bug-fp:${fingerprint}\`)`,
            `- **Versión:** v${payload.appVersion || "?"}`,
            `- **macOS:** ${payload.macOSVersion || "?"} · ${payload.architecture || "?"}`,
            `- **Tipo:** ${payload.automatic ? "Automático mensual" : "Reporte manual"}`
          ].join("\n");

          const commentRes = await fetch(
            `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues/${existing.number}/comments`,
            { method: "POST", headers: ghHeaders, body: JSON.stringify({ body: commentBody }) }
          );
          if (commentRes.ok) {
            return json({ ok: true, deduplicated: true, issueUrl: existing.html_url }, 200);
          }
        }
      }
    }

    // 2. Crear nuevo Issue en GitHub.
    const finalBody = fingerprint && !body.includes(`auto-bug-fp:${fingerprint}`)
      ? `${body}\n\n<!-- auto-bug-fp:${fingerprint} -->`
      : body;

    const createRes = await fetch(
      `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues`,
      {
        method: "POST",
        headers: ghHeaders,
        body: JSON.stringify({
          title,
          body: finalBody,
          labels: labels.length ? labels : ["bug"]
        })
      }
    );

    if (!createRes.ok) {
      const errText = await createRes.text();
      return json({ ok: false, error: `GitHub API error (${createRes.status}): ${errText.slice(0, 200)}` }, 502);
    }

    const created = await createRes.json();
    return json({ ok: true, deduplicated: false, issueUrl: created.html_url }, 201);
  }
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" }
  });
}
