# MicroDuck iOS（第一层现场管理员）

原生 SwiftUI。模拟器没有蓝牙，所以默认连本机 App-sim：`ws://127.0.0.1:17432`。

```bash
# 1. 协议孪生
scripts/duck-app-sim up

# 2. 编进 iOS Simulator（不要签名）
cd apps/microduck-ios
xcodebuild -scheme MicroDuck -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

APP=$(find build -name MicroDuck.app | head -1)
UDID=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"];
print(next(x["udid"] for xs in d.values() for x in xs if x.get("state")=="Booted"))')
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" garden.pollen.microduck
```

harness 打 iOS（坐标点击，不是 Playwright YAML）：

```bash
cd ~/Workspace/harness/harness
npx tsx src/cli.ts ios perceive --device "iPhone 17 Pro Max" --out /tmp/harness/ios-latest
```

真鸭子到了再换 BLE 传输，页面和调用名不变。
