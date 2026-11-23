// Spitball Club: tiny opt-in leaderboard. Stores running totals per anonymous install.
//   POST /v1/report  {id, handle, words, seconds}  → upsert totals
//   GET  /v1/stats                                 → {members, words, hours, top[]}
//   GET  /v1/rank?id=…                             → {rank, members}
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};
const json = (body, status = 200, extra = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...cors, ...extra } });

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (req.method === 'OPTIONS') return new Response(null, { headers: cors });

    if (req.method === 'POST' && url.pathname === '/v1/report') {
      let b;
      try { b = await req.json(); } catch { return json({ error: 'bad json' }, 400); }
      const id = String(b.id || '');
      if (!/^[0-9a-f-]{36}$/.test(id)) return json({ error: 'bad id' }, 400);
      const handle = String(b.handle || '').replace(/[^\w@.\- ]/g, '').slice(0, 24);
      // Sanity caps: nobody dictates more than this.
      const words = Math.max(0, Math.min(Number(b.words) | 0, 50_000_000));
      const seconds = Math.max(0, Math.min(Number(b.seconds) | 0, 100_000_000));
      await env.DB.prepare(
        `INSERT INTO members (id, handle, words, seconds, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(id) DO UPDATE SET handle = ?2, words = MAX(words, ?3), seconds = MAX(seconds, ?4), updated_at = ?5`
      ).bind(id, handle, words, seconds, Date.now()).run();
      return json({ ok: true });
    }

    if (req.method === 'GET' && url.pathname === '/v1/stats') {
      const totals = await env.DB.prepare('SELECT COUNT(*) AS members, COALESCE(SUM(words),0) AS words, COALESCE(SUM(seconds),0) AS seconds FROM members').first();
      const top = await env.DB.prepare("SELECT CASE WHEN handle = '' THEN 'Anonymous' ELSE handle END AS handle, words, seconds FROM members ORDER BY words DESC LIMIT 10").all();
      return json({ members: totals.members, words: totals.words, hours: totals.seconds / 3600, top: top.results }, 200, { 'Cache-Control': 'public, max-age=60' });
    }

    if (req.method === 'GET' && url.pathname === '/v1/rank') {
      const me = await env.DB.prepare('SELECT words FROM members WHERE id = ?1').bind(url.searchParams.get('id') || '').first();
      const members = (await env.DB.prepare('SELECT COUNT(*) AS n FROM members').first()).n;
      if (!me) return json({ rank: null, members });
      const ahead = (await env.DB.prepare('SELECT COUNT(*) AS n FROM members WHERE words > ?1').bind(me.words).first()).n;
      return json({ rank: ahead + 1, members });
    }

    return json({ error: 'not found' }, 404);
  },
};
