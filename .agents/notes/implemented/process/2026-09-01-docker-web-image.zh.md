# Agent Note: Docker 镜像通过 overlay 绑定全部网卡

Status: implemented

[English](2026-09-01-docker-web-image.md) | 中文

## Problem

`dsh web` 在容器内必须监听 `0.0.0.0`，Docker 的端口发布才能到达它。CLI（命令行界面）拒绝 `--host 0.0.0.0`，因为该 flag 会把未认证的 Web API——包括会运行 bash 的 `session.prompt`——暴露在调用它的机器的全部网卡上。贡献者仍然需要一份可重复的镜像来运行本次检出。

## Decision

多阶段 `Dockerfile` 安装并构建本仓库，然后以 `web --patch /opt/dsh/docker/web.cordis.yml` 启动构建后的 `dsh` bin。该 overlay 把 webserver 行的 config 替换为 `host: '0.0.0.0'`，并重述 `port: !!js ctx.webStartup.port ?? 3080`。`docker-compose.yml` 默认发布 `127.0.0.1:3080:3080`，把调用目录（或 `$DSH_WORKSPACE`）挂载到 `/workspace`，并把 `$DSH_HOME` 放在 named volume 上。运行时镜像不安装 bubblewrap，因此 Linux 沙箱选择使用 Landlock，而不是嵌套的、通常需要额外容器 capability 的 `bwrap`。

该镜像不是带认证的远程部署。可达性由 compose 的端口映射决定；`/api` 的浏览器信任栅栏仍接受 `127.0.0.1` 和 `localhost` 这类回环 Host 值。

## Alternatives considered

**`network_mode: host`。** 不作为默认：它在 Linux Engine 上可用，但不会在 macOS 或 Windows 的 Docker Desktop 上发布端口，而这正是本次检出必须服务的贡献者环境。

**再次允许 `dsh web --host 0.0.0.0`。** 不予采纳：恢复该 flag 会重新暴露 CLI 目前拒绝的、宿主机范围的未认证 API；overlay 只覆盖容器 NAT 路径。

**基于 `npx @deepseek-ai/dsh` 的镜像。** 不作为仓库 Dockerfile：它不会运行本次检出的源码，也会与同一棵树中的 lockfile 和 overlay 发生偏离。

**在容器内绑定 `127.0.0.1`。** 不予采纳，因为 Docker 发布的端口无法连接到容器命名空间中只监听回环的进程。

## Consequences

`docker compose up --build` 是本次检出文档化的容器路径。若把 compose 映射改为 `3080:3080`，未认证 API 会发布到宿主机的全部网卡；那仍是操作者的绑定策略，而不是认证层。全接口绑定也会选中 browse 目录选择器，这是容器能够提供的交互。构建后的 dump-config 冒烟测试固定 overlay 会在 webserver 行上落实 `host: '0.0.0.0'`。
