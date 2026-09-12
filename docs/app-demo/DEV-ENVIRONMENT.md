# MicroDuck App 开发环境方案

状态：方案 · 日期：2026-09-12 · 从 `app-checkpoint-2026-09-12` 续做

产品方向已经冻结，见 [`control-app-evolution.md`](../design/control-app-evolution.md)。本文只回答：**在没有真鸭子的 Mac 上，怎么开发、怎么自动验收、真鸭子来了怎么切过去。**

虚拟鸭子的机制和切换步骤在 [`SIM-DUCK.md`](SIM-DUCK.md)。不要在这里重写三层产品设计。

## 1. 开发目标（不变）

第一层现场管理员，不是手机手柄。

当前只做、也只验收这些：

- 发现、PIN、配网、健康、模型检查 / 更新 / 回退
- 互动页：摄像头、立即停止、坐下 / 站起、叫一声
- 摇杆禁用，直到 `teleop` 存在
- 运动控制不走 BLE；实体手柄继续负责盲操

协议对齐原作者已经写完的机器人侧，不另写 BLE 方言。App 只缺客户端。

## 2. 机器怎么分工

| 机器 | 角色 | 不要在上面做 |
|---|---|---|
| **这台 Mac**（`william's Laptop`） | App、Xcode、harness、App-sim、以后的真机 BLE | 不要重做信息架构 |
| **Ubuntu**（`william-MS-7E07`） | 已冻结的设计和画廊；文档应急 | 不要写 iOS / CoreBluetooth |
| **真鸭子** | 还没有。来了之后只换传输，不换协议 | 不要等它才开始写 App |

仓库：

| | |
|---|---|
| fork | `https://github.com/willyxq/microduck` |
| 上游 | `https://github.com/pollen-robotics/microduck` |
| 设计冻结点 | 标签 `app-checkpoint-2026-09-12`（提交 `626383c`） |
| 设计分支 | `cursor/microduck-control-app-design-85d7` |
| 本方案分支 | 从该标签切出，不要从 `main` 重做 |
| 画廊 | https://willyxq.github.io/microduck/app-demo/ |

HANDOFF 表里曾写提交 `1738ba5`。那是三层演进归档；标签在其后两笔文档提交。续做以**标签**为准。

## 3. 本机盘点（2026-09-12 实测）

已装且可用：

| 工具 | 版本 / 状态 |
|---|---|
| Xcode | 26.1.1 |
| Swift | 6.2.1 |
| Rust | 1.96.1 |
| Node / npm | 24.11.0 / 11.6.1 |
| Flutter | 3.41.5（本机其它 App 用过 harness） |
| Docker | 28.5.1 |
| 蓝牙 | 开着（`50:A6:D8:C2:14:9F`） |
| 本仓库测试 | 上游 roadmap 写过：Mac 上 `cargo test --workspace` 可通过 |

还缺、或现在连不上：

| | |
|---|---|
| 真鸭子 | 没有，系统蓝牙列表里看不到 `duck-*` |
| iPhone **mickey**（iOS 26.5） | Xcode 里 Offline |
| `duckctl` | 源码在，本机还没编过 |
| App 工程 | L1 web 面在 `apps/microduck-app`；**iOS SwiftUI** 在 `apps/microduck-ios`（模拟器，`garden.pollen.microduck`）。还不是 TestFlight 包 |
| App-sim | 已落地：`scripts/duck-app-sim` + `sim-btd`，见 [`SIM-DUCK.md`](SIM-DUCK.md) |

结论：Mac 够写 App 和跑 harness。不够做「真机 BLE 探针」。在鸭子到货前，探针改打 App-sim：同一组调用 `hello` / `authenticate` / `system.info`。

## 4. 文档地图

先读机器人侧原文，再读我们的产品稿。

| 顺序 | 文件 | 谁拥有 |
|---|---|---|
| 1 | [`app-path-design.md`](../design/app-path-design.md) | BLE、`btd`、`configd`、扫描 / 配对 / 配网 |
| 2 | 上游分支 `docs-mobile-app-approach` 的 `docs/design/mobile-app.md` | App 先是设置工具；建议 Tauri + `duck-ipc-proto` |
| 3 | [`updater-design.md`](../design/updater-design.md) | 手机只触发更新，鸭子用自己的 Wi-Fi 下载 |
| 4 | [`remote-webrtc.md`](../design/remote-webrtc.md) | 视频和 `control` 已有，`teleop` 未做 |
| 5 | [`control-app-product-design.md`](../design/control-app-product-design.md) | v0 协议、安全、页面约束 |
| 6 | [`control-app-evolution.md`](../design/control-app-evolution.md) | 三层方向，已冻结 |
| 7 | [`simulation.md`](../design/simulation.md)（上游 `sim-remote-io`） | **身体**孪生：`robotd --sim` + MuJoCo。不是手机 GATT |
| 8 | 本文 + [`SIM-DUCK.md`](SIM-DUCK.md) | 开发环境和虚拟鸭子 |
| 9 | [`HANDOFF.md`](HANDOFF.md) | 2026-09-12 冻结点 |

