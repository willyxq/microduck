# 虚拟鸭子，以及怎么切到真鸭子

状态：待实现 · 日期：2026-09-12

配套 [`DEV-ENVIRONMENT.md`](DEV-ENVIRONMENT.md)。产品目标仍是第一层现场管理员。

现在没有真鸭子。App 和 harness 要连上一只**说同样协议的鸭子**，而不是连一个随便编的假 API。真鸭子到了，只换传输。

## 1. 为什么必须自己做 App-sim

三件已经存在的东西，都**不是**手机 App 要的那只鸭子：

| 已有 | 它实际是什么 | 为什么不够 |
|---|---|---|
| `configd --fake-net`、`robotd --fake`、`btd` 测试里的 `Link::pair` | 单测 / 笔记本打 IPC | 没有手机能连的端口 |
| 上游 `sim-remote-io` 的 [`simulation.md`](../design/simulation.md) / `scripts/duck-sim` | **身体**孪生：真 `robotd` + MuJoCo | 给 `robotctl` 用；假的是关节和 IMU，不是给手机的 GATT |
| 真 BLE `btd` | 板上的无线电 | 没板；iOS Simulator 也没有蓝牙 |

所以要补一层 **App-sim：协议孪生**。它跑本仓库里的真 daemon（`--fake` / `--fake-net`），前面加一个和 `btd` 同会话逻辑的网关。App 看见的仍是 NDJSON JSON-RPC，不是另一套 REST。

```
        harness / 开发者
                │
                ▼
         MicroDuck App
                │
     MICRODUCK_TRANSPORT
          ┌─────┴──────┐
          │            │
        sim           ble          ← 只在这里分叉
          │            │
          ▼            ▼
   ws://127.0.0.1:17432     真机 CoreBluetooth
          │            │
          ▼            ▼
      sim-btd         板上 btd
          │            │
          └─────┬──────┘
                │ 同一张路由表，同一套 duck-ipc-proto
                ▼
     configd · robotd · updaterd
```

`btd` 自己的原则仍然成立：传输是一根管子，不拥有配置，不解析回复含义。sim-btd 只是把管子从 GATT 换成 WebSocket。

## 2. 三层孪生，用途不同

| 层 | 命令（拟定） | 鸭子有什么 | App 怎么连 | 何时用 |
|---|---|---|---|---|
| **A. App-sim** | `scripts/duck-app-sim` | 真 IPC + FakeNet + fake robot | `MICRODUCK_TRANSPORT=sim` | **现在。** 开发 L1、跑 harness |
| **B. Body-sim** | 上游 `scripts/duck-sim` | 真 `robotd --sim` + MuJoCo | 仍走 App-sim 网关，只是后面的 `robotd` 换成 `--sim` | 要看站起来、坐下、叫一声是否真的动 |
| **C. Real** | 真鸭子开机 | 真无线电、真 Wi-Fi、真舵机 | `MICRODUCK_TRANSPORT=ble` | 鸭子到货。验收扫描和配网 |

从 A 到 C，App 的页面和调用名不变。变的是网线。

Body-sim 在 Mac 上比 Ubuntu 重：上游按 Linux 容器 / `systemd-nspawn` 写的，MuJoCo 在 Apple Silicon 上要单独接。它不阻塞 L1。L1 先把 A 做稳。

## 3. App-sim 必须长什么样

实现时按这个契约写。偏离了，切真机时一定裂。

### 3.1 进程

`scripts/duck-app-sim up` 拉起：

1. `configd --fake-net`（以及测试需要的 `--fake-pads`）
2. `robotd --fake`（L1 健康、服务列表）；以后可换成 `--sim`
3. `updaterd` 能在笔记本跑就跑；跑不起来就让 `update.*` 回规范错误，不要编造进度条
4. **sim-btd**：WebSocket `127.0.0.1:17432`，复用 `btd` 的 session / route / framing

`scripts/duck-app-sim down` 按 pidfile 停，不要 `pkill -f`。

`scripts/duck-app-sim status` 打印：PIN、假 SSID、监听地址、各 socket 是否在。

### 3.2 线上协议

