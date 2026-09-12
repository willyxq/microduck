# L1 现场管理员验收单

没真鸭子也能签这一层。协议和页面分开验，截图不能代替 `probe`。

环境：App-sim `up`，web `http://127.0.0.1:5173`，iOS 模拟器已装 `garden.pollen.microduck`。

| # | 证明 | 命令 | 必须看到 |
|---|---|---|---|
| 1 | 协议孪生 | `scripts/duck-app-sim probe` | `authenticated: true`，`name: duck-sim`，`serial: SIM-0001` |
| 2 | 发现 / PIN / 首页 | `npx tsx src/cli.ts scenario …/l1-connect-sim.yaml` | 现场连接 |
| 3 | 底栏和「不是手柄」 | `…/l1-home.yaml` | 首页 / 互动 / 模型 / 设置；没有「手柄」 |
| 4 | 配网 | `…/l1-wifi.yaml` | Pollen 错密码 → BadKey；Cafe 开放网 → 已加入 Cafe |
| 5 | 按钮反应 | `…/l1-buttons.yaml` | 停止 / 坐下 toast；摄像头写「没有直播」；更新拒下；回退二次确认后拒切版本 |
| 6 | iOS 真点击 | `scripts/harness-ios-l1` | 同上，截图在 `captures/ios-harness-clicks/` |
| 7 | iOS 回归 | `xcodebuild test … ConnectSimTests` | 发现 → PIN → BadKey → Cafe |

场景 YAML 只打 web。iOS 走 TapBridge / XCUITest，不要用 AppleScript 点 Simulator 窗口。

不在本单：MuJoCo 身体、摇杆 / `teleop`、真机 BLE、第二层意图。
