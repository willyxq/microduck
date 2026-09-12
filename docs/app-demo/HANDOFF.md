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

推荐顺序，不要先搭完整 UI：

1. 在 Mac 检出上面的标签，单独开 App 仓库或本仓库子目录，例如 `apps/microduck-ios`。App 发商店的节奏和机器人 daemon 不同，原作者建议最终独立成库。
2. 先做**真机 BLE 探针**，不做页面：扫描（不要用 service filter）、连接、`hello`、认证、`system.info`。iPhone 和以后的 Android 都要跑。
3. 协议复用 `duck-ipc-proto` 和 `btd` 的组帧。原作者因此倾向 Tauri 2 + Rust。如果第一枪用原生 Swift，也必须按同一套 JSON-RPC 说话，不能发明新命令。
4. 探针通过后，再做第一层：发现、PIN、配网、健康、模型检查/更新/回退。视觉以线上三层画廊的 L1 为准。
5. 互动页先做：摄像头、立即停止、坐下/站起、叫一声。摇杆保持禁用，直到 `teleop` 通道存在。
6. WebRTC 控制属于第一层之后的能力，且只能走局域网，不能退化到 BLE。

Mac 最小工具：

- Xcode + 真机 iPhone
- 一只已刷好、能广播 BLE 的 MicroDuck
- Rust（若走 Tauri / 复用协议 crate）
- 本仓库作为 git 依赖，用来引用 `duck-ipc-proto`

不要在 Ubuntu 上继续写 iOS 工程，也不要等额度恢复后再重新设计信息架构。

## 5. 额度恢复后的续做提示

给下一个 Agent 的第一句话可以是：

> 从 `app-checkpoint-2026-09-12` 继续 MicroDuck App。先读 `docs/app-demo/HANDOFF.md`。不要重做三层产品设计。下一件事实机 BLE 探针：scan / connect / hello / authenticate / system.info。产品目标是第一层现场管理员，不是手机手柄。

如果要 fork：

```bash
git checkout -b app-l1-ble-spike app-checkpoint-2026-09-12
```
