# iOS harness 点击截图

来源：iPhone 17 Pro Max 模拟器 + App-sim + TapBridge（`127.0.0.1:17433`）。

`scripts/harness-ios-l1` 用 harness `ios interact`（`id=`）或 `scripts/sim-tap` 真点按钮，不是静态稿。协议探针另见 `scripts/duck-app-sim probe`。

| 文件 | 点了什么 | 反应 |
|---|---|---|
| `01-discover.png` | — | 列出 duck-sim |
| `02-pin.png` | 点 duck-sim | 出厂 PIN |
| `03-home.png` | PIN 000000 + 认证 | 现场连接、一切正常 |
| `04-interact.png` | 底栏「互动」 | 摄像头占位（没有直播）、停止 / 坐下 / 摇杆禁用 |
| `05-stop-toast.png` | 「立即停止」 | toast：不走 BLE |
| `06-sit-toast.png` | 「坐下 / 站起」 | toast：不能经 BLE 下发 |
| `07-update-refused.png` | 「更新」 | 模拟环境不下载 |
| `08-rollback-confirm.png` | 「回到上一版本」 | 二次确认，写回退目标，不写恢复出厂 |
| `09-rollback-refused.png` | 「确认回退」 | 模拟环境不切换已安装版本 |
| `10-wifi-scan.png` | 设置 → 扫描 | Pollen、Cafe |
| `11-wifi-badkey.png` | Pollen + wrong-key | 密码不对（BadKey） |
| `12-wifi-cafe.png` | Cafe（开放） | 已加入 Cafe |