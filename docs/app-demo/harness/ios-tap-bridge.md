# iOS harness 怎么点按钮

iOS Simulator **没有蓝牙**，也没有可靠的 Simulator 窗口辅助功能。`simctl` 能截图，不能点。AppleScript `process "Simulator" window 1` 在这台机器上失败。

所以点击走 **App 内回环桥**，不是点 Mac 屏幕。

```
harness ios interact / scripts/sim-tap
        │
        ▼
 http://127.0.0.1:17433   ← TapBridge（模拟器和 Mac 共用 loopback）
        │
        ▼
 AppModel.performHarnessAction("stop")
        │
        ▼
 和屏幕按钮同一条路径（toast / PIN / FakeNet）
```

| | |
|---|---|
| 监听 | `127.0.0.1:17433`（只绑 IPv4 loopback） |
| 健康 | `GET /health` |
| 点 id | `GET /tap?id=duck-sim` |
| 点坐标 | `GET /tap?x=215&y=320`（设计空间 430×932） |
| 输入 | `GET /type?text=000000` |
| 环境变量 | `MICRODUCK_TAP_BRIDGE`（默认上面这个地址） |

`pin-input` / `wifi-password` 是聚焦空操作；真正写入靠 `/type`。已知 id 和 web `data-testid` 对齐：`duck-sim`、`pin-submit`、`nav-*`、`stop`、`sit`、`quack`、`apply-update`、`wifi-scan`、`wifi-Pollen`、`wifi-join`。

## 怎么跑

```bash
scripts/duck-app-sim up
# 模拟器里已装并启动 garden.pollen.microduck
scripts/sim-tap health
scripts/harness-ios-l1
```

或直接让本机 harness 点（`~/Workspace/harness/harness` 的 `ios.ts` 要优先走桥；桥在线时不要回退 AppleScript）：

```bash
cd ~/Workspace/harness/harness
npx tsx src/cli.ts ios interact --device "iPhone 17 Pro Max" \
  --actions '[{"action":"tap","x":0,"y":0,"id":"stop"}]'
```

这只证明 **L1 按钮被点到、页面反应对**。协议层仍用 `scripts/duck-app-sim probe`。真机 BLE 以后另换传输，不换这些 id。
