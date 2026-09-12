# iOS 真实截图

来源：iPhone 17 Pro Max 模拟器，`garden.pollen.microduck`，App-sim 已启动。

点按由 XCUITest 完成（`apps/microduck-ios/MicroDuckUITests`）。harness `ios perceive` 能截图；`ios interact` 的 AppleScript 点击需要本机辅助功能权限，当前环境没有，所以交互验收走 XCUITest。

| 文件 | 场景 |
|---|---|
| `l1-discover.png` | 发现页列出 duck-sim |
| `l1-discover-harness.png` | 同一页，harness `ios perceive` |
| `l1-pin.png` | 出厂 PIN |
| `l1-home.png` | 连上后的现场管理员首页 |
| `l1-interact.png` | 停止 / 坐下 / 摇杆禁用 |
| `l1-models.png` | 模型检查 |
| `l1-settings.png` | 设置 |
| `l1-wifi-scan.png` | FakeNet：Pollen、Cafe |
| `l1-wifi-badkey.png` | 错密码显示 BadKey |
