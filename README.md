# Ops-HealthCheck: 轻量化无 Agent 巡检系统

本项目是一个基于 Shell 编写的自动化运维工具，通过 SSH 协议实现对多台远程服务器的健康状态监测。

---

## 📂 目录结构

建议您的项目保持以下结构，以确保脚本内的相对路径生效：
 
```text
ops_healthcheck/
├── bin/
│   └── healthcheck.sh        # 主执行程序 (需具备执行权限)
├── conf/
│   └── hosts.conf            # 巡检主机清单 (IP 或 Hostname)
├── logs/
│   └── <hostname>/           # 自动生成的按主机归档的日志
└── README.md                 # 项目文档
```

---

## 🛠️ 快速开始

### 1. 准备工作

*   **SSH 免密登录**：确保控制节点与被控节点已配置 SSH 免密登录。
*   **依赖工具**：确认本地已安装 curl（用于发送 Webhook 告警）。

### 2. 配置主机列表

编辑 conf/hosts.conf，每行填入一个目标 IP 或主机名：

```text
192.168.1.10
192.168.1.11
server-node-01
```

### 3. 配置告警（可选）

在 bin/healthcheck.sh 中填入您的 Webhook Token：

```bash
WEBHOOK_URL="https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN"
```

### 4. 运行巡检

```bash
# 1. 赋予执行权限
chmod +x bin/healthcheck.sh

# 2. 手动测试运行
./bin/healthcheck.sh
```

### 5. 部署自动化 (Cron)

建议通过 crontab -e 设置每 5 分钟自动执行一次：

```bash
*/5 * * * * /path/to/ops_healthcheck/bin/healthcheck.sh >/dev/null 2>&1
```

---

## 📊 巡检指标说明（可自定义阈值）
 
| 指标 | 监控逻辑 | 警告阈值 | 严重阈值 |
| :--- | :--- | :--- | :--- |
| **主机状态** | SSH 联通性测试 | - | - |
| **CPU 负载** | 1min 平均负载/核数 | 0.7 | 1.0 |
| **磁盘空间** | 根目录 / 使用率 | 80% | 90% |

