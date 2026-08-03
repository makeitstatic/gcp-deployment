// architecture.md -> architecture.pdf
//
// The Markdown is the single source of truth; this renders it. Everything
// Obsidian understands natively (frontmatter, callouts, mermaid fences) has
// to be handled explicitly here, plus the document skeleton and print rules.
//
// Usage, from this directory:
//   npm install marked mermaid puppeteer-core
//   node make-pdf.js [out.pdf]
//
// Needs a Chromium-family browser at BROWSER (default /usr/bin/brave).
// Regenerate whenever architecture.md changes, or the PDF silently drifts.

const fs = require('fs');
const path = require('path');
const { marked } = require('marked');
const puppeteer = require('puppeteer-core');

const REPO = path.resolve(__dirname, '..');
const DOCS = path.join(REPO, 'docs');
const HTML = path.join(__dirname, 'print.html');
const OUT = process.argv[2] || path.join(REPO, 'solution-architecture.pdf');
const BROWSER = process.env.BROWSER || '/usr/bin/brave';

// Reading order. Numbered chapters first, then every ADR in numeric order —
// discovered from disk so a new record joins the PDF without touching this
// file. decisions/README.md is the index and leads the appendix.
const CHAPTERS = fs
  .readdirSync(DOCS)
  .filter((f) => /^\d+-.*\.md$/.test(f))
  .sort()
  .map((f) => path.join(DOCS, f));

const ADR_DIR = path.join(DOCS, 'decisions');
const ADRS = [
  path.join(ADR_DIR, 'README.md'),
  ...fs
    .readdirSync(ADR_DIR)
    .filter((f) => /^\d+-.*\.md$/.test(f))
    .sort()
    .map((f) => path.join(ADR_DIR, f)),
].filter((f) => fs.existsSync(f));

const FILES = [...CHAPTERS, ...ADRS];
if (!FILES.length) throw new Error(`no documents found under ${DOCS}`);

// On this machine `ui-monospace` and a bare `monospace` resolve to different
// families. Mermaid sizes each node box from the font it believes it is
// using, so a stack is a liability: pin one installed family and use the
// same one in CSS, or labels get clipped mid-word.
const MONO = 'DejaVu Sans Mono';

const DOC_TITLE = 'Online Boutique on Google Cloud';
const DOC_SUBTITLE = 'Solution architecture, decisions and runbook';

