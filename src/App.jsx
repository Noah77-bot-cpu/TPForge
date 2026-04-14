import { useEffect, useState } from "react";
import config from "./config";

export default function App() {
  const [scripts, setScripts] = useState([]);
  const [query, setQuery] = useState("");
  const [copiedSlug, setCopiedSlug] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    async function loadScripts() {
      if (!config.owner || !config.repo) {
        setError("Configure src/config.js avec le owner et le repo GitHub.");
        setIsLoading(false);
        return;
      }

      try {
        const folders = await fetchScriptFolders(config);
        const items = await Promise.all(
          folders.map((folder) => buildScriptEntry(config, folder))
        );
        setScripts(items.filter(Boolean));
      } catch (err) {
        setError(err.message || "Impossible de charger les scripts depuis GitHub.");
      } finally {
        setIsLoading(false);
      }
    }

    loadScripts();
  }, []);

  const normalizedQuery = query.trim().toLowerCase();
  const filteredScripts = scripts.filter((item) => {
    return (
      !normalizedQuery ||
      item.title.toLowerCase().includes(normalizedQuery) ||
      item.description.toLowerCase().includes(normalizedQuery) ||
      item.slug.toLowerCase().includes(normalizedQuery)
    );
  });

  async function copyCommand(slug, command) {
    try {
      await navigator.clipboard.writeText(command);
      setCopiedSlug(slug);
      window.setTimeout(() => setCopiedSlug(""), 1800);
    } catch (err) {
      window.alert("La copie automatique a echoue. Copie la commande manuellement.");
    }
  }

  return (
    <main className="app-shell">
      <div className="app-shell__bg" />
      <div className="app-shell__glow" />

      <div className="app-shell__content">
        <section className="hero-grid">
          <div className="animate-rise">
            <p className="eyebrow">
              GitHub script index
            </p>
            <h1 className="hero-title">
              TPForge lit automatiquement les scripts presents dans
              <span className="hero-title__accent"> GitHub </span>
              et affiche leur commande de deploiement.
            </h1>
            <p className="hero-copy">
              Chaque script vit dans son dossier avec un fichier Markdown pour
              le descriptif et un fichier shell pour l installation.
            </p>
          </div>

          <aside className="panel animate-rise">
            <p className="panel-label">
              Configuration
            </p>
            <div className="stats-grid">
              <StatCard
                label="Repository"
                value={`${config.owner || "owner"}/${config.repo || "repo"}`}
              />
              <StatCard label="Branche" value={config.branch || "main"} />
              <StatCard label="Scripts detectes" value={scripts.length} />
            </div>
          </aside>
        </section>

        <section className="search-panel animate-rise">
          <div className="search-grid">
            <label className="search-input">
              <span className="search-input__label">Rechercher</span>
              <input
                type="text"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Nom du dossier, titre, description..."
                className="search-input__field"
              />
            </label>

            <div className="search-meta">
              Dossier surveille:{" "}
              <span className="search-meta__path">
                {config.scriptsPath || "scripts"}
              </span>
            </div>
          </div>
        </section>

        <section className="results-section">
          {isLoading ? (
            <div className="cards-grid">
              {Array.from({ length: 3 }).map((_, index) => (
                <div
                  key={index}
                  className="skeleton-card"
                />
              ))}
            </div>
          ) : error ? (
            <div className="feedback-card feedback-card--error">
              {error}
            </div>
          ) : filteredScripts.length === 0 ? (
            <div className="feedback-card feedback-card--empty">
              Aucun script trouve pour cette recherche.
            </div>
          ) : (
            <div className="cards-grid">
              {filteredScripts.map((item, index) => (
                <article
                  key={item.slug}
                  className="script-card"
                  style={{ animationDelay: `${index * 90}ms` }}
                >
                  <div className="script-card__header">
                    <div>
                      <p className="script-card__slug">
                        {item.slug}
                      </p>
                      <h2 className="script-card__title">
                        {item.title}
                      </h2>
                    </div>
                    <a
                      href={item.folderUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="pill-link"
                    >
                      Ouvrir
                    </a>
                  </div>

                  <p className="script-card__description">
                    {item.description}
                  </p>

                  <div className="script-card__files">
                    Fichiers: {item.metaFileName} + {item.scriptFileName}
                  </div>

                  <div className="script-card__command">
                    <p className="script-card__command-label">
                      Commande curl
                    </p>
                    <pre className="script-card__command-text">
                      <code>{item.curlCommand}</code>
                    </pre>
                  </div>

                  <div className="script-card__actions">
                    <button
                      type="button"
                      onClick={() => copyCommand(item.slug, item.curlCommand)}
                      className="primary-button"
                    >
                      {copiedSlug === item.slug
                        ? "Commande copiee"
                        : "Copier la commande"}
                    </button>
                    <a
                      href={item.rawScriptUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="secondary-link"
                    >
                      Voir le .sh
                    </a>
                  </div>
                </article>
              ))}
            </div>
          )}
        </section>
      </div>
    </main>
  );
}

function StatCard({ label, value }) {
  return (
    <div className="stat-card">
      <p className="stat-card__label">{label}</p>
      <p className="stat-card__value">{value}</p>
    </div>
  );
}

async function fetchScriptFolders(appConfig) {
  const apiUrl = buildContentsApiUrl(appConfig, appConfig.scriptsPath || "scripts");
  const response = await fetch(apiUrl, {
    headers: { Accept: "application/vnd.github+json" },
  });

  if (!response.ok) {
    throw new Error(
      "Impossible de lire le dossier scripts depuis GitHub. Verifie owner, repo, branche et visibilite."
    );
  }

  const data = await response.json();
  return data.filter((entry) => entry.type === "dir");
}

async function buildScriptEntry(appConfig, folder) {
  const folderPath = folder.path;
  const folderContents = await fetchFolderContents(appConfig, folderPath);
  const metaFile = folderContents.find(
    (item) => item.type === "file" && item.name.toLowerCase().endsWith(".md")
  );
  const scriptFile = folderContents.find(
    (item) => item.type === "file" && item.name.toLowerCase().endsWith(".sh")
  );

  if (!metaFile || !scriptFile) {
    return null;
  }

  const metadataText = await fetchTextFile(metaFile.download_url);
  const metadata = parseMetadata(metadataText);

  return {
    slug: folder.name,
    title: metadata.title || prettifySlug(folder.name),
    description:
      metadata.description || "Aucune description trouvee dans le Markdown.",
    curlCommand: buildCurlCommand(appConfig, scriptFile.path),
    folderUrl: buildGithubTreeUrl(appConfig, folderPath),
    rawScriptUrl: scriptFile.download_url,
    metaFileName: metaFile.name,
    scriptFileName: scriptFile.name,
  };
}

async function fetchFolderContents(appConfig, folderPath) {
  const response = await fetch(buildContentsApiUrl(appConfig, folderPath), {
    headers: { Accept: "application/vnd.github+json" },
  });

  if (!response.ok) {
    throw new Error(`Impossible de lire le dossier ${folderPath} sur GitHub.`);
  }

  return response.json();
}

async function fetchTextFile(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error("Impossible de telecharger un fichier distant.");
  }

  return response.text();
}

