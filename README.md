# cf-node-bootstrap

**Pyr0ball's Reductive [bash] Library (PRbL) Auto-Installer** — plus CircuitForge node provisioning.

---

Bootstraps a new machine with a sane bash environment and optionally provisions it as a CircuitForge product node or GPU worker.

Depends on [PRbL](https://github.com/pyr0ball/PRbL-bashrc.git). Clone recursively:

```bash
git clone --recurse-submodules https://github.com/CircuitForgeLLC/cf-node-bootstrap.git
cd cf-node-bootstrap/
```

---

## What it installs

- `PRbL` — pluggable bash functions and scripting helpers
- A `~/.bashrc.d/` drop-in directory for modular shell config
- An informative login splash screen (quickinfo)
- Vim color scheme and formatting
- Core dependencies: `git`, `vim`, `lm-sensors`, `curl`, `net-tools`, `bc`

---

## Install

### Basic (current user)

```bash
./install.sh -i
```

Installs to `~/.local/share/prbl`. During install you will be prompted to:

1. Install optional **extras** (e.g. dev-tool cache redirect for machines with a separate `/devl` disk)
2. Provision this node for **CircuitForge apps** (see Provisioning Profiles below)

### Global (all users, requires root)

```bash
sudo ./install.sh -i
```

Installs to `/usr/share/prbl`.

---

## Flags

| Flag | Description |
|------|-------------|
| `-i` / `--install` | Install PRbL and run provisioning menus |
| `-u` / `--update` | Update an existing install |
| `-d` / `--dependencies` | Install package dependencies only |
| `-D` / `--dry-run` | Show what would happen without making changes |
| `-r` / `--remove` | Remove the PRbL install |
| `-f` / `--force` | Remove then reinstall |
| `-F` / `--force-remove` | Remove without reinstalling |
| `-h` / `--help` | Print usage |

---

## Provisioning Profiles

After the base PRbL install, the installer offers to set up CircuitForge apps on this node. You will be asked to pick a profile, which controls which apps are available and which remote they are cloned from.

### OEM / customer node

For end-user machines. Clones apps from the **public GitHub mirror** (`CircuitForgeLLC`). Only apps with `oem` in their `app_available_profiles` are shown.

Use this for:
- A customer deploying a licensed CircuitForge product
- A self-hoster running a public release

### Collaborator node

For contributors and internal team machines. Clones apps from the **private Forgejo** instance (`git.opensourcesolarpunk.com`). All apps with `collaborator` in their `app_available_profiles` are shown, including pre-release and internal tools.

Use this for:
- A developer working on CircuitForge products
- An internal machine with Forgejo access

### Orchard-join node

For GPU worker nodes joining an existing `cf-orch` orchard. Clones `circuitforge-orch` from Forgejo and hands off to its own interactive installer — when prompted, choose the `agent` topology and have your coordinator's URL ready.

Use this for:
- Adding a GPU machine to an existing CircuitForge compute cluster
- Xander's orchard nodes or any remote worker joining a coordinator

---

## Optional Extras

After the base install, you will be prompted to select extras. Each extra is a standalone install script in `extras/`.

| Extra | Purpose |
|-------|---------|
| `model-cache-redirect` | Redirects pip, whisper, clip, and Hugging Face caches from `~/.cache` to `/devl/user-cache` (for machines with a separate fast disk at `/devl`). Skips cleanly on machines without a separate `/devl` mount. |

---

## CF Apps manifests

Each CircuitForge product has a `.manifest` file under `cf-apps/`. These are plain bash files declaring the app name, description, repo URLs, supported provisioning profiles, and install types (bare-metal, Docker, Podman). See `cf-apps/README.md` for the full schema.

Available apps:

| App | Description |
|-----|-------------|
| `circuitforge-core` | Shared scaffold library required by most CF products |
| `peregrine` | LLM-powered job discovery and application pipeline |
| `kiwi` | Pantry tracker with barcode/receipt scanning and recipe suggestions |
| `snipe` | Auction trust-scoring for eBay and estate sales |
| `turnstone` | Log diagnostics tool |
| `linnet` | Real-time tone annotation product |
| `pagepiper` | Document/rulebook RAG tool |

---

## Planned

- Expanded automatic OS detection and package management (non-Debian/Ubuntu)
- Modular login splash page
