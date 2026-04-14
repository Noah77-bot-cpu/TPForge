import { useEffect, useState } from "react";
import config from "./config";

export default function App() {
  const [scripts, setScripts] = useState([]);
  const [query, setQuery] = useState("");
  const [copiedSlug, setCopiedSlug] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    async function load() {
      if (!config.owner || !config.repo) {
        setError("Configure src/config.js.");
        setIsLoading(false);
        return;
      }
      try {
        const folders = await fetchScriptFolders(config);
        const items = await Promise.all(folders.map((f) => buildScriptEntry(config, f)));
        setScripts(items.filter(Boolean));
      } catch (err) {
        setError(err.message || "Impossible de charger les scripts.");
      } finally {
        setIsLoading(false);
      }
    }
    load();
  }, []);

  const filtered = scripts.filter(
    (s) =>
      !query.trim() ||
      s.title.toLowerCase().includes(query.toLowerCase()) ||
      s.description.toLowerCase().includes(query.toLowerCase()) ||
      s.slug.toLowerCase().includes(query.toLowerCase())
  );

  async function copy(slug, cmd) {
    try {
      await navigator.clipboard.writeText(cmd);
      setCopiedSlug(slug);
      setTimeout(() => setCopiedSlug(""), 1800);
    } catch {
      alert("Copie manuelle nécessaire.");
    }
  }

  return (
    <div className="shell">
      <header className="header">
        <div className="header__inner">
          <div className="brand">
            <span className="brand__icon">⚒</span>
            <span className="brand__name">TPForge</span>
          </div>
          <div className="header__pills">
            <span className="pill">{config.owner}/{config.repo}</span>
            <span className="pill">{config.branch}</span>
            {!isLoading && (
              <span className="pill pill--gold">
                {scripts.length} script{scripts.length !== 1 ? "s" : ""}
              </span>
            )}
          </div>
        </div>
      </header>

      <div className="search-zone">
        <div className="search-bar">
          <svg className="search-bar__icon" viewBox="0 0 20 20" fill="currentColor">
            <path
              fillRule="evenodd"
              d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z"
              clipRule="evenodd"
            />
          </svg>
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Rechercher un script..."
            className="search-bar__input"
          />
          {query && (
            <button className="search-bar__clear" onClick={() => setQuery("")}>
              ✕
            </button>
          )}
        </div>
      </div>

      <main className="main">
        {isLoading ? (
          <div className="grid">
            {[0, 1, 2].map((i) => (
              <div key={i} className="skeleton" style={{ animationDelay: `${i * 120}ms` }} />
            ))}
          </div>
        ) : error ? (
          <div className="notice notice--error">{error}</div>
        ) : filtered.length === 0 ? (
          <div className="notice">Aucun résultat pour « {query} ».</div>
        ) : (
          <div className="grid">
            {filtered.map((item, i) => (
              <article
                key={item.slug}
                className="card"
                style={{ animationDelay: `${i * 70}ms` }}
              >
                <div className="card__head">
                  <div>
                    <p className="card__slug">{item.slug}</p>
                    <h2 className="card__title">{item.title}</h2>
                  </div>
                  <a
                    href={item.folderUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="card__github"
                  >
                    GitHub ↗
                  </a>
                </div>

                <p className="card__desc">{item.description}</p>

                <div className="card__cmd">
                  <code>{item.curlCommand}</code>
                </div>

                <div className="card__foot">
                  <button
                    onClick={() => copy(item.slug, item.curlCommand)}
                    className={`btn-copy${copiedSlug === item.slug ? " btn-copy--done" : ""}`}
                  >
                    {copiedSlug === item.slug ? "✓ Copié !" : "Copier la commande"}
                  </button>
                  <a
                    href={item.rawScriptUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="btn-raw"
                  >
                    .sh ↗
                  </a>
                </div>
              </article>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}

async function fetchScriptFolders(cfg) {
  const res = await fetch(buildApiUrl(cfg, cfg.scriptsPath || "scripts"), {
    headers: { Accept: "application/vnd.github+json" },
  });
  if (!res.ok) throw new Error("Impossible de lire les scripts depuis GitHub.");
  const data = await res.json();
  return data.filter((e) => e.type === "dir");
}

async function buildScriptEntry(cfg, folder) {
  const contents = await fetchFolder(cfg, folder.path);
  const meta = contents.find((f) => f.type === "file" && f.name.toLowerCase().endsWith(".md"));
  const sh = contents.find((f) => f.type === "file" && f.name.toLowerCase().endsWith(".sh"));
  if (!meta || !sh) return null;

  const text = await fetchText(meta.download_url);
  const parsed = parseMeta(text);

  return {
    slug: folder.name,
    title: parsed.title || prettify(folder.name),
    description: parsed.description || "",
    curlCommand: buildCurl(cfg, sh.path),
    folderUrl: `https://github.com/${cfg.owner}/${cfg.repo}/tree/${cfg.branch}/${folder.path}`,
    rawScriptUrl: sh.download_url,
  };
}

async function fetchFolder(cfg, path) {
  const res = await fetch(buildApiUrl(cfg, path), {
    headers: { Accept: "application/vnd.github+json" },
  });
  if (!res.ok) throw new Error(`Impossible de lire ${path}`);
  return res.json();
}

async function fetchText(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error("Impossible de télécharger le fichier.");
  return res.text();
}

function parseMeta(md) {
  const lines = md.split(/\r?\n/);
  let title = "";
  let description = "";
  for (const line of lines) {
    if (!title && line.toLowerCase().startsWith("title:")) title = line.slice(6).trim();
    if (!description && line.toLowerCase().startsWith("description:")) description = line.slice(12).trim();
  }
  if (!title) {
    const h = lines.find((l) => l.trimStart().startsWith("# "));
    if (h) title = h.replace(/^#\s+/, "").trim();
  }
  return { title, description };
}

function buildApiUrl(cfg, path) {
  return `https://api.github.com/repos/${cfg.owner}/${cfg.repo}/contents/${path}?ref=${encodeURIComponent(cfg.branch || "main")}`;
}

function buildCurl(cfg, scriptPath) {
  return `curl -fsSL https://raw.githubusercontent.com/${cfg.owner}/${cfg.repo}/${cfg.branch || "main"}/${scriptPath} | bash`;
}

function prettify(slug) {
  return slug.split(/[-_]/).filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join(" ");
}
