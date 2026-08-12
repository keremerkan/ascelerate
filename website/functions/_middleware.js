// Markdown for agents: content negotiation at the edge (Cloudflare Pages
// Functions). Clients sending Accept: text/markdown get a page's .md twin
// when one exists (docs twins come from scripts/generate-md-twins.mjs, the
// homepage twin from static/index.md); browsers keep getting HTML. HTML
// responses for negotiated URLs carry Vary: Accept so caches keep the two
// representations apart.
const HAS_EXTENSION = /\.[a-z0-9]+$/i;

export async function onRequest({ request, env, next }) {
  const url = new URL(request.url);
  const accept = (request.headers.get('accept') || '').toLowerCase();

  if (request.method === 'GET' && accept.includes('text/markdown') && !HAS_EXTENSION.test(url.pathname)) {
    const base = url.pathname.replace(/\/+$/, '');
    const candidates = base ? [`${base}.md`, `${base}/index.md`] : ['/index.md'];
    for (const path of candidates) {
      const asset = await env.ASSETS.fetch(new URL(path, url.origin));
      if (asset.ok) {
        const headers = new Headers(asset.headers);
        headers.set('Content-Type', 'text/markdown; charset=utf-8');
        headers.append('Vary', 'Accept');
        return new Response(asset.body, { status: 200, headers });
      }
    }
  }

  const response = await next();
  if ((response.headers.get('content-type') || '').includes('text/html')) {
    const headers = new Headers(response.headers);
    headers.append('Vary', 'Accept');
    // RFC 8288 discovery: the homepage advertises its machine-readable twin,
    // so agents can find /index.md from a HEAD request alone.
    const home = url.pathname.match(/^\/(?:(de|fr|ja|tr)\/)?$/);
    if (home) {
      const prefix = home[1] ? `/${home[1]}` : '';
      headers.set('Link', `<${prefix}/index.md>; rel="describedby"; type="text/markdown"`);
    }
    return new Response(response.body, { status: response.status, headers });
  }
  return response;
}
