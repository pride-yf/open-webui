# Open WebUI 当前状态与停用说明

记录日期：2026-10-14。本文记录已经确认的项目状态，以及在服务器上停用旧服务的方法。它不是服务器实时状态报告。

## 当前状态

| 项目 | 已知情况 |
| --- | --- |
| 原服务 | Open WebUI 已由使用者部署成功，曾通过公网域名访问；部署维护分支为本仓库的 `personal-deploy` |
| 服务器 | Ubuntu，已有 Docker Compose、Nginx 和域名 HTTPS；标称 2 GB，此前排查记录实际可见内存约 1613 MiB，且与其他服务共享 |
| 历史故障 | 曾因 Open WebUI 未设置容器内存上限发生整机 OOM；后续仓库加入 slim 镜像、内存上限和有限重启次数，详见 [OOM 后调整](./LOW-MEMORY.zh-CN.md)；服务器是否应用了全部最新配置需现场核对 |
| 后续方向 | 采用个人 Pi Study 项目，重点支持多渠道模型与思考档位、手动 Skill、可控搜索/图片工具、多设备会话同步，以及图片/PDF/语音接入 |
| 新项目进度 | 私有仓库 [pride-yf/pi-study](https://github.com/pride-yf/pi-study) 已建立并提交首版代码；模拟接口测试、桌面/手机网页检查，以及 GitHub 上 512 MiB 限制下的容器启动测试通过，镜像已发布 |
| 新服务上线状态 | 尚未确认在目标服务器完成部署，也未使用使用者的实际 API Key 验收；构建成功不代表已完成生产迁移 |
| 旧服务停用状态 | 已提供停止和关闭自动重启的操作说明；截至本文记录时，尚未收到服务器执行结果，**不能认定 Open WebUI 已停止** |
| 数据迁移 | 不自动删除或迁移原聊天、附件和配置；Pi Study 当前没有 Open WebUI 历史导入器，不能直接共用旧数据库 |

Pi Study 的 PDF 当前只通过支持文件输入的 Responses 模型处理；语音是外部转录和合成，不是实时语音通话。模型真实能力仍取决于所选渠道。新项目的 512 MiB 容器上限也不是整台共享服务器永不 OOM 的保证。

旧仓库保留用于配置追溯、备份与必要时恢复。迁移阶段应先停旧服务、核实内存余量，再运行新服务，避免两者同时常驻。本文不更改服务器状态，也不修改仓库现有 Compose 的默认启动行为。

## 1. 优先停止运行中的旧容器

以下命令在 Ubuntu 服务器执行，也可使用阿里云命令助手执行。需有 Docker 权限；命令助手若以 root 执行，无需另加 sudo。这里不需要先拉取 Git 仓库或升级镜像。

先列出容器：

```bash
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

找到镜像包含 `open-webui` 的目标容器，确认它是旧服务。**Compose 的实际容器名可能是 `open-webui-personal-open-webui-1`，不一定是 `open-webui`。** 不要选择其他业务容器。

下面仅以 `open-webui-personal-open-webui-1` 为例；如果实际名称不同，替换两条命令中的名称：

```bash
docker update --restart=no open-webui-personal-open-webui-1
docker stop -t 10 open-webui-personal-open-webui-1
```

第一条关闭 Docker 的自动重启策略，第二条请求正常停止，最多等 10 秒后 Docker 会强制结束仍未退出的进程。机器有余量时可把超时改成 60 秒；已有卡顿/OOM 风险时优先尽快释放内存。正在生成的回答可能中断。

这些命令保留容器、聊天记录、附件和数据目录。**不要执行 `docker compose down -v`、`docker volume rm`，也不要删除 `data/` 或 `.env`。**

如果确有多份旧 Open WebUI 实例，逐一确认名称和用途后停止，不要批量停止整机所有容器。

## 2. 验证已经停止

仍按实际名称替换：

```bash
docker inspect open-webui-personal-open-webui-1 \
  --format '状态={{.State.Status}} 自动重启={{.HostConfig.RestartPolicy.Name}}'
free -h
docker stats --no-stream
```

预期输出包含：

```text
状态=exited 自动重启=no
```

`docker stats` 不应再出现该运行实例。`free -h` 重点查看 available，并给其他业务的峰值和系统保留余量。不要仅凭停止命令已提交就判断完成，应保存本节实际结果。

关闭 Docker 重启策略不会阻止人为 `docker start`，也不会阻止外部 systemd、定时任务、监控或部署脚本重新启动容器。如果曾配置这些机制，还需停用其中针对旧 Open WebUI 的启动任务；本仓库未配置这些宿主机任务。

## 3. 防止之后 Compose 恢复旧重启策略

当前仓库 `compose.yaml` 中的默认策略是 `on-failure:3`。仅执行 `docker update --restart=no` 修改的是现有容器；未来 `docker compose up -d` 可能按 Compose 文件恢复策略并启动旧服务。

在**实际旧部署目录**操作。按原 Git 部署指南通常是：

```bash
cd /opt/open-webui-repo/deploy/personal
```

如果使用的是早期逐文件部署，则可能是 `/opt/open-webui`。不要在仓库根目录执行 Compose 命令，那里是上游的另一套配置。

建议在该目录新增本地 `compose.override.yaml`（若已存在则合并以下字段，保留原有其他配置）：

```yaml
services:
  open-webui:
    restart: "no"
```

默认执行 `docker compose` 时会合并该文件。将此本地文件加入仓库的 `.git/info/exclude`，避免意外提交；早期非 Git 部署不需要这一步。如果实际命令显式指定了 `-f compose.yaml`，应同时加上 `-f compose.override.yaml`，或在其实际使用的配置中设置 `restart: "no"`。

```bash
docker compose config --quiet
```

这里仅检查配置，不执行 `up` 或 `start`。即使设置 `restart: "no"`，手动 `docker compose up -d` 仍会启动服务，因此迁移后不要对旧项目运行启动命令。

## 4. 停止后备份旧数据

本项目把数据绑定在部署目录的 `./data`，并把配置保存在 `.env`。应保留完整数据和原 `WEBUI_SECRET_KEY`，不要把旧目录当作 Pi Study 的数据目录。

先确认旧容器已经停止，再进入旧部署目录执行：

```bash
./backup.sh
```

现有 `backup.sh` 会恢复执行备份前正在运行的服务；**先停止再备份**，它才会保持旧服务停止。备份包含 `.env`、`compose.yaml` 和整个 `data` 目录；若新增了本地 override 文件，需另外保存该文件。

将备份复制到服务器外的安全存储。归档含 API 凭据和聊天内容，不能提交进此公开仓库，也不要粘贴完整 `.env` 到问题报告。

## 5. Nginx 与切换到新服务

旧 Open WebUI 停止后，如果 Nginx 仍代理到原 `127.0.0.1:3000`，访问旧地址出现 502 是预期现象，不代表必须重新启动旧服务。

新 Pi Study 默认监听宿主机 `127.0.0.1:3010`。只有在新服务启动、健康检查和登录通过后，才按 [Pi Study 部署文档](https://github.com/pride-yf/pi-study/blob/main/docs/deployment.md) 更新该域名的代理目标，并执行：

```bash
sudo nginx -t
# 仅当检查成功后：
sudo systemctl reload nginx
```

这里假设 Nginx 运行在宿主机；如果 Nginx 运行在容器里，应使用两服务可达的受控 Docker 网络地址。不要为解决连接问题把 3000 或 3010 暴露到公网。

私有 Pi Study 仓库链接需要对应 GitHub 访问权限；旧 Open WebUI 仓库保持当前状态。

## 6. 如需恢复旧 Open WebUI

先停止新服务，重新检查内存预算。在旧部署目录确认 `.env`、完整 `data/`、镜像版本和资源限制均正确后，再有意执行：

```bash
docker compose up -d open-webui
docker compose ps
docker stats --no-stream
```

必要时恢复旧 Nginx 代理目标，并在配置检查通过后重载。`restart: "no"` 不影响手动启动，只是避免自动重启。恢复前仍需遵守 [低内存说明](./LOW-MEMORY.zh-CN.md)，不要撤掉内存上限。

## 后续状态记录

完成服务器操作后，补充执行日期和核验结果：旧容器名称、停止状态、重启策略、新服务是否部署、实际渠道是否验收、备份位置说明。不要记录密码、API Key、私钥或完整环境配置。未取得结果的事项继续标记“未确认”。
