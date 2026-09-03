# Ops-HealthCheck: 轻量化无 Agent 巡检系统

基于 Shell 编写的自动化运维巡检工具，通过 SSH 对多台远程服务器进行健康状态监测，无需在目标主机部署任何 Agent。巡检结果按主机与日期归档保存，指标超过阈值时通过 Webhook 推送告警。

**特性**

- **无 Agent**：仅依赖目标主机的 SSH 与基础命令，无需安装额外软件
- **配置与代码分离**：阈值、主机清单、Webhook 地址均外置到配置文件，敏感信息不入库
- **分级告警**：输出 OK / WARN / CRITICAL / UNKNOWN 四级状态，按最严重项汇总
- **面向 cron 设计**：显式声明 PATH、基于脚本位置计算绝对路径、文件锁防止任务堆叠

---

## 📂 目录结构

```text
Linux-Server-Health-Check/
├── bin/
│   └── healthcheck.sh            # 主执行程序（需具备执行权限）
├── conf/
│   ├── hosts.conf.example        # 主机清单模板
│   ├── settings.conf.example     # 巡检阈值与运行参数模板
│   ├── webhook.conf.example      # Webhook 告警地址模板
│   └── *.conf                    # 实际配置（已在 .gitignore 中排除）
├── docs/
│   └── alert.png                 # 告警效果示例
├── logs/
│   └── <hostname>/<date>.log     # 自动生成的巡检日志
└── README.md
```

---

## 🛠️ 快速开始

### 1. 准备工作

- **SSH 密钥认证**：控制节点需能通过密钥免密登录所有目标主机
- **控制节点依赖**：`ssh`、`curl`（推送告警）、`flock`、`timeout`、`awk`
- **目标主机依赖**：`hostname`、`nproc`、`uptime`、`df`、`free`、`pgrep`

### 2. 生成配置文件

配置文件不随仓库分发，需从模板复制：

```bash
cp conf/hosts.conf.example    conf/hosts.conf
cp conf/settings.conf.example conf/settings.conf
cp conf/webhook.conf.example  conf/webhook.conf
```

### 3. 配置主机清单

编辑 `conf/hosts.conf`，每行一个目标主机（IP、主机名或 SSH 别名），`#` 开头为注释：

```text
192.168.1.10
server-node-01
# 192.168.1.99   暂时下线
```

### 4. 配置巡检参数

编辑 `conf/settings.conf`：

```bash

WATCH_PROCS="sshd nginx"    # 监控的进程名，空格分隔；留空则跳过该检查

DISK_WARN=80                # 磁盘使用率阈值（%）
DISK_CRIT=90
MEM_WARN=80                 # 内存使用率阈值（%）
MEM_CRIT=90
INODE_WARN=80               # inode 使用率阈值（%）
INODE_CRIT=90
LOAD_WARN_PER_CORE=0.7      # 每核心负载阈值
LOAD_CRIT_PER_CORE=1.0
LOG_RETENTION_DAYS=7        # 日志保留天数

```

### 5. 配置告警

在 `conf/webhook.conf` 中填入 Webhook 链接：

```bash
https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN
```

### 6. 运行

```bash
chmod +x bin/healthcheck.sh
./bin/healthcheck.sh
```

建议先手动运行，确认 SSH 连接、日志输出与告警推送均正常后再配置定时任务。

### 7. 部署定时任务

```bash
crontab -e
```

```cron
*/5 * * * * /absolute/path/to/Linux-Server-Health-Check/bin/healthcheck.sh >/dev/null 2>&1
```

将路径替换为项目实际绝对路径，用 `crontab -l` 确认已生效。

---

## 📊 巡检指标

| 指标 | 采集方式 | 判定逻辑 | 默认 WARN | 默认 CRIT |
| :--- | :--- | :--- | :--- | :--- |
| **主机可达性** | `ssh hostname` | 连接失败即判定失联 | — | 失联 |
| **CPU 负载** | `uptime` 1 分钟平均值 | 按 CPU 核数归一化 | 0.7 / 核 | 1.0 / 核 |
| **内存使用率** | `free -m` | used / total | 80% | 90% |
| **磁盘使用率** | `df -h /` | 根分区已用百分比 | 80% | 90% |
| **inode 使用率** | `df -i /` | 根分区 inode 已用百分比 | 80% | 90% |
| **关键进程存活** | `pgrep -x` | 任一进程缺失即判定严重 | — | 进程不存在 |

**负载归一化**：4 核主机 1 分钟负载为 `3.2`，归一化后为 `3.2 / 4 = 0.8`，超过 WARN 阈值 `0.7`，触发警告。这样同一套阈值可适用于不同规格的机器。

**为什么同时监控 inode**：block 与 inode 是两个独立配额。当目录下堆积大量小文件时，`df -h` 可能显示磁盘充足，但因 inode 耗尽而无法创建新文件，报 `No space left on device`。

**状态汇总**：单台主机的最终状态取所有检查项中最严重的一项。状态码对齐 Nagios 插件规范（OK=0 / WARN=1 / CRITICAL=2 / UNKNOWN=3）。

---

## 🔔 告警效果

磁盘使用率超过阈值时，钉钉机器人收到的告警：

![钉钉告警示例](docs/alert.png)

---

## 📁 日志

日志按主机与日期分目录存储于 `logs/<hostname>/<YYYY-MM-DD>.log`，超过 `LOG_RETENTION_DAYS` 天的文件在每次巡检结束后自动清理。

---

## 🔒 安全建议

- 使用专用低权限账号执行远程巡检，避免使用 root
- 限制配置文件与 SSH 私钥权限：`chmod 600 conf/*.conf ~/.ssh/id_*`
- `conf/*.conf` 已在 `.gitignore` 中排除，请勿将含真实令牌的配置提交到仓库
- Webhook 地址包含访问令牌，泄露后任何人都可向该群组推送消息，如有泄露请立即重置
