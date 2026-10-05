# PrintForge

PrintForge is a browsing platform for 3D-printable models — a Next.js app where users can search, filter by category, sort, and paginate through a catalog of user-submitted 3D print files.

Built as a Scrimba practice project using the Next.js App Router with server components, dynamic routes, and a local SQLite database.

## Features

- **Model catalog** — browse all models in a responsive grid, each with an image, name, description, like count, and category
- **Search** — filter models by name or description
- **Sort** — order results alphabetically, by popularity (likes), or by most recently added
- **Categories** — browse models filtered by a specific category
- **Pagination** — server-driven pagination with configurable page size
- **Model detail page** — dedicated page for each model showing its full description, category, likes, and date added

## Tech stack

- [Next.js 15](https://nextjs.org) (App Router, React Server Components)
- [React 19](https://react.dev)
- [Tailwind CSS 4](https://tailwindcss.com)
- [SQLite](https://www.sqlite.org/) via `sqlite` / `sqlite3`
- TypeScript

## Getting started

Install dependencies:

```bash
npm install
```

Run the dev server:

```bash
npm run dev
```

This seeds the SQLite database (`printforge.db`) from the JSON fixtures in [lib/data/](lib/data/) before starting the Next.js dev server, then opens the app at [http://localhost:3000](http://localhost:3000).

### Other scripts

```bash
npm run build   # production build
npm run start   # run the production build
npm run lint    # lint the codebase
```

## Project structure

```
app/
  page.tsx                          # landing page
  about/                            # about page
  3d-models/
    page.tsx                        # models list (search, sort, pagination)
    [id]/page.tsx                   # single model detail page
    categories/[categorySlug]/      # models filtered by category
components/                         # UI components (grid, cards, nav, pagination, search, sort)
lib/
  db.ts                             # SQLite connection helper
  models.ts                         # model queries (list, count, get by id)
  categories.ts                     # category queries
  seeds/                            # scripts that seed the SQLite DB from data/*.json
  data/                             # seed data (models.json, categories.json)
  types.ts                          # shared TypeScript types
  utils.ts                          # query param parsing helpers
```

## Data model

Each **model** has: `id`, `name`, `description`, `likes`, `image`, `category`, `dateAdded`.

Each **category** has: `name`, `slug`.

The SQLite database (`printforge.db`) is regenerated from [lib/data/models.json](lib/data/models.json) and [lib/data/categories.json](lib/data/categories.json) each time `npm run dev` runs, via the seed scripts in [lib/seeds/](lib/seeds/).

## Deployment

The app is deployed to an AWS Lightsail instance and served at
**https://printforge.soloalbert.com** behind nginx.

| Piece | Value |
|---|---|
| App dir | `/opt/printforge` |
| Process | `printforge.service` (systemd), runs as the unprivileged `printforge` user |
| Bind address | `127.0.0.1:3001` — nginx is the only public entry point |
| TLS | Let's Encrypt via certbot, auto-renewed by `certbot.timer` |

### Deploying

```bash
./deploy.sh
```

The script rsyncs the source, installs dependencies, re-seeds the database, builds, and
restarts the service, then verifies every route through nginx and fails loudly if any route
does not return 200.

The build goes into `.next-staging` first (see `distDir` in
[next.config.ts](next.config.ts)) and is only swapped into place **after** it succeeds, so a
broken build cannot take the site down. Downtime is limited to the stop/swap/start, a few
seconds.

### File ownership (important)

`albert` deploys, but the service runs as `printforge`, and both write into `.next`. Three
things make that work, and breaking any one of them takes the site down:

- `/opt/printforge` is `albert:printforge` mode **2770** (setgid), so new files inherit the
  shared group. Without setgid, `printforge.db` ends up group `albert` and the service loses
  access — every database-backed route returns 500.
- The systemd unit sets **`UMask=0002`** (drop-in at
  `/etc/systemd/system/printforge.service.d/umask.conf`), so the service's runtime caches
  (`.next/cache/images`, `favicon.ico.body`) are group-writable. With the default `022` they
  are mode `644` and the deploy user cannot clear `.next`, so the next build fails with
  `EACCES`.
- `albert` is a member of the `printforge` group. A non-root user cannot set the setgid bit
  for a group it does not belong to, which is what keeps this self-sustaining.

Consequently `deploy.sh` **never rsyncs `printforge.db`** (it is seeded server-side, and
replacing the file would destroy its ownership) and always passes `--no-perms` (plain
`rsync -a` rewrites the destination directory mode and strips setgid).

## Notes

This is a learning project built while following a Scrimba course, so some areas (e.g. pagination controls in [components/PaginationControls.tsx](components/PaginationControls.tsx)) are deliberately left as exercises — see [final_pagination_challenge.md](final_pagination_challenge.md) for the current open challenge.
