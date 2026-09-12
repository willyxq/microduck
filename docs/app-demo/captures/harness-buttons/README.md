# harness 点击验收（2026-09-12）

`l1-buttons.yaml` 对 `http://127.0.0.1:5173` 真点击，不是静态稿。

| 文件 | 点了什么 | 反应 |
|---|---|---|
| `01-discover.png` | — | 列出 duck-sim |
| `02-pin.png` | 点 duck-sim | 进入 PIN |
| `03-home.png` | PIN 000000 + 认证 | 现场连接、一切正常 |
| `04-interact.png` | 底栏「互动」 | 停止 / 坐下 / 摇杆禁用 |
| `05-stop-toast.png` | 「立即停止」 | toast：不走 BLE |
| `06-sit-toast.png` | 「坐下 / 站起」 | toast：不能经 BLE 下发 |
| `07-update-refused.png` | 「更新」 | 模拟环境不下载 |
| `08-wifi-scan.png` | 设置 → 扫描 | Pollen、Cafe |
| `09-badkey-toast.png` | Pollen + wrong-key | 密码不对（BadKey） |
