# 真实截图

harness 对着正在跑的 App-sim + L1 web 面截的，不是画廊稿。

来源：2026-09-12，`http://127.0.0.1:5173`，390×844。协议探针另见 `scripts/duck-app-sim probe`。

| 文件 | 场景 |
|---|---|
| `l1-discover.png` | 发现页列出 duck-sim |
| `l1-pin.png` | 出厂 PIN |
| `l1-home.png` | 现场管理员首页 |
| `l1-interact.png` | 互动：停止 / 坐下 / 叫一声；摇杆禁用 |
| `l1-models.png` | 模型检查；模拟环境不下载 |
| `l1-settings.png` | 设置与传输说明 |
| `l1-wifi-scan.png` | FakeNet：Pollen、Cafe |
| `l1-wifi-badkey.png` | 错密码显示 BadKey，不是网络没了 |

iOS 真点击截图：[`ios/`](ios/)（XCUITest）、[`ios-harness-clicks/`](ios-harness-clicks/)（TapBridge / harness）。web 按钮点击：[`harness-buttons/`](harness-buttons/)。身体孪生：[`web-body/`](web-body/)（`l1-body.yaml`：MuJoCo 画面 + 局域网坐下）。
