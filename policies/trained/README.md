# Trained capabilities

Copied from `ubuntu-lan` (`william@192.168.3.6`) `microduck_rl` wandb / `logs/rsl_rl`.
Every file is the official 61-D family (`obs[1,61] → actions[1,14]`).

`catalog.json` is the user-facing map: **capability → file**. The App never asks
anyone to pick an `.onnx`. Download copies `available/` → `installed/`; Body-sim
attaches that session and `robot.do {skill}` / the drive stick switch it.

Builtin walk / sit / stand stay `policies/alpha_*.onnx` until someone downloads
the LAN-trained replacement.

Roller skills are listed but need a wheeled body; the current Cream walker
refuses them with a clear toast.
