const { useEffect, useState } = React;

function App() {
  const config = window.TPFORGE_CONFIG || {};
  const [scripts, setScripts] = useState([]);
  const [query, setQuery] = useState('');
  const [copiedSlug, setCopiedSlug] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    async function loadScripts() {
      if (!config.owner || !config.repo) {
        setError('Configure `site-config.js` avec le owner et le repo GitHub pour charger automatiquement les scripts.');
        setIsLoading(false);
        return;
      }

      try {
        const folders = await fetchScriptFolders(config);
        const items = await Promise.all(folders.map((folder) => buildScriptEntry(config, folder)));
        setScripts(items.filter(Boolean));
      } catch (err) {
        setError(err.message || 'Impossible de charger les scripts depuis GitHub.');
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
      window.setTimeout(() => setCopiedSlug(''), 1800);
    } catch (err) {
      window.alert('La copie automatique a échoué. Tu peux copier le script manuellement.');
    }
  }

  return (
    <main className="relative overflow-hidden">
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,_rgba(213,170,73,0.22),_transparent_35%),radial-gradient(circle_at_80%_20%,_rgba(120,68,22,0.28),_transparent_25%),linear-gradient(180deg,_#191611_0%,_#12110f_45%,_#0b0a08_100%)]" />
      <div className="absolute inset-x-0 top-0 h-72 bg-[linear-gradient(90deg,transparent,rgba(255,255,255,0.07),transparent)] opacity-30 blur-3xl" />

      <div className="relative mx-auto flex min-h-screen w-full max-w-7xl flex-col px-6 py-10 sm:px-10 lg:px-12">
        <section className="grid gap-10 lg:grid-cols-[1.15fr_0.85fr] lg:items-end">
          <div className="animate-rise">
            <p className="mb-4 inline-flex items-center gap-2 rounded-full border border-forge-300/25 bg-forge-400/10 px-4 py-2 text-xs font-semibold uppercase tracking-[0.32em] text-forge-200">
              GitHub script index
            </p>
            <h1 className="max-w-3xl text-5xl font-bold tracking-tight text-stone-50 sm:text-6xl">
              TPForge lit automatiquement les scripts présents dans
              <span className="text-forge-300"> GitHub </span>
              et affiche leur commande de déploiement.
            </h1>
            <p className="mt-6 max-w-2xl text-lg leading-8 text-stone-300">
              Chaque script vit dans son propre dossier avec un fichier Markdown pour le descriptif et un fichier shell pour l&apos;installation.
            </p>
          </div>

          <aside className="animate-rise rounded-[2rem] border border-white/10 bg-white/5 p-6 shadow-glow backdrop-blur-xl">
            <p className="text-sm uppercase tracking-[0.22em] text-stone-400">Configuration</p>
            <div className="mt-6 grid gap-4">
              <StatCard label="Repository" value={`${config.owner || 'owner'}/${config.repo || 'repo'}`} />
              <StatCard label="Branche" value={config.branch || 'main'} />
              <StatCard label="Scripts détectés" value={scripts.length} />
            </div>
          </aside>
        </section>

        <section className="mt-10 animate-rise rounded-[2rem] border border-white/10 bg-black/20 p-5 shadow-2xl backdrop-blur-xl sm:p-6">
          <div className="grid gap-4 lg:grid-cols-[1.3fr_0.7fr]">
            <label className="flex items-center gap-3 rounded-2xl border border-white/10 bg-white/5 px-4 py-4">
              <span className="text-stone-400">Rechercher</span>
              <input
                type="text"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Nom du dossier, titre, description..."
                className="w-full bg-transparent text-sm text-stone-100 outline-none placeholder:text-stone-500"
              />
            </label>

            <div className="rounded-2xl border border-white/10 bg-white/5 px-4 py-4 text-sm text-stone-300">
              Dossier surveillé: <span className="font-mono text-forge-200">{config.scriptsPath || 'scripts'}</span>
            </div>
          </div>
        </section>

        <section className="mt-10 flex-1">
          {isLoading ? (
            <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
              {Array.from({ length: 3 }).map((_, index) => (
                <div key={index} className="h-80 animate-pulse rounded-[2rem] border border-white/10 bg-white/5" />
              ))}
            </div>
          ) : error ? (
            <div className="rounded-[2rem] border border-red-500/30 bg-red-500/10 p-6 text-red-100">
              {error}
            </div>
          ) : filteredScripts.length === 0 ? (
            <div className="rounded-[2rem] border border-white/10 bg-white/5 p-10 text-center text-stone-300">
              Aucun script trouvé pour cette recherche.
            </div>
          ) : (
            <div className="grid gap-6 md:grid-cols-2 xl:grid-cols-3">
              {filteredScripts.map((item, index) => (
                <article
                  key={item.slug}
                  className="group rounded-[2rem] border border-white/10 bg-[linear-gradient(180deg,rgba(255,255,255,0.08),rgba(255,255,255,0.03))] p-6 shadow-xl backdrop-blur-xl transition duration-300 hover:-translate-y-1 hover:border-forge-300/40 hover:shadow-glow"
                  style={{ animationDelay: `${index * 90}ms` }}
                >
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <p className="text-xs uppercase tracking-[0.24em] text-forge-200/90">{item.slug}</p>
                      <h2 className="mt-2 text-2xl font-bold text-stone-50">{item.title}</h2>
                    </div>
                    <a
                      href={item.folderUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="rounded-full border border-forge-300/30 bg-forge-400/10 px-3 py-1 text-xs font-semibold text-forge-200 transition hover:bg-forge-300 hover:text-slateforge"
                    >
                      Ouvrir
                    </a>
                  </div>

                  <p className="mt-4 min-h-16 text-sm leading-7 text-stone-300">
                    {item.description}
                  </p>

                  <div className="mt-5 rounded-[1.25rem] border border-white/10 bg-white/5 px-4 py-3 text-xs uppercase tracking-[0.18em] text-stone-400">
                    Fichiers: {item.metaFileName} + {item.scriptFileName}
                  </div>

                  <div className="mt-6 rounded-[1.5rem] border border-white/10 bg-black/40 p-4">
                    <p className="mb-3 text-xs uppercase tracking-[0.2em] text-stone-500">Commande curl</p>
                    <pre className="overflow-x-auto text-sm leading-6 text-forge-100">
                      <code className="font-mono">{item.curlCommand}</code>
                    </pre>
                  </div>

                  <div className="mt-6 flex flex-wrap gap-3">
                    <button
                      type="button"
                      onClick={() => copyCommand(item.slug, item.curlCommand)}
                      className="rounded-full bg-forge-300 px-4 py-3 text-sm font-semibold text-slateforge transition hover:bg-forge-200"
                    >
                      {copiedSlug === item.slug ? 'Commande copiée' : 'Copier la commande'}
                    </button>
                    <a
                      href={item.rawScriptUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="rounded-full border border-white/10 px-4 py-3 text-sm font-semibold text-stone-200 transition hover:border-forge-300/40 hover:text-forge-200"
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
    <div className="rounded-[1.5rem] border border-white/10 bg-black/20 p-5">
      <p className="text-sm text-stone-400">{label}</p>
      <p className="mt-2 break-words text-2xl font-bold text-stone-50">{value}</p>
    </div>
  );
}

async function fetchScriptFolders(config) {
  const apiUrl = buildContentsApiUrl(config, config.scriptsPath || 'scripts');
  const response = await fetch(apiUrl, {
    headers: { Accept: 'application/vnd.github+json' }
  });

  if (!response.ok) {
    throw new Error('Impossible de lire le dossier scripts depuis GitHub. Vérifie le owner, le repo, la branche et la visibilité du dépôt.');
  }

  const data = await response.json();
  return data.filter((entry) => entry.type === 'dir');
}

async function buildScriptEntry(config, folder) {
  const folderPath = folder.path;
  const folderContents = await fetchFolderContents(config, folderPath);
  const metaFile = folderContents.find((item) => item.type === 'file' && item.name.toLowerCase().endsWith('.md'));
  const scriptFile = folderContents.find((item) => item.type === 'file' && item.name.toLowerCase().endsWith('.sh'));

  if (!metaFile || !scriptFile) {
    return null;
  }

  const metadataText = await fetchTextFile(metaFile.download_url);
  const metadata = parseMetadata(metadataText);

  return {
    slug: folder.name,
    title: metadata.title || prettifySlug(folder.name),
    description: metadata.description || 'Aucune description trouvée dans le fichier Markdown.',
    curlCommand: buildCurlCommand(config, scriptFile.path),
    folderUrl: buildGithubTreeUrl(config, folderPath),
    rawScriptUrl: scriptFile.download_url,
    metaFileName: metaFile.name,
    scriptFileName: scriptFile.name
  };
}

async function fetchFolderContents(config, folderPath) {
  const response = await fetch(buildContentsApiUrl(config, folderPath), {
    headers: { Accept: 'application/vnd.github+json' }
  });

  if (!response.ok) {
    throw new Error(`Impossible de lire le dossier ${folderPath} sur GitHub.`);
  }

  return response.json();
}

async function fetchTextFile(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error('Impossible de télécharger un fichier distant.');
  }

  return response.text();
}

function parseMetadata(markdown) {
  const lines = markdown.split(/\r?\n/);
  let title = '';
  let description = '';

  lines.forEach((line) => {
    if (!title && line.toLowerCase().startsWith('title:')) {
      title = line.slice(6).trim();
      return;
    }

    if (!description && line.toLowerCase().startsWith('description:')) {
      description = line.slice(12).trim();
    }
  });

  if (!title) {
    const heading = lines.find((line) => line.trim().startsWith('# '));
    if (heading) {
      title = heading.replace(/^#\s+/, '').trim();
    }
  }

  if (!description) {
    const paragraph = lines.find((line) => line.trim() && !line.trim().startsWith('#'));
    if (paragraph) {
      description = paragraph.trim();
    }
  }

  return { title, description };
}

function buildContentsApiUrl(config, path) {
  const base = `https://api.github.com/repos/${config.owner}/${config.repo}/contents/${path}`;
  return `${base}?ref=${encodeURIComponent(config.branch || 'main')}`;
}

function buildGithubTreeUrl(config, path) {
  return `https://github.com/${config.owner}/${config.repo}/tree/${config.branch || 'main'}/${path}`;
}

function buildCurlCommand(config, scriptPath) {
  const rawUrl = `https://raw.githubusercontent.com/${config.owner}/${config.repo}/${config.branch || 'main'}/${scriptPath}`;
  return `curl -fsSL ${rawUrl} | bash`;
}

function prettifySlug(slug) {
  return slug
    .split(/[-_]/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
