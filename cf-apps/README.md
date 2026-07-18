# CF Apps manifests

One `.manifest` file per CircuitForge product, sourced by
`lib/cf-apps.functions`. Each is a plain bash file defining these
variables (see any existing manifest for a concrete example):

```bash
app_name=""                    # matches the filename minus .manifest
app_desc=""                    # one line, shown in the selection menu
app_repo_url_github=""         # public CircuitForgeLLC mirror, used for the oem profile
app_repo_url_forgejo=""        # private Circuit-Forge Forgejo, used for the collaborator profile
app_available_profiles=()      # which of: oem collaborator
app_install_types=()           # which of: bare-metal docker podman, in menu display order
app_conda_env=""               # empty string if not applicable
app_env_template=""            # path relative to repo root, empty if none
app_needs_core=false           # true if circuitforge-core must be installed first
```

Optionally define hook functions for whichever install types the app
actually supports (skip the ones it doesn't):

```bash
app_setup_bare_metal() { local dir="$1"; ... }
app_setup_docker()     { local dir="$1"; ... }
app_setup_podman()     { local dir="$1"; ... }
```

`$1` is the app's clone directory. Prefer shelling out to the app's own
`install.sh`/`Makefile`/`docker compose` rather than reimplementing its
setup steps here — most CF products already have one.

If a hook is left undefined for an install type the app declares in
`app_install_types`, the dispatcher clones the repo and prints a warning
telling the user to finish setup manually, rather than silently doing
nothing.

See `circuitforge-plans/cf-node-bootstrap/superpowers/plans/2026-07-17-cf-apps-install-menu.md`
for the full design rationale, including the OEM/collaborator/orchard
provisioning-profile split.
