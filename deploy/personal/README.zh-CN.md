# 个人 Open WebUI：Ubuntu + Docker Compose + 已有 Nginx

基线：Open WebUI **v0.11.4**（2026-10-08 核对的上游最新稳定版）。单用户、API 对话、服务端保存历史记录与附件。使用官方标准镜像，不在服务器编译源码。

## 1. 服务器上的依赖

| 组件 | 是否需要另装 | 说明 |
|---|---|---|
| Docker Engine + Compose v2 | 已有，检查版本即可 | 本指南使用 `docker compose`，不是旧版 `docker-compose` |
| Nginx + 已有域名 HTTPS 证书 | 已有 | 支持流式输出和 WebSocket，见配置片段 |
| curl、openssl、tar、Bash | Ubuntu 通常已有 | 下载配置、生成密钥和备份；缺少时 `sudo apt-get install curl openssl tar` |
| Open WebUI 官方 Docker 镜像 | 首次拉取 | 唯一新增的长期运行服务 |
| SQLite | 不需要单独安装 | 随应用镜像提供，数据库在 `./data` 下 |
| Python、Node.js、Git | 不需要在宿主机安装 | 运行依赖在镜像内；部署无需源码或 Git |
| Ollama、GPU/CUDA、Redis、PostgreSQL、独立向量数据库 | 当前不需要 | 不引入这些服务 |
| 外部模型 API | 需要可用账号和 API Key | 服务器需要能访问供应商地址；模型调用单独计费 |

建议起步 2 vCPU、4 GB RAM，预留至少 20 GB 磁盘给镜像、聊天附件和备份；这是运维建议，不是官方最低配置。标准镜像包含本地文档/音频处理依赖与缓存模型，明显大于 slim。此处采用标准版以便后续扩展，避免把 slim 当成功能完全相同的替代品。

网络依赖：拉取镜像需要访问 `ghcr.io` 及其下载端点；获取配置需要访问 GitHub；聊天需要访问模型供应商。默认禁止 Hugging Face 在线下载和 embedding 模型自动更新，不影响外部聊天 API。以后启用新的本地 embedding、语音或 OCR 功能时，可能需要开放模型下载或接入相应第三方 API。Docker 拉取镜像与容器访问模型 API 使用不同的网络路径，宿主机 shell 的代理不一定自动对二者生效。

## 2. 获取配置，无需克隆仓库

用具备 Docker 权限的服务器账号执行；下面以 root 运维为例：

```bash
sudo -i
install -d -m 700 /opt/open-webui
cd /opt/open-webui
BASE=https://raw.githubusercontent.com/pride-yf/open-webui/personal-deploy/deploy/personal
for f in compose.yaml .env.example backup.sh nginx-location.conf.example README.zh-CN.md; do
  curl --fail --show-error --location "$BASE/$f" --output "$f" || exit 1
done
cp -n .env.example .env
chmod 600 .env
chmod 700 backup.sh
```

也可以把本部署包直接上传到 `/opt/open-webui`。配置更新前保留现有 `.env` 和 `data`，不要用示例覆盖实际配置。

## 3. 首次启动

分别生成登录签名密钥和初始管理员密码：

```bash
openssl rand -hex 32
openssl rand -hex 20
nano .env
```

填写：

- `WEBUI_URL`：实际完整 HTTPS 域名，例如 `https://chat.yourdomain.com`，建议独立子域名。
- `WEBUI_SECRET_KEY`：第一条命令生成的随机值。长期保存，升级不能随意更换。
- `WEBUI_ADMIN_EMAIL`：你的管理员登录邮箱。
- `WEBUI_ADMIN_PASSWORD`：第二条命令生成的随机密码。
- `OPENAI_API_BASE_URL` / `OPENAI_API_KEY`：可以在此填写；也可以先留空 Key，启动后在管理设置的 Connections 中配置。名称虽为 OPENAI，但可接入兼容 API，按供应商文档填写地址。

`.env` 中含 `$` 或 `#` 的密钥请使用单引号包裹，避免 Compose 插值或注释解析。不要上传 `.env`、备份或数据目录到 GitHub。

```bash
docker compose version
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:3000/health
```

首次初始化可能需要一段时间。健康接口暂未就绪时，用 `docker compose logs --tail=100 open-webui` 排查并稍后重试。不要通过删除 `data` 解决启动问题。

管理员环境变量只在空数据库时用于创建管理员，不是已有账号的密码重置方式。先确认 `.env` 中管理员信息已填写，再把域名反向代理公开到这个实例，避免尚未创建管理员时暴露初始化页面。

## 4. Nginx 与多端访问

`nginx-location.conf.example` 是配置片段，放到该域名已有的 HTTPS `server {}` 中，保留你原来的证书和域名设置。它处理流式回答与 WebSocket，不需要安装额外 Nginx 模块。

```bash
sudo nginx -t
# 仅当上一步成功后执行：
sudo systemctl reload nginx
```

默认 Open WebUI 只绑定 `127.0.0.1:3000`，适用于 Nginx 直接运行在 Ubuntu 宿主机的情况。若 Nginx 运行在 Docker 容器中，容器里的 127.0.0.1 不代表宿主机，不能照抄此 upstream：把两个服务连接到同一个用户定义 Docker 网络，并用 `http://open-webui:8080` 代理；取消不需要的宿主机端口映射。不要为了绕过网络问题直接把 3000 端口开放到公网。

用域名登录后，确认管理员账号正常、注册关闭。然后清空 `.env` 中 `WEBUI_ADMIN_EMAIL` 和 `WEBUI_ADMIN_PASSWORD`，再次执行 `docker compose up -d` 移除容器里的初始化密码。账号和密码哈希已保存在数据库中。