// ---- shared marked configuration -------------------------------------------
const slugs = new Set();
// Matches GitHub's / Obsidian's heading-anchor algorithm, so the same
// `file.md#anchor` link resolves on GitHub, in a vault, and in this PDF:
// strip entities and punctuation, then one hyphen per space — NOT per run,
// which is why "Level 3 — application components" yields a double hyphen.
const slug = (s) => {
  const b = s
    .replace(/&[#\w]+;/g, '')
    .toLowerCase()
    .replace(/[^\w\s-]/g, '')
    .trim()
    .replace(/\s/g, '-');
  let out = b, n = 2;
  while (slugs.has(out)) out = `${b}-${n++}`;
  slugs.add(out);
  return out;
};

const TONE = {
  abstract: 'accent', tip: 'accent', info: 'accent', important: 'accent',
  note: 'neutral', question: 'neutral',
  warning: 'amber', caution: 'amber',
  failure: 'red', danger: 'red', bug: 'red',
};

const toc = [];
// ADR bodies all share the same four headings — listing them would triple the
// contents for no navigational gain, so only chapters contribute h2 entries.
let collectSections = true;

marked.use({
  renderer: {
    // Mermaid must reach the browser as a <pre class="mermaid">. Escaping the
    // angle brackets is what makes a literal "<br/>" survive into the diagram
    // source — inside a <pre> it would otherwise parse as a real BR element
    // and contribute nothing to the textContent mermaid reads.
    code({ text, lang }) {
      if (lang === 'mermaid') {
        return `<pre class="mermaid">${text.replace(/</g, '&lt;').replace(/>/g, '&gt;')}</pre>`;
      }
      const esc = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      return `<pre class="code"><code>${esc}</code></pre>`;
    },
    heading({ tokens, depth }) {
      const text = this.parser.parseInline(tokens);
      const id = slug(text.replace(/<[^>]+>/g, ''));
      if (depth === 1 || (depth === 2 && collectSections)) toc.push({ depth, id, text });
      return `<h${depth} id="${id}">${text}</h${depth}>\n`;
    },
    // Cross-document links become internal anchors; links to source files
    // become code spans, since a clickable path means nothing on paper.
    link({ href, tokens }) {
      const text = this.parser.parseInline(tokens);
      if (/^(https?|mailto):/.test(href)) {
        return `<a href="${href}">${text}</a>`;
      }
      const md = href.match(/([^/]+)\.md(#.+)?$/);
      if (md) return `<a href="${md[2] || '#doc-' + md[1]}">${text}</a>`;
      return `<code class="path">${text}</code>`;
    },
  },
});

// ---- render each document ---------------------------------------------------
const renderDoc = (file) => {
  collectSections = !file.includes(`${path.sep}decisions${path.sep}`);
  let md = fs.readFileSync(file, 'utf8').replace(/^---\n[\s\S]*?\n---\n/, '');

  // Obsidian callouts: > [!type] Title / > body. Swapped for placeholders
  // first so marked cannot reprocess the HTML we build here.
  const callouts = [];
  md = md.replace(
    /^> \[!(\w+)\][+-]?[ \t]*(.*)\n((?:>.*\n?)*)/gm,
    (_, type, heading, rest) => {
      const kind = type.toLowerCase();
      const html =
        `<div class="callout callout-${TONE[kind] || 'neutral'}">` +
        `<p class="callout-label">${kind}</p>` +
        (heading.trim() ? `<p class="callout-title">${marked.parseInline(heading.trim())}</p>` : '') +
        `<div class="callout-body">${marked.parse(rest.replace(/^> ?/gm, ''))}</div>` +
        `</div>`;
      callouts.push(html);
      return `\n@@CALLOUT${callouts.length - 1}@@\n\n`;
    }
  );

  let html = marked.parse(md);
  callouts.forEach((c, i) => {
    html = html.replace(new RegExp(`<p>@@CALLOUT${i}@@</p>`), c);
  });

  // A section leading with a diagram opens its own page — see h2.page-open in
  // the stylesheet. Detected from the rendered HTML so it tracks the content.
  // i === 0 is the chapter intro; i === 1 is its first section, which is
  // already at the top of a fresh page because the chapter broke there.
  // Forcing another break would leave the intro alone on a near-empty page.
  html = html
    .split(/(?=<h2 )/)
    .map((part, i) =>
      i <= 1 || !/<pre class="mermaid">/.test(part)
        ? part
        : part.replace(/^<h2 /, '<h2 class="page-open" ')
    )
    .join('');

  const id = 'doc-' + path.basename(file, '.md');
  return `<section class="chapter" id="${id}">${html}</section>`;
};

const chapters = FILES.map(renderDoc).join('\n');

// ---- cover and contents -----------------------------------------------------
// Generated from the headings actually rendered, so it cannot drift.
const tocHtml =
  `<nav class="toc"><p class="toc-label">Contents</p><ol>` +
  toc
    .map((t) =>
      t.depth === 1
        ? `<li class="toc-chapter"><a href="#${t.id}">${t.text}</a></li>`
        : `<li class="toc-section"><a href="#${t.id}">${t.text}</a></li>`
    )
    .join('') +
  `</ol></nav>`;

const body = `
<header class="cover">
  <p class="cover-eyebrow">Terraform reference implementation</p>
  <h1 class="cover-title">${DOC_TITLE}</h1>
  <p class="cover-subtitle">${DOC_SUBTITLE}</p>
  <dl class="cover-facts">
    <div><dt>Region</dt><dd>europe-west4</dd></div>
    <div><dt>Cluster</dt><dd>GKE Autopilot, regional, private nodes</dd></div>
    <div><dt>State</dt><dd>GCS, versioned and locked</dd></div>
    <div><dt>Workload</dt><dd>11 microservices + redis-cart, v0.10.6</dd></div>
  </dl>
  ${tocHtml}
</header>
${chapters}`;

const title = `${DOC_TITLE} — ${DOC_SUBTITLE}`;

// ---- page ------------------------------------------------------------------
const css = `
  *, *::before, *::after { box-sizing: border-box; }
  body { margin: 0; }
  img, svg { max-width: 100%; }

  :root {
    --ground: #FFFFFF;
    --surface: #FFFFFF;
    --sheet: #EDF1F2;
    --ink: #12181B;
    --ink-2: #45535A;
    --ink-3: #6E7F85;
    --line: #D6DEE1;
    --line-strong: #B7C4C8;
    --accent: #0E6E7C;
    --accent-soft: #E3EFF1;
    --amber: #8F5606;
    --amber-soft: #FBF1DE;
    --red: #9B3125;
    --red-soft: #F9E9E6;
    --mono: "${MONO}", monospace;
    --sans: "Noto Sans", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  }

  html { font-size: 12.25px; }
  body {
    background: var(--ground);
    color: var(--ink);
    font-family: var(--sans);
    line-height: 1.62;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }

  .wrap { max-width: 100%; padding: 0; }

  /* ---- type scale ---- */
  h1 {
    font-family: var(--mono);
    font-size: 2.5rem;
    font-weight: 700;
    letter-spacing: -0.025em;
    line-height: 1.08;
    margin: 0 0 1.25rem;
    text-wrap: balance;
  }
  h2 {
    font-family: var(--mono);
    font-size: 1.5rem;
    font-weight: 700;
    letter-spacing: -0.012em;
    margin: 2.75rem 0 0.85rem;
    padding-bottom: 0.4rem;
    border-bottom: 2px solid var(--accent);
    text-wrap: balance;
  }
  h3 {
    font-family: var(--mono);
    font-size: 1.0625rem;
    font-weight: 700;
    margin: 1.9rem 0 0.6rem;
    color: var(--ink);
  }
  p { margin: 0 0 0.85rem; max-width: 78ch; orphans: 3; widows: 3; }
  strong { font-weight: 650; }
  a { color: var(--accent); text-decoration: none; border-bottom: 1px solid rgba(14,110,124,0.3); }

  code {
    font-family: var(--mono);
    font-size: 0.895em;
    background: #EFF3F4;
    padding: 0.05em 0.3em;
    border-radius: 2px;
  }

  pre.code {
    font-family: var(--mono);
    font-size: 0.8rem;
    line-height: 1.55;
    background: #F4F7F7;
    border: 1px solid var(--line);
    border-left: 3px solid var(--accent);
    border-radius: 2px;
    padding: 0.85rem 1rem;
    margin: 0 0 1.1rem;
    overflow-x: auto;
    white-space: pre-wrap;
    word-break: break-word;
  }
  pre.code code { background: none; padding: 0; font-size: 1em; }

  hr { border: none; border-top: 1px solid var(--line); margin: 2.5rem 0; }

  /* ---- masthead + contents ---- */
  .toc {
    border: 1px solid var(--line);
    border-radius: 2px;
    padding: 1rem 1.25rem 1.1rem;
    margin: 1.75rem 0 0;
    background: #FAFCFC;
    break-inside: avoid;
  }
  .toc-label {
    font-family: var(--mono);
    font-size: 0.6875rem;
    letter-spacing: 0.13em;
    text-transform: uppercase;
    color: var(--accent);
    margin: 0 0 0.5rem;
  }
  .toc ol {
    margin: 0; padding: 0; list-style: none;
    columns: 2; column-gap: 2.25rem;
  }
  .toc li { font-size: 0.82rem; padding: 0.1rem 0; break-inside: avoid; }
  .toc-chapter {
    font-weight: 650;
    margin-top: 0.5rem;
    counter-increment: chap;
  }
  .toc-chapter:first-child { margin-top: 0; }
  .toc-section { padding-left: 1rem; color: var(--ink-2); }
  .toc-section::before {
    content: '';
    display: inline-block;
    width: 0.4rem; height: 1px;
    background: var(--ink-3);
    vertical-align: middle;
    margin-right: 0.45rem;
  }
  .toc a { border: none; color: var(--ink); }

  /* ---- cover ---- */
  .cover { break-after: page; }
  .cover-eyebrow {
    font-family: var(--mono);
    font-size: 0.7rem;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--accent);
    margin: 0 0 0.9rem;
  }
  .cover-title {
    font-family: var(--mono);
    font-size: 2.9rem;
    font-weight: 700;
    letter-spacing: -0.03em;
    line-height: 1.05;
    margin: 0 0 0.6rem;
  }
  .cover-subtitle {
    font-size: 1.2rem;
    color: var(--ink-2);
    margin: 0 0 2.5rem;
  }
  .cover-facts {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 0.9rem 2rem;
    margin: 0 0 2.5rem;
    padding: 1.2rem 0 0;
    border-top: 2px solid var(--accent);
  }
  .cover-facts div { display: flex; flex-direction: column; gap: 0.15rem; }
  .cover-facts dt {
    font-family: var(--mono);
    font-size: 0.62rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--ink-3);
  }
  .cover-facts dd { margin: 0; font-size: 0.92rem; }

  /* ---- tables ---- */
  table {
    border-collapse: collapse;
    width: 100%;
    font-size: 0.85rem;
    margin: 0 0 1.2rem;
    border: 1px solid var(--line);
  }
  thead { display: table-header-group; }
  thead th {
    font-family: var(--mono);
    font-size: 0.66rem;
    letter-spacing: 0.09em;
    text-transform: uppercase;
    color: var(--ink-3);
    font-weight: 500;
    text-align: left;
    background: #F5F8F8;
    white-space: nowrap;
  }
  th, td {
    padding: 0.5rem 0.75rem;
    border-bottom: 1px solid var(--line);
    text-align: left;
    vertical-align: top;
  }
  td:nth-child(2) { font-variant-numeric: tabular-nums; }
  tbody tr:last-child td { border-bottom: none; }
  tr { break-inside: avoid; }
  /* Keep a table whole where it fits on a fresh page — a single row spilling
     past a break reads as a mistake. A table taller than one page still
     breaks; this is a preference, not a guarantee. */
  table { break-inside: avoid; }

  /* Each source document is a chapter and opens on a fresh page. */
  .chapter { break-before: page; }
  .chapter h1 {
    font-size: 1.95rem;
    padding-bottom: 0.5rem;
    border-bottom: 3px solid var(--accent);
    margin: 0 0 1.4rem;
  }

  /* Links to source files are references, not destinations, on paper. */
  code.path { background: #EFF3F4; border-bottom: none; white-space: nowrap; }

  /* ---- callouts ---- */
  .callout {
    border: 1px solid var(--line);
    border-left: 3px solid var(--ink-3);
    border-radius: 2px;
    padding: 0.85rem 1.1rem 0.35rem;
    margin: 0 0 1.2rem;
    background: #FAFCFC;
    break-inside: avoid;
  }
  .callout-label {
    font-family: var(--mono);
    font-size: 0.625rem;
    letter-spacing: 0.13em;
    text-transform: uppercase;
    margin: 0 0 0.15rem;
    color: var(--ink-3);
  }
  .callout-title { font-weight: 650; margin: 0 0 0.5rem; }
  .callout-body p:last-child { margin-bottom: 0.5rem; }
  .callout-body ul { margin: 0 0 0.6rem; padding-left: 1.1rem; }
  .callout-body li { margin-bottom: 0.3rem; }

  .callout-accent  { border-left-color: var(--accent); background: var(--accent-soft); }
  .callout-accent .callout-label { color: var(--accent); }
  .callout-amber   { border-left-color: var(--amber); background: var(--amber-soft); }
  .callout-amber .callout-label { color: var(--amber); }
  .callout-red     { border-left-color: var(--red); background: var(--red-soft); }
  .callout-red .callout-label { color: var(--red); }

  /* ---- diagrams ---- */
  .sheet, pre.mermaid {
    background: var(--sheet);
    border: 1px solid var(--line-strong);
    border-radius: 2px;
    padding: 1.1rem 0.75rem;
    margin: 0 0 0.75rem;
    display: flex;
    justify-content: center;
    break-inside: avoid;
    font-family: var(--mono);
  }

  /* Fit the type area in BOTH axes — a diagram constrained only by width can
     still be taller than the page and strand a blank sheet. The height cap
     also leaves room for the section heading and intro above it, so the two
     stay on one page instead of the diagram being pushed to the next. */
  pre.mermaid svg {
    max-width: 100% !important;
    max-height: 193mm !important;
    width: auto !important;
    height: auto !important;
  }

  /* Mermaid's base theme paints edge labels magenta, which fights the
     palette. Node and cluster colours come from classDef in the Markdown
     (portable to Obsidian); edge labels can only be reached from here. */
  pre.mermaid svg .edgeLabel,
  pre.mermaid svg .edgeLabel p,
  pre.mermaid svg .edgeLabel span,
  pre.mermaid svg .edgeLabel div,
  pre.mermaid svg .edgeLabel foreignObject > div {
    color: #12181B !important;
    fill: #12181B !important;
    background-color: #EDF1F2 !important;
  }
  pre.mermaid svg .edgeLabel rect,
  pre.mermaid svg rect.labelBkg { fill: #EDF1F2 !important; }

  /* Same family mermaid measured with, on every element the label text can
     inherit from. */
  pre.mermaid, pre.mermaid svg, pre.mermaid svg text, pre.mermaid svg tspan,
  pre.mermaid svg foreignObject, pre.mermaid svg foreignObject div,
  pre.mermaid svg foreignObject span, pre.mermaid svg foreignObject p {
    font-family: "${MONO}", monospace !important;
  }

  /* ---- pagination ---- */
  @page { size: A4; margin: 13mm 12mm 15mm; }
  h1, h2, h3 { break-after: avoid; }
  h2 + p, h3 + p, h2 + table, h3 + table { break-before: avoid; }

  /* A diagram is one unbreakable block roughly two-thirds of a page tall, so
     a section leading with one will strand its heading and intro at the foot
     of the previous page. Rather than fight that with break-after rules —
     which only move the gap around — such sections open a page of their own.
     The rhythm reads as deliberate, and heading, intro and diagram always
     stay together. Marked up in the build, so it tracks the content. */
  h2.page-open { break-before: page; }
  ul, ol { max-width: 78ch; }
  li { orphans: 2; widows: 2; }
`;

const mermaidJs = fs.readFileSync(
  require.resolve('mermaid/dist/mermaid.min.js'),
  'utf8'
);

const html = `<!doctype html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<title>${title}</title>
<style>${css}</style>
</head>
<body>
<div class="wrap">
${body}
</div>
<script>${mermaidJs}<\/script>
<script>
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'loose',
    theme: 'base',
    themeVariables: { fontFamily: '${MONO}', fontSize: '12px' },
    flowchart: { htmlLabels: true, useMaxWidth: true }
  });
  mermaid.run({ querySelector: 'pre.mermaid' })
    .then(function () { document.documentElement.setAttribute('data-mermaid', 'done'); })
    .catch(function (e) { document.documentElement.setAttribute('data-mermaid', 'error: ' + e.message); });
<\/script>
</body>
</html>`;

fs.writeFileSync(HTML, html);
console.log(`html: ${(html.length / 1e6).toFixed(2)} MB · ${toc.length} sections in contents`);

// ---- render ----------------------------------------------------------------
(async () => {
  const browser = await puppeteer.launch({
    executablePath: BROWSER,
    headless: true,
    args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage();
  page.on('pageerror', (e) => console.error('page error:', e.message));

  await page.goto('file://' + HTML, { waitUntil: 'load', timeout: 120000 });

  // The bare --print-to-pdf flag prints at load, long before mermaid has run.
  await page.waitForFunction(
    () => document.documentElement.getAttribute('data-mermaid') !== null,
    { timeout: 120000 }
  );
  const state = await page.evaluate(() =>
    document.documentElement.getAttribute('data-mermaid')
  );
  const diagrams = await page.evaluate(
    () => document.querySelectorAll('pre.mermaid svg').length
  );
  const expected = FILES.reduce(
    (n, f) => n + (fs.readFileSync(f, 'utf8').match(/```mermaid/g) || []).length,
    0
  );
  console.log(`mermaid: ${state} · ${diagrams}/${expected} diagrams rendered`);
  if (state !== 'done') throw new Error('mermaid failed: ' + state);
  if (diagrams !== expected) throw new Error(`expected ${expected} diagrams, got ${diagrams}`);

  await page.evaluateHandle('document.fonts.ready');

  const foot =
    `<div style="width:100%;font-family:${MONO},monospace;font-size:7pt;color:#6E7F85;` +
    `padding:0 12mm;display:flex;justify-content:space-between;">` +
    `<span>Online Boutique on Google Cloud — Solution Architecture</span>` +
    `<span class="pageNumber"></span></div>`;

  await page.pdf({
    path: OUT,
    format: 'A4',
    printBackground: true,
    preferCSSPageSize: true,
    displayHeaderFooter: true,
    headerTemplate: '<span></span>',
    footerTemplate: foot,
  });

  await browser.close();
  console.log('wrote', OUT);
})().catch((e) => {
  console.error('FAILED:', e.message);
  process.exit(1);
});