- 一条连接 = 一次 `btd` session
- 报文：NDJSON，组帧与 `btd::framing` 相同（没有 BLE 20 字节限制时仍按同一套拼行，真机再按 MTU 切）
- 先 `hello`，再 `system.authenticate`，PIN 按字符串比，默认 `000000`
- 路由表就是 `btd/src/route.rs`。App-sim **不得**比真 `btd` 多放行电机控制
- 假 Wi-Fi 行为跟 `FakeNet`：看不见的 SSID → `NotFound`；错密码 → `BadKey`；重配覆盖不堆副本

开发用的可见身份固定，方便 harness 写断言：

| 字段 | 开发默认 |
|---|---|
| 名字 | `duck-sim` |
| 序列号 | `SIM-0001` |
| PIN | `000000` |
| 假 SSID | `SimCafe`、`SimOffice`（`SimCafe` 的密码约定为 `correct`） |
| 无地址时的广告含义 | 等价 `0.0.0.0`：鸭子在、但没网 |

### 3.3 App 侧

发现页在 `sim` 模式下**不要扫 BLE**。直接列出 App-sim 宣告的那一只（或多只，若以后起两个端口）。

设置里保留「模拟鸭子 / 真机」；开发构建默认模拟。正式包默认真机，不进商店还挂着 sim 端口。

## 4. 日常怎么开

鸭子还没到，每天只走这一路：

```bash
# 1. 协议孪生
scripts/duck-app-sim up

# 2. App（开发构建默认 sim）
cd apps/microduck-app && npm run tauri dev
# 或：MICRODUCK_TRANSPORT=sim npm run dev

# 3. 自动看页面
cd ~/Workspace/harness/harness
npx tsx src/cli.ts scenario \
  /Users/william/Workspace/e1901/microduck/microduck/docs/app-demo/harness/l1-home.yaml
```

探针（没 UI 也能跑，对应原 HANDOFF 的下一枪）：

```
connect sim → hello → authenticate 000000 → system.info
```

`system.info` 必须带回 `SIM-0001` / `duck-sim`。这是「连上了虚拟鸭子」的最低证据。

## 5. 真鸭子到了怎么切

不要开新 App，不要抄一套 API。按清单做：

1. 真鸭子开机，确认它在广播（笔记本 `cargo run -p duckctl -- scan`，**不要**加 service filter）。
2. 真机 iPhone 连上 Xcode（本机的 mickey 目前是 Offline）。
3. App 设 `MICRODUCK_TRANSPORT=ble`，或设置页切到真机。
4. 复跑同一组调用：`hello` / `authenticate` / `system.info` / `net.status`。
5. 再跑发现：无 filter 扫描、用序列号当收藏键、外设 identifier 只当缓存（见 `app-path-design.md` §3.3、§8.2）。
6. 配网、更新改打真 `configd` / `updaterd`。App-sim 里 `FakeNet` 绿了，只说明客户端说的话是对的，不说明板上的 NetworkManager 没漂。
7. `scripts/duck-app-sim down`。开发和 CI 继续留着它。

切回去：`MICRODUCK_TRANSPORT=sim`，重新 `duck-app-sim up`。

### 5.1 切换时不要做的事

- 不要为真机再写一份 JSON 字段
- 不要在模拟器里「模拟 BLE 外设」当作真机验收
- 不要用 Body-sim 的 MuJoCo 窗口代替 `system.info`
- 不要在 BLE 上做摇杆；真机也一样禁用，直到 `teleop`

## 6. App-sim 证明不了什么

写在这里，避免 harness 全绿被当成现场就绪：

- CoreBluetooth 的扫描过滤、bond、`encrypt_read` 挂死（`app-path-design.md` §5.5）
- 广告间隔、空 service list、地址漂移（§3.4、§8.6）
- 真 NetworkManager 的 `BadKey` / 重复 profile
- 更新进度在 20 字节链路上是否平滑
- 舵机、电池、IMU、摄像头画面

这些只能在层 C（以及以后的层 B）补。层 A 的职责是：**App 在没鸭子时也能把现场管理员的状态机做完，并且和真鸭子说同一种话。**

## 7. 和上游 duck-sim 的关系

上游 [`simulation.md`](../design/simulation.md) 的缝在 `RobotIo`：真舵机或 MuJoCo。App-sim 的缝在 **传输**：GATT 或 WebSocket。

两层可以叠：

```
App --ws--> sim-btd --unix--> robotd --sim--> MuJoCo
```

不要把它们合成一个脚本名就混着维护。`duck-app-sim` 管手机能不能说话；`duck-sim` 管鸭子有没有身体。
