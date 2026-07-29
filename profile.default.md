<!-- The default search profile. setup.sh copies this to profile.md, which is the
     file actually used and is never committed. Everything below is pasted verbatim
     into the agent's prompt, so write it as instructions — prose or bullets, no
     schema to respect. -->

## Candidate

- Role: JavaScript/TypeScript developer, any seniority.
- Based in: Antananarivo, Madagascar (UTC+3), works from home.
- Languages: French and English — postings in either are fine.

## Roles wanted

Fullstack, frontend, backend or mobile developer positions on JS/TS stacks:
React, Next.js, Node.js, NestJS, React Native, Vue, Angular, Express and similar.

## Eligibility rules

- Jobs located in Madagascar: on-site, hybrid or freelance are all acceptable.
- Jobs anywhere else: must be fully remote / freelance / contract and open to a
  candidate working from Madagascar (remote worldwide, remote Africa, or
  contractor-friendly). Exclude US-only, EU-only or France-residency-required
  roles. Flag "eligibility unclear" when unsure.
- Timezone-overlap requirements up to US Eastern are acceptable, but must be
  flagged.

## Sources to sweep

1. **Remote worldwide boards** — RemoteOK, Remotive, Wellfound, Arc.dev,
   web3.career.
2. **French-speaking market** — Welcome to the Jungle, LinkedIn public listings,
   free-work.com, ChooseYourBoss. Full-remote roles only; flag listings that
   likely require French payroll or French freelance status.
3. **Madagascar local** — portaljob-madagascar.com, asako.mg, LinkedIn
   Madagascar/Antananarivo, local ESNs and offshore development companies. Watch
   for mis-geotagged listings: verify the location in the listing body.
   - asako.mg: use `/emploi/s-informatique-digital`, which shows clean
     per-listing dates.
   - portaljob-madagascar.com is an Inertia/Laravel single-page app, rebuilt
     around July 2026. The old `POST /api/emploi/annonces` endpoint now returns
     HTTP 403 `{"message":"Access not allowed"}` even with session cookies and an
     `X-XSRF-TOKEN` header; `/emploi` is a 404 and `/annonces` redirects to the
     homepage. There is no sitemap.xml. Known-good: the homepage embeds Inertia
     props in the `data-page` attribute of `<div id="app">` (HTML-unescape, then
     parse as JSON), and the sector taxonomy is at `props.megaMenu.secteurs`,
     where id 7 = "Informatique / web", slug `informatique-web`. Use `curl` to
     rediscover the current listing route; if you find one that works, record the
     exact command in the report's Notes section so the next run can reuse it. If
     it stays blocked, say so and move on — do not spend more than a few minutes
     on it.
4. **Freelance / contract** — Arc.dev, Upwork public pages, Contra.

## Sources to never use

Himalayas and WeWorkRemotely (paywalled), Codeur.com (no credits), Malt and
Lemon.io (not usable from Madagascar), Freelancer.com (bidding model not wanted).
Never search or cite these.
