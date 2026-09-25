# Agent Note: Docker image binds all interfaces through an overlay

Status: implemented

English | [中文](2026-09-01-docker-web-image.zh.md)

## Problem

`dsh web` must listen on `0.0.0.0` inside a container for Docker port publishing to reach it. The CLI refuses `--host 0.0.0.0` because that flag would expose the unauthenticated Web API — including `session.prompt`, which runs bash — on every interface of the machine that invoked it. Contributors still need a repeatable image that runs this checkout.

## Decision

A multi-stage `Dockerfile` installs and builds this repository, then starts the built `dsh` bin as `web --patch /opt/dsh/docker/web.cordis.yml`. That overlay replaces the webserver row's config with `host: '0.0.0.0'` and restates `port: !!js ctx.webStartup.port ?? 3080`. `docker-compose.yml` publishes `127.0.0.1:3080:3080` by default, mounts the invoking directory (or `$DSH_WORKSPACE`) at `/workspace`, and keeps `$DSH_HOME` on a named volume. The runtime image does not install bubblewrap, so Linux sandbox selection uses Landlock rather than a nested `bwrap` that commonly needs extra container capabilities.

The image is not an authenticated remote deployment. Reachability is the compose port mapping; the `/api` browser-trust fence still accepts loopback Host values such as `127.0.0.1` and `localhost`.

## Alternatives considered

**`network_mode: host`.** Rejected as the default: it works on Linux Engine and does not publish ports on Docker Desktop for macOS or Windows, which is the contributor environment this checkout must serve.

**Allow `dsh web --host 0.0.0.0` again.** Rejected: restoring the flag would re-expose the host-wide unauthenticated API the CLI currently refuses; the overlay is scoped to the container NAT path.

**An `npx @deepseek-ai/dsh` image.** Rejected as the repository Dockerfile: it would not run this checkout's source and would drift from the lockfile and overlay in the same tree.

**Bind `127.0.0.1` inside the container.** Rejected because Docker's published port cannot connect to a loopback-only listener in the container namespace.

## Consequences

`docker compose up --build` is the documented container path for this checkout. Changing the compose mapping to `3080:3080` publishes the unauthenticated API on every host interface; that remains the operator's bind policy, not an authentication layer. All-interfaces bind also selects the browse directory picker, which is the interaction a container can serve. The built-bin dump-config smoke pins that the overlay materializes `host: '0.0.0.0'` on the webserver row.