function parseMetadata(markdown) {
  const lines = markdown.split(/\r?\n/);
  let title = "";
  let description = "";

  lines.forEach((line) => {
    if (!title && line.toLowerCase().startsWith("title:")) {
      title = line.slice(6).trim();
      return;
    }

    if (!description && line.toLowerCase().startsWith("description:")) {
      description = line.slice(12).trim();
    }
  });

  if (!title) {
    const heading = lines.find((line) => line.trim().startsWith("# "));
    if (heading) {
      title = heading.replace(/^#\s+/, "").trim();
    }
  }

  if (!description) {
    const paragraph = lines.find(
      (line) => line.trim() && !line.trim().startsWith("#")
    );
    if (paragraph) {
      description = paragraph.trim();
    }
  }

  return { title, description };
}

function buildContentsApiUrl(appConfig, path) {
  const base = `https://api.github.com/repos/${appConfig.owner}/${appConfig.repo}/contents/${path}`;
  return `${base}?ref=${encodeURIComponent(appConfig.branch || "main")}`;
}

function buildGithubTreeUrl(appConfig, path) {
  return `https://github.com/${appConfig.owner}/${appConfig.repo}/tree/${appConfig.branch || "main"}/${path}`;
}

function buildCurlCommand(appConfig, scriptPath) {
  const rawUrl = `https://raw.githubusercontent.com/${appConfig.owner}/${appConfig.repo}/${appConfig.branch || "main"}/${scriptPath}`;
  return `curl -fsSL ${rawUrl} | bash`;
}

function prettifySlug(slug) {
  return slug
    .split(/[-_]/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}
