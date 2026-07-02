# finite SearXNG Tinfoil Prototype

This directory is a public-repo-ready bundle for the first SearXNG-only
Tinfoil Containers prototype.

Do not deploy it from `finite-search` directly. Tinfoil requires
`tinfoil-config.yml` to live at the root of a public GitHub repo so the enclave
measurement can be verified by clients.

## What This Runs

- One SearXNG container.
- JSON search enabled.
- The same narrowed engine set proven on `lat2`.
- Open outbound egress so SearXNG can reach public search engines.
- Tinfoil shim routes only `/search` and `/search/*`.
- Healthcheck uses local `/healthz`, not a real search query.
- `SEARXNG_SECRET` is a Tinfoil secret, not a public env var.

This is a staging prototype. SearXNG does not provide request authentication by
itself, so do not treat a raw public SearXNG endpoint as production-ready.

## Public Repo Setup

This repo is already the public Tinfoil config repo:

```text
finitecomputer/finite-searxng-tinfoil
```

The release workflow rewrites the placeholder image in `tinfoil-config.yml`
with the digest-pinned GHCR image for this repo:

```yaml
image: "ghcr.io/finitecomputer/finite-searxng-tinfoil:placeholder"
```

## Local Smoke Before Tinfoil

From `finite-search`:

```bash
scripts/smoke-tinfoil-searxng-bundle.sh
```

That builds the local image and proves:

```text
http://127.0.0.1:<port>/search?q=open+source&format=json
```

returns non-empty JSON results.

## Release

The latest published release is:

```text
v0.0.3
ghcr.io/finitecomputer/finite-searxng-tinfoil@sha256:53033ff33864679d3ff54fa16c16a5e64b50eb9cdd17d830596c4f00616f4213
```

The next candidate release is `v0.0.4`. It updates the top-level Tinfoil
enclave shape to `cvm-version: 0.10.4`, `cpus: 8`, and `memory: 16384` to match
the current public Tinfoil web-search/doc-upload examples and the published
`small_0d_new` hardware profile shape.

For future releases, run the `Tinfoil Release` workflow with a new version:

```bash
gh workflow run tinfoil-release.yml -f version=v0.0.4
```

The workflow:

1. Builds and pushes `ghcr.io/<owner>/<repo>`.
2. Rewrites `tinfoil-config.yml` with the pinned image digest.
3. Creates the release tag.
4. Dispatches the publish workflow that measures and attests the image.

## Tinfoil Deploy

In the Tinfoil dashboard:

1. Add a `SEARXNG_SECRET` secret with a random value.
2. Create a new container from the public repo and release tag.
3. Deploy in staging first.
4. Smoke through the verified Tinfoil proxy, not plain public `curl`:

```bash
tinfoil container connect finite-searxng \
  -p 3301
```

Then, in another shell:

```bash
curl -fsS 'http://127.0.0.1:3301/search?q=open+source&format=json' |
  jq '.results | length'
```

CLI equivalent once an org admin key is available:

```bash
tinfoil login --api-key admin_...
export SEARXNG_SECRET_VALUE="$(openssl rand -hex 32)"
scripts/deploy-staging.sh v0.0.4
unset SEARXNG_SECRET_VALUE
```

Manual form:

```bash
tinfoil login
printf '%s' '<random-secret>' |
  tinfoil secret create SEARXNG_SECRET --value-file -
tinfoil container create finite-searxng \
  --repo finitecomputer/finite-searxng-tinfoil \
  --tag v0.0.4 \
  --secret SEARXNG_SECRET \
  --staging
```

GitHub Actions equivalent:

1. Add `TINFOIL_API_KEY` as a repository or organization secret.
2. If `SEARXNG_SECRET` does not already exist in Tinfoil, also add
   `SEARXNG_SECRET_VALUE` as a secret.
3. Run the `Tinfoil Deploy - Staging` workflow with tag `v0.0.4`.

## Current Deployment

`finite-searxng` is live at:

```text
https://finite-searxng.finite.containers.tinfoil.dev
```

Current state:

```text
tag: v0.0.2
status: ready
mode: non-staging
resources: 2 CPU / 8192 MiB
```

Direct public smoke passed:

```bash
curl -fsS \
  'https://finite-searxng.finite.containers.tinfoil.dev/search?q=open+source&format=json' |
  jq '.results | length'
```

`finite-searxng-medium` is also deployed as a staging experiment at:

```text
https://finite-searxng-medium.finite.containers.tinfoil.dev
```

Its current state:

```text
tag: v0.0.3
status: ready
mode: staging
resources: 4 CPU / 16384 MiB
```

Direct public smoke also passed for the medium experiment.

The verified proxy path is not passing yet. Both `tinfoil container connect`
and the standalone `tinfoil-proxy` fail with:

```text
failed to verify enclave: verifyHardware: failed to verify hardware measurements: no matching hardware platform found
```

`v0.0.2` changed `cvm-version` from `0.10.1` to `0.10.0` to test whether the
networking CVM version was the issue. The app still runs, but attested proxy
verification still fails.

`v0.0.3` increased top-level resources from `2 CPU / 8192 MiB` to
`4 CPU / 16384 MiB` to test whether a different CPU-only platform profile would
match Tinfoil's hardware measurements. It did not.

Deeper follow-up found that `4 CPU / 16384 MiB` is not one of the exact
published hardware profile shapes in `tinfoilsh/hardware-measurements@v0.0.35`.
The public profiles include `mini_0d` at `4 CPU / 4096 MiB` and `small_0d_new`
at `8 CPU / 16384 MiB`; Tinfoil's own `confidential-websearch` and
`confidential-doc-upload` repos also use `cvm-version: 0.10.4` with
`8 CPU / 16384 MiB` and open egress. `v0.0.4` is prepared to test that shape.

Verifier evidence from `go run ./verifier/examples/verifier`:

```text
finite-searxng-medium runtime MRTD:
7357a10d2e2724dffe68813e3cc4cfcde6814d749f2fb62e3953e54f6e0b50a219786afe2cd478f684b52c61837e1114

finite-searxng-medium runtime RTMR0:
492006d8554a37287c46a04d4ac6c3339a463453d3c355756af39f0150e37424ccc98d0c2821732b40670393a5182e58
```

That MRTD/RTMR0 pair is not present in `tinfoilsh/hardware-measurements`
release `v0.0.35`, so hardware verification fails before code measurement
comparison. The existing `kimi-k2-6` container on the same TDX/H200 host
verifies and matches `extra_large_1d_new`.

Treat this as a Tinfoil verifier/platform follow-up until `v0.0.4` is deployed
and verified through `tinfoil-proxy`, not as production-ready.
Also note that the current verifier resolves the repo's latest release; keep the
GitHub "latest" release aligned with whichever deployed tag is being tested.

## Production Gate

Before production use, choose one:

- Keep the endpoint private to trusted runtimes through an access-controlled
  gateway.
- Add a token-gated wrapper in front of `/search`.
- Accept raw public SearXNG exposure only for short-lived experiments.