电脑、手机和平板访问同一 HTTPS 域名并登录同一账号，即可读取服务端历史记录。移动端可添加到主屏幕。请实际验证长回答期间锁屏、断网与设备切换的行为；历史同步不等于任何中断下生成都能自动恢复。

## 5. 配置与学习使用

本配置保留管理界面设置的数据库持久化。**管理界面已保存的设置可能优先于环境变量**：首次接入之后，通常在管理界面改 API 地址/Key；不要认为修改 `.env` 一定覆盖已有数据库配置。修改镜像、端口、签名密钥等启动配置仍需要重建容器。

默认关闭 Ollama、代码执行、代码解释器，以及自动标题/标签/追问/输入补全，减少纯聊天场景的额外模型调用。标题可以手动改，也可以按需在管理界面重新开启。工具、终端和外部 MCP 没有额外接入。

可在 Workspace 中创建“讲解”“引导”“检验”三个模型预设，只配置提示词与所需模型。短章节先以完整内容辅助对话，确有大量资料时再启用知识库。

## 6. 备份与版本升级

备份会短暂停止 Open WebUI，保证 SQLite 和附件的一致性，然后恢复之前正在运行的服务：

```bash
cd /opt/open-webui
./backup.sh
```

备份包含 `.env`、Compose 文件和完整 `data`，因此也包含密钥与聊天内容。至少保留一份服务器外副本。备份脚本不会自动删除历史备份，请按磁盘容量自行制定保留周期。

升级时先阅读目标版本 release notes，确认插件兼容性，并核对 GitHub 发布的正式版本号，不使用 `main` / `latest` 浮动标签。步骤如下：

```bash
cd /opt/open-webui
./backup.sh
# 记下刚生成的备份路径；只有备份成功才继续。
nano .env
# 只把 OPEN_WEBUI_IMAGE 改为已核实的新稳定版本，例如 ghcr.io/open-webui/open-webui:vX.Y.Z。
docker compose config --quiet
docker compose pull open-webui
# 只有拉取成功才继续。
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:3000/health
```

再验证登录、历史对话、一次真实模型回答、手机访问与附件。不要配置自动更新生产容器；数据库迁移可能让旧镜像无法直接读取新数据库。

## 7. 回退必须同时恢复数据和旧配置

先选定升级前的可信备份。以下操作会恢复到该备份的时间点；之后的新对话不在恢复数据中。先停止实例，再保留失败现场，最后恢复：

```bash
cd /opt/open-webui
docker compose stop -t 60 open-webui
RECOVERY_DIR="recovery-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 700 "$RECOVERY_DIR"
mv data "$RECOVERY_DIR/data"
cp .env compose.yaml "$RECOVERY_DIR/"
# 把路径替换为升级前备份，不要使用不明来源的压缩包。
tar -xzf backups/open-webui-YOUR-BACKUP.tar.gz
docker compose config --quiet
docker compose pull open-webui
docker compose up -d
```

恢复会取回旧版本 `OPEN_WEBUI_IMAGE`、原密钥与旧数据库。不要仅切换旧镜像而继续使用已迁移的数据库。恢复成功前保留 `recovery-*` 目录。

## 8. Fork、升级与扩展的分工

- `main`：保留上游跟踪用途，不直接部署它的浮动镜像。
- `personal-deploy`：从 v0.11.4 创建的个人分支，新增 `deploy/personal` 部署文件和一个手动镜像构建工作流，应用源码不作功能修改。
- 初期运行上游官方固定版本镜像。Fork 的同步、部署配置的更新、生产容器的升级是三个独立动作。
- 优先通过提示词、模型预设、Functions/Filters/Actions 扩展。导出并审核自己的插件源码，放入 `extensions` 等版本管理目录；运行时配置及密钥留在服务器。
- 只有需要修改应用源码时，才从个人分支创建功能分支并通过 PR 合并。执行手动镜像构建工作流会生成自己命名空间下、以提交 SHA 标识的镜像；把实际镜像地址写进服务器 `.env` 后才会部署。
- 个人构建默认生成 `linux/amd64` 镜像。如果服务器是 ARM64，构建前需改用相应 runner/平台设置；上游官方镜像的多架构支持与这个自定义构建不是同一回事。GHCR 新创建的包可能是私有的：自用服务器需配置有 `read:packages` 权限的登录，或明确把不含私人内容的镜像包设为公开。
- 源码升级：以个人分支为基础，把指定的上游稳定版合入升级分支，处理冲突、测试后再合并。GitHub 的 Sync fork 跟踪上游默认分支，不等同于选择稳定发布版本，不要把同步操作当作生产升级。
- 本次禁用 fork 继承的上游工作流；只保留个人手动构建工作流可用。不要恢复所有继承工作流来实现更新。

公开仓库的 fork 也是公开的。业务密钥、私人笔记、聊天数据库、附件及其备份均不应进入仓库。以后若需要私有的业务代码或私有插件，可独立放到私有仓库，通过插件或构建过程接入。

## 9. 验证边界与参考

部署文件按上述稳定版源码中的环境变量及官方部署说明准备，并进行静态检查。尚未登录你的服务器，未进行真实 Docker 启动、Nginx 配置加载或模型 API 调用测试；请按第 3、4、6 节完成实际验证。

- 上游发布：https://github.com/open-webui/open-webui/releases
- 官方文档：https://docs.openwebui.com/
- 环境配置：https://docs.openwebui.com/reference/env-configuration/
- 扩展说明：https://docs.openwebui.com/features/extensibility/plugin/
- 许可证：https://github.com/open-webui/open-webui/blob/main/LICENSE
