# MicroDuck App 检查点 · 2026-09-12

这是额度用尽前的冻结点。之后在 Mac 上继续，或新开 Cursor 对话 / fork 仓库，都从这里开始，不要从 Ubuntu 环境接着写 iOS 代码。

## 1. 精确位置

| 项 | 值 |
|---|---|
| 仓库 | `https://github.com/willyxq/microduck` |
| 上游 | `https://github.com/pollen-robotics/microduck` |
| 分支 | `cursor/microduck-control-app-design-85d7` |
| 提交 | `1738ba5aae96ebd51fba4cf9d7420e3bb8937635` |
| 标签 | `app-checkpoint-2026-09-12` |
| 线上画廊 | https://willyxq.github.io/microduck/app-demo/?v=1738ba5 |
| v0 存档 | https://willyxq.github.io/microduck/app-demo/v0/?v=1738ba5 |

在 Mac 上检出：

```bash
git clone https://github.com/willyxq/microduck.git
cd microduck
git fetch --tags
git switch --detach app-checkpoint-2026-09-12
# 或继续在原分支上做：
# git switch cursor/microduck-control-app-design-85d7
```

新开 Cursor Agent 时，把本文件和下面「必须先读」的文档贴进任务，要求从该标签创建新分支，不要从 `main` 重做设计。

## 2. 现在完成了什么

只完成了**产品设计和可下载视觉稿**，没有 App 工程、没有 iOS/Android 工程、没有真机 BLE 联调。

已冻结：

- `docs/app-demo/v0/`：2026-09-11 控制台方案，底栏是「首页 / 控制 / 模型 / 设置」
- `docs/design/control-app-evolution.md`：三层演进，底栏改为「首页 / 互动 / 模型 / 设置」
- 9 张演进图：`docs/app-demo/assets/l{1,2,3}-{home,interact,models}.png`

产品判断：

- App 不是手机版手柄。智能提高后，减少连续驾驶，不取消停止和接管。
- 第一层是现场管理员：配网、更新、画面、停止、坐下/站起、叫一声。
- 第二层是高级意图：过来、跟随、找球、自己玩、休息。
- 第三层是陪伴：状态、记忆、边界、偶尔召唤。
- 层次由设备能力和安全证据切换，能力下降自动退回。
- 运动控制不走 BLE。`teleop` 未完成前，摇杆必须禁用。
- 实体手柄继续负责需要盲操的现场驾驶。

## 3. 必须先读的原文

不要只读我们后来写的产品稿。原作者已经把机器人侧路径写完，App 只缺客户端。

1. `docs/design/app-path-design.md`：BLE / `btd` / `configd`，扫描、配对、配网
2. 原作者分支 `docs-mobile-app-approach` 上的 `docs/design/mobile-app.md`：App 先是设置工具；建议 Tauri + `duck-ipc-proto`
3. `docs/design/updater-design.md`：手机只触发更新，鸭子用自己的 Wi-Fi 下载
4. `docs/design/remote-webrtc.md`：视频和 `control` 已有，低延迟 `teleop` 未做
5. `docs/design/control-app-product-design.md`：v0 协议、安全和页面行为
6. `docs/design/control-app-evolution.md`：当前产品方向和切换标准
7. Issue [#107](https://github.com/pollen-robotics/microduck/issues/107)：设计了 App，一行代码都没有

我们**不是**从原作者 App 分支切出来的。工程续做时要对齐原文协议，不要另写一套 BLE 方言。

## 4. 在 Mac 上怎么继续

Ubuntu 这台机器只适合改文档和出图。iOS 真机、Xcode、签名、CoreBluetooth 必须在 Mac 上做。

**现在没有真鸭子。** 开发环境和虚拟鸭子方案见：

- [`DEV-ENVIRONMENT.md`](DEV-ENVIRONMENT.md) — 机器、工具链、harness、工程形态
- [`SIM-DUCK.md`](SIM-DUCK.md) — App-sim 协议孪生，以及怎么切到真机
- [`harness/`](harness/) — L1 自动验收场景

推荐顺序，不要先搭完整 UI，也不要空等真鸭子：

1. 在 Mac 从本标签切新分支。App 工程放 `apps/microduck-app` 或独立仓库。
2. 先做 **App-sim**（真 daemon + WebSocket 网关），再做探针：`hello` / `authenticate` / `system.info`。这就是原来的 BLE 探针，传输先用 sim。
3. 协议复用 `duck-ipc-proto` 和 `btd` 的组帧。原作者因此倾向 Tauri 2 + Rust。
4. L1 页面用本机 `~/Workspace/harness/harness` 自动截图验收。iOS Simulator 没有蓝牙。
5. 真鸭子到了只设 `MICRODUCK_TRANSPORT=ble`，不要另写一套 API。
6. 互动页先做摄像头、立即停止、坐下/站起、叫一声。摇杆保持禁用。WebRTC 不能退化到 BLE。

Mac 最小工具：

- Xcode；真机 iPhone 用于以后的 BLE，不是现在的阻塞项
- Rust、Node；harness 在 `~/Workspace/harness/harness`
- App-sim（待实现），代替还没到的真鸭子
- 本仓库作为 git 依赖，用来引用 `duck-ipc-proto`

不要在 Ubuntu 上继续写 iOS 工程，也不要重做信息架构。

## 5. 额度恢复后的续做提示

给下一个 Agent 的第一句话可以是：

> 从 `app-checkpoint-2026-09-12` 继续 MicroDuck App。先读 `docs/app-demo/HANDOFF.md` 和 `docs/app-demo/DEV-ENVIRONMENT.md`。不要重做三层产品设计。没有真鸭子：先实现 App-sim，再打 hello / authenticate / system.info。产品目标是第一层现场管理员，不是手机手柄。

如果要 fork：

```bash
git checkout -b app-l1-sim-spike app-checkpoint-2026-09-12
```
