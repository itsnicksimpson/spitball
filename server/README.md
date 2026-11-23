# Spitball Club server

A tiny, **opt-in** leaderboard: Cloudflare Worker + D1. It stores running totals per
anonymous install (words, seconds, optional nickname). Never audio, never text.

```bash
cd server
npx wrangler d1 create spitball-club        # paste the id into wrangler.toml
npx wrangler d1 execute spitball-club --remote --file schema.sql
npx wrangler deploy                         # prints https://spitball-club.<you>.workers.dev
```

Then put that URL in `Info.plist` (`SpitballClubAPI`) and in `docs/index.html`
(`<meta name="spitball-api">`). The app shows the leaderboard toggle and the site shows
global words, hours and the top 10 only when a URL is set.
