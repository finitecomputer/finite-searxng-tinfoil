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

The first release has been published:

```text
v0.0.1
ghcr.io/finitecomputer/finite-searxng-tinfoil@sha256:4221fc420bc524fbc2797b5fdc421f86e4abc5d2036d4521bdbf5893d79b3b70
```

For future releases, run the `Tinfoil Release` workflow with a new version:

```bash
gh workflow run tinfoil-release.yml -f version=v0.0.2
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
tinfoil login
printf '%s' '<random-secret>' |
  tinfoil secret create SEARXNG_SECRET --value-file -
tinfoil container create finite-searxng \
  --repo finitecomputer/finite-searxng-tinfoil \
  --tag v0.0.1 \
  --secret SEARXNG_SECRET \
  --staging
```

## Production Gate

Before production use, choose one:

- Keep the endpoint private to trusted runtimes through an access-controlled
  gateway.
- Add a token-gated wrapper in front of `/search`.
- Accept raw public SearXNG exposure only for short-lived experiments.
