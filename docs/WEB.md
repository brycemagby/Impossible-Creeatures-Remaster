# The browser version

The game runs in a browser as well as on the desktop. Web builds use Godot's Compatibility renderer
(WebGL 2), set in `project.godot` (`renderer/rendering_method.web`), and are exported without
thread support, so any static web host can serve them without special headers.

Without threads, Godot 4.3 draws nothing in 3D once more than
`limits/spatial_indexer/threaded_cull_minimum_instances` objects (1000 by default) are in the
scene's view checks: it hands the check to worker threads that a threadless build doesn't have.
Each furry creature is dozens of small meshes, so a big fight crossed that line and the screen
showed only the sky's brown underside. `project.godot` raises the limit for web builds so the
check always runs on the main thread.

Online play needs a **relay server**, because browsers can't accept incoming connections. Both
players connect to the relay with a WebSocket and it passes the game's messages between them. The
relay is in `relay/`: a Cloudflare Worker with one Durable Object per room. The protocol is
described at the top of `relay/src/room.js`.

Everything here fits in Cloudflare's free plan: the website on **Cloudflare Pages** and the relay
on **Cloudflare Workers**. The free plan has daily limits (Durable Object requests and running
time); at the game's message rate that's roughly a few dozen 20-minute matches a day. If it ever
outgrows that, the Workers paid plan is $5 a month. Check Cloudflare's current pricing page for
the exact numbers.

## Publishing to Cloudflare (one-time setup)

After this, every push to `main` republishes the game and the relay automatically.

1. **Make a free Cloudflare account** at <https://dash.cloudflare.com/sign-up>. No card is needed.
2. **Pick your workers.dev name.** In the dashboard, open **Workers & Pages** (under Compute in the
   left menu). The first time, Cloudflare asks you to choose a subdomain such as
   `yourname.workers.dev`; pick anything. The relay will live at
   `impossible-creatures-relay.yourname.workers.dev`.
3. **Copy your Account ID.** It's on the right of the **Workers & Pages** overview page (also under
   any domain's Overview). Keep it for step 5.
4. **Make an API token** so GitHub can publish for you:
   - Click your profile icon (top right) → **My Profile** → **API Tokens** → **Create Token**.
   - Next to **Edit Cloudflare Workers**, click **Use template**.
   - Under **Permissions**, click **+ Add more** and pick **Account**, **Cloudflare Pages**,
     **Edit**.
   - Under **Account Resources**, pick your account. Under **Zone Resources**, pick
     **All zones** (you have none, which is fine).
   - Click **Continue to summary** → **Create Token** and copy the token. Cloudflare only shows it
     once.
5. **Give both to GitHub.** In the repository on GitHub: **Settings** → **Secrets and variables** →
   **Actions** → **New repository secret**, twice:
   - Name `CLOUDFLARE_API_TOKEN`, value: the token from step 4.
   - Name `CLOUDFLARE_ACCOUNT_ID`, value: the Account ID from step 3.
6. **Publish.** On GitHub, open **Actions** → **Deploy web version** → **Run workflow** (or push to
   `main`). It deploys the relay, exports the game pointed at that relay, and uploads the website.
   When it finishes, the game is at `https://impossible-creatures.pages.dev` (the last lines of the
   "Publish the website" step print the exact address).

Optional: a custom domain (about $10 a year from any registrar, or at cost through Cloudflare) can
be attached to the Pages project under **Workers & Pages** → the project → **Custom domains**.

### What the workflow does

`.github/workflows/deploy-web.yml`:

1. Runs the relay's tests and deploys it with `wrangler deploy`, reading its address from the output.
2. Downloads Godot 4.3 and its web export template (cached between runs).
3. Writes the relay's address into `project.godot` (`network/relay/url`) and exports the **Web**
   preset to `build/web/`.
4. Gzips the engine with `tools/pack_web.sh`. The engine is about 35 MB and Cloudflare Pages takes
   files up to 25 MB, so the site ships `index.wasm.gz` (about 8 MB) and the page unpacks it
   itself (a few lines of script in the Web preset's `html/head_include`).
5. Uploads `build/web/` to the Pages project `impossible-creatures`, creating it the first time.

Without the two secrets the workflow skips everything and says so, so forks don't fail.

## Running it on your own computer

You need Node.js 20 or newer for the relay.

```sh
cd relay
npm install
npm run local          # the relay on ws://localhost:8787 (or `npm run dev` for Cloudflare's own runtime)
```

Export the game from the editor (**Project** → **Export** → **Web** → **Export Project**, into
`build/web/`), or from the command line:

```sh
godot --headless --path . --export-release "Web" build/web/index.html
cd build/web && python3 -m http.server 8060
```

Open <http://localhost:8060> in two browser windows: host in one, join with the code in the other.
The desktop game uses the same local relay by default (`network/relay/url` in `project.godot` is
`ws://localhost:8787`), so a desktop copy can join a browser one too.

To point a game at a different relay without re-exporting:

- desktop: set the `IC_RELAY_URL` environment variable, e.g. `IC_RELAY_URL=wss://example.workers.dev`
- browser: add `?relay=wss://example.workers.dev` to the page address

Export templates: the editor offers to download them (**Editor** → **Manage Export Templates**).
