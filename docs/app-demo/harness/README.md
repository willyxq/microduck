# L1 harness 场景

用本机已有的 harness 自动验 App，不要只看编译。

```
~/Workspace/harness/harness
```

Skill 文档里的 `~/Workspace/docs/harness/` 已经不存在。

## 怎么跑

先起 App-sim 和 App 的 web 面，再跑场景。URL 在 App 工程落地后改成真实端口。

```bash
scripts/duck-app-sim up
# App web 开发服，默认假定 5173

cd ~/Workspace/harness/harness
npx tsx src/cli.ts scenario \
  /Users/william/Workspace/e1901/microduck/microduck/docs/app-demo/harness/l1-connect-sim.yaml
```

截图和报告在 `/tmp/harness/scenario-*/`。Agent 用 Read 看 `screenshot.png` 和 `report.json`。

## 场景

| 文件 | 证明 |
|---|---|
| `l1-connect-sim.yaml` | 发现页能看见 `duck-sim`，PIN 后进入现场管理员首页 |
| `l1-home.yaml` | 首页回答「鸭子现在怎么样」：名字、健康、网络、更新摘要 |
| `l1-wifi.yaml` | 配网走 `net.scan` / `net.connect`；错密码要能看出是密码问题 |

这些 YAML 是验收契约。App 还没长出来时，场景不会绿——那是正常的。实现 UI 时按断言补 `data-testid`，不要改断言去迁就空壳。

协议层（`hello` / `authenticate` / `system.info`）另做命令行探针，不要只用截图证明「已经连上鸭子」。
