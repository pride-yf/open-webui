# 2 GB 共享服务器：OOM 后调整

2026-10-09：现有日志显示系统实际可见内存约 1613 MiB，Swap 为 0，Open WebUI 容器占用约 625 MiB，HostConfig.Memory 为 0。内核记录了 global_oom，被杀进程属于该容器。可以确认整机内存耗尽；尚不能证明内存泄漏、反复重启或某种具体 embedding 工作负载。高 PID、重启后的 RestartCount=0/OOMKilled=false 都不足以复原重启前进程关系。

## 1. 先停服务，给其他服务恢复余量

在实际部署目录执行（如果部署在其他路径，请替换）：

```bash
cd /opt/open-webui-repo/deploy/personal
docker compose stop -t 60 open-webui
./backup.sh
free -m
docker stats --no-stream
```

先停止再备份，脚本会保持该服务停止。记录停止后的 MemAvailable，观察其他服务高峰。不要删除聊天数据，也不要盲目停用云平台组件、数据库或密码管理服务。

## 2. 获取修正配置，修改已有 .env

```bash
git status --short
git pull --ff-only origin personal-deploy
nano .env
```

若 Git 拉取失败，先处理本地修改，不要继续执行或强制覆盖。将已有 OPEN_WEBUI_IMAGE 那一行改为下值，并添加资源参数（不要保留同名重复项）：

```dotenv
OPEN_WEBUI_IMAGE=ghcr.io/open-webui/open-webui:v0.11.4-slim
WEBUI_MEM_LIMIT=512m
WEBUI_MEMSWAP_LIMIT=768m
WEBUI_CPUS=1.0
```

Git 不会覆盖 .env，仅修改 .env.example 不会切换已有实例的镜像。512 MiB 是这个共享小机器的初始内存预算，不是该应用的实测最低内存，也不承诺启动成功。若需要超过预算才能运行，应先腾出资源或迁移/扩容。

Compose 的正确字段是服务级 `mem_limit`、`memswap_limit`。后者是内存加 swap 的总额，所以默认允许最多 512 MiB RAM + 256 MiB swap；没有宿主机 swap 时额外额度不可用，物理内存限制仍生效。`memswap_limit` 等于 `mem_limit` 表示容器禁用 swap。不要使用不存在的 `mem_swlimit`，也不要关闭 OOM killer。

默认固定一个 Uvicorn worker、CPU 上限 1 核，改用 `on-failure:3` 避免连续失败时无限重试。它不保证每个 OOM 都让主进程退出，也不因 unhealthy 自动重启；Docker daemon/主机重启后不会自动拉起此策略下的服务，需要手动 `docker compose up -d`。稳定运行后是否恢复开机自启，应另行评估。

## 3. 建议加 1 GiB swap 缓冲

先检查 `swapon --show`、`df -h /`、`findmnt -no FSTYPE /`。已有 swap 时先评估现状，不重复创建。以下适用于支持普通 swapfile 的 ext4/XFS；Btrfs 等文件系统需要专门方法。root 执行；若同名文件存在会停止，不能覆盖现有文件：

```bash
sudo bash <<'BASH'
set -euo pipefail
if [ -e /swap-openwebui ]; then
  echo '/swap-openwebui 已存在，请先检查，不覆盖。' >&2
  exit 1
fi
if swapon --noheadings --show=NAME | grep -q .; then
  echo '已有 swap，请先评估，不重复创建。' >&2
  exit 1
fi
umask 077
dd if=/dev/zero of=/swap-openwebui bs=1M count=1024 status=progress
chmod 600 /swap-openwebui
mkswap /swap-openwebui
swapon /swap-openwebui
if ! grep -Eq '^/swap-openwebui[[:space:]]' /etc/fstab; then
  printf '/swap-openwebui none swap sw 0 0\n' >> /etc/fstab
fi
swapon --show
BASH
```

确认有足够磁盘余量后再执行；中途失败时检查错误，保留现场，不直接反复执行。swap 是峰值缓冲，不是新增可持续使用的物理内存；持续换入换出仍可能让机器卡顿。先保留系统默认 swappiness，不根据这份日志直接设为 80。

## 4. 重建并验证限制

```bash
docker compose config --quiet
docker compose pull open-webui
# 以上两步均成功后再启动。
docker compose up -d --force-recreate open-webui
docker compose ps
docker inspect "$(docker compose ps -a -q open-webui)" \
  --format 'image={{.Config.Image}} memory={{.HostConfig.Memory}} memory_swap={{.HostConfig.MemorySwap}} cpus={{.HostConfig.NanoCpus}} restart={{json .HostConfig.RestartPolicy}} oom={{.State.OOMKilled}}'
docker stats --no-stream
free -m
```

预期 memory=536870912、memory_swap=805306368、cpus=1000000000，镜像结尾为 v0.11.4-slim。再测一次纯文本对话、一次长对话和手机访问。用 `vmstat 1 10` 观察 si/so（忽略第一行累计平均），用 `docker compose logs --tail=100 open-webui` 查看启动错误。不要贴出 API Key 或完整 .env。

起步预算建议：其他服务与系统的工作集 + Open WebUI 的 512 MiB 上限 + 至少约 300 MiB 运行余量，应能容纳在实际 1613 MiB 内存内。这只是规划，需包含高峰与内核开销。若 Open WebUI 停止后仍只能空出 600–700 MiB，当前机器不适合继续常驻它。若启动后持续换页、MemAvailable 长期低于约 200 MiB、出现 OOM 或服务退出，停止 Open WebUI，不要立即放宽内存上限。

## 5. slim 的功能边界

保留聊天、账号、SQLite、历史记录、服务端同步、本地附件存储和纯文本文件读取。镜像体积减少不等于运行内存按相同比例减少，具体驻留内存与数据量、模块加载和并发有关。

- PDF/Office 内容提取：需要外部 Tika/Docling/云端提取服务；纯 txt/md 等仍可读。
- 向量知识库：需要外部 embedding 服务和 PostgreSQL + pgvector；slim 不带标准版的本地 Chroma 客户端。当前实例绕过向量检索，不要为此在这台小机器上新增 PostgreSQL。
- 本地 Whisper、PyTorch embedding、local reranker：不提供；语音等改用外部 API。
- Git 源码依赖的插件及部分系统依赖：slim 不含相应运行工具，需要审查后选择别处运行。

已有数据库设置可能覆盖环境默认值。切换 slim 后如果日志显示仍请求本地 embedding、Chroma 或本地语音，先检查管理界面保存的设置；纯聊天先关闭这些功能，不通过安装一堆本地依赖补齐。大型文件全文也会增加内存与 API 上下文用量，先限制使用为文字、短材料和单路聊天。

## 6. 实际选择

优先短期试用“slim + 512 MiB 硬限制 + 有界 swap + 单 worker”。如果无法稳定启动或运行，保留备份并停止此服务；把 Open WebUI 搬到另一台主机，或者升级到 4 GB（仍需保留限制与实际监控）。给其他服务设置内存预算应依据各自峰值，不在未了解 PostgreSQL/Redis/sub2api 配置时套用任意小上限。

本次仅核对了上游 slim 镜像存在、官方功能说明和配置字段，并更新仓库；没有连接服务器验证运行内存。参考：https://docs.openwebui.com/getting-started/quick-start/ 和 https://docs.docker.com/compose/compose-file/05-services/#mem_limit
