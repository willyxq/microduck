# L1 harness 场景

用本机已有的 harness 自动验 App，不要只看编译。

```
~/Workspace/harness/harness
```

Skill 文档里的 `~/Workspace/docs/harness/` 已经不存在。

## 怎么跑

先起 App-sim 和 App 的 web 面，再跑场景。每个 YAML 自己走完发现 → PIN，不要假定上一场还连着。

```bash
scripts/duck-app-sim up
cd apps/microduck-app && npm run dev

cd ~/Workspace/harness/harness
npx tsx src/cli.ts scenario \
  /Users/william/Workspace/e1901/microduck/microduck/docs/app-demo/harness/l1-connect-sim.yaml
```

截图和报告在 `/tmp/harness/scenario-*/`。Agent 用 Read 看 `screenshot.png` 和 `report.json`。真实截图副本在 [`../captures/`](../captures/)。

## 场景

| 文件 | 证明 |
|---|---|
| `l1-connect-sim.yaml` | 发现页能看见 `duck-sim`，PIN 后进入现场管理员首页 |
| `l1-home.yaml` | 首页回答「鸭子现在怎么样」：名字、健康、网络、更新摘要；底栏是首页 / 互动 / 模型 / 设置 |
| `l1-wifi.yaml` | 配网走 `net.scan` / `net.connect`；Pollen 错密码必须说出是密码问题 |

协议层（`hello` / `authenticate` / `system.info`）用 `scripts/duck-app-sim probe`，不要只用截图证明「已经连上鸭子」。

## iOS

`scenario` YAML 是 Playwright，只打 web。iOS 用：

```bash
# 截图
npx tsx src/cli.ts ios perceive --device "iPhone 17 Pro Max" --out /tmp/harness/ios-latest

# 真实点按（推荐）：XCUITest，不依赖辅助功能权限
cd /Users/william/Workspace/e1901/microduck/microduck/apps/microduck-ios
xcodebuild test -scheme MicroDuck -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO \
  -only-testing:MicroDuckUITests/ConnectSimTests
```

`ios interact` 靠 AppleScript 点 Simulator 窗口。没开辅助功能时会失败，不要把它当成唯一验收。