Issue [#107](https://github.com/pollen-robotics/microduck/issues/107)：设计了 App，一行代码都没有。

## 5. 自动验证：本机已有 harness

不在 `e1901` 里。实际位置：

```
~/Workspace/harness/harness
```

Cursor skill 仍写着 `~/Workspace/docs/harness/`，那个目录已经不在。调用时用上面这条路径：

```bash
cd ~/Workspace/harness/harness
npx tsx src/cli.ts web perceive --url http://127.0.0.1:5173 --out /tmp/harness/latest
npx tsx src/cli.ts ios devices
npx tsx src/cli.ts scenario /path/to/scenario.yaml
```

它给 Agent 的是眼睛和手：截图、DOM / 控制台、点击输入、YAML 场景、断言、视觉 diff。本机其它 Flutter App（`kexue_daiwa`、`bp_companion`）已经用它在 iOS 模拟器上截图迭代。

L1 的场景草稿在 [`harness/`](harness/)。App 跑起来之后，改代码必须走：

```
改代码 → 热更新 / 重装 → harness perceive 或 scenario → 读截图和 report.json → 不过就再改
```

不要只靠「看起来能编过」。

### 5.1 三层验证，不要混用

| 层 | 证明什么 | 用什么 | 现在能不能跑 |
|---|---|---|---|
| **协议** | 客户端和鸭子说同一种 JSON-RPC | App-sim + `duckctl`-同构探针 | 要先建 App-sim |
| **页面** | L1 信息架构和状态对 | harness web / iOS | App UI 出来就能跑 |
| **无线电** | 扫描、bond、CoreBluetooth 坑 | 真 iPhone + 真鸭子 | 鸭子到货后补，不阻塞 L1 |

iOS Simulator **没有蓝牙**。所以「在模拟器里连真 GATT」这条路不存在。harness 能验 UI，验不了无线电。真机 BLE 是第三层，不是第一层。

## 6. 工程形态

原作者建议 Tauri 2 + Rust，复用 `duck-ipc-proto` 和 `btd` 组帧。本机 harness 最熟的是 **Web**，其次才是 iOS `simctl`。

因此第一枪这样拆：

```
apps/microduck-app/          # 或独立仓库；发商店节奏和 daemon 不同
  src-tauri/                 # 传输 + 协议。React 不解析机器人回复
  web/                       # L1 页面。harness 先打这里
```

客户端内部只有一个 API，两个传输：

```
App  →  Transport
          ├── sim  →  ws://127.0.0.1:17432   # 默认。开发、CI、harness
          └── ble  →  CoreBluetooth / btleplug
```

环境变量（实现时按这个名字，避免各写一套）：

| 变量 | 含义 | 默认 |
|---|---|---|
| `MICRODUCK_TRANSPORT` | `sim` 或 `ble` | `sim` |
| `MICRODUCK_SIM_URL` | App-sim WebSocket | `ws://127.0.0.1:17432` |
| `MICRODUCK_PIN` | 开发 PIN | `000000`（和仓库里的出厂 PIN 一样） |

真鸭子到了：真机上设 `MICRODUCK_TRANSPORT=ble`，或设置页一个「模拟 / 真机」开关。页面、状态机、调用名都不改。

如果第一枪改用 Flutter：可以，本机有现成 harness 经验。但 Dart 不得发明命令；必须仍走同一套 JSON-RPC，最好由 Rust 客户端出 FFI，而不是手写一份协议。

## 7. 推荐工作顺序

不要先搭完整 UI，也不要空等真鸭子。

1. **实现 App-sim**（协议孪生）。[`SIM-DUCK.md`](SIM-DUCK.md) 是说明书。
2. **探针打 App-sim**：`hello` → `authenticate` → `system.info`。这就是原 HANDOFF 的 BLE 探针，只是传输先用 WebSocket。
3. **L1 页面**，视觉跟线上画廊 L1。每做一个主路径，补一条 [`harness/`](harness/) 场景。
4. **互动页**的停止 / 坐下 / 站起 / 叫一声，先打 App-sim 的 `robot.*` 只读和以后开放的安全动作；摇杆继续禁用。
5. 真鸭子 + 真 iPhone 到手：打开 `ble` 传输，复跑同一组调用。这时才补扫描、无 service filter、广告间隔那些无线电问题。

上游 `sim-remote-io` 的 `duck-sim`（MuJoCo 身体）是后一步：要看鸭子站起来、验证坐下 / 站起时再接。它不替代 App-sim。

## 8. 目录约定

```
docs/app-demo/
  HANDOFF.md              # 2026-09-12 冻结点
  DEV-ENVIRONMENT.md      # 本文
  SIM-DUCK.md             # 虚拟鸭子和切换
  harness/                # L1 验收场景
  captures/               # harness 真实截图（不是画廊稿）
  v0/                     # 旧控制台存档
apps/microduck-app/       # L1 web 面。harness 先打这里
scripts/duck-app-sim      # 一键拉起协议孪生
sim-btd/                  # WebSocket 网关，复用 btd session / route
```

`apps/` 最终可以独立成库。在独立之前，本仓库用 git 依赖引用 `duck-ipc-proto`。

## 9. 本方案不做什么

- 不重做三层产品设计，不改底栏
- 不在 Ubuntu 上写 iOS
- 不把 `btd --fake` 的测试 channel 伪装成手机能扫到的 BLE
- 不把 MuJoCo `duck-sim` 当成 App 的第一依赖
- 不在 BLE 上传动画文件或摇杆
- 不把 harness 跑在 mock 页面上、就宣称「已经连上鸭子」——页面断言和协议断言要分开
