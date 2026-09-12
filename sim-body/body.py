#!/usr/bin/env python3
"""Body twin: MuJoCo duck + LAN control + camera.

Motion lives here, not on the BLE-shaped App-sim pipe (sim-btd :17432).
The phone talks JSON-RPC over ws://127.0.0.1:17434, same method names mediad
would forward: robot.stop / robot.do / robot.sound.

TCP :7801 speaks duck_control::sim (protocol 1) so robotd --sim can attach later.
Camera is HTTP MJPEG/JPEG on :17435, from an offscreen renderer looking at the duck.

This is not microduck_rl's duck-body. No ONNX sitstand. Sit/stand interpolate the
home pose against a folded pose. Real policies wait for the RL repo + robotd --sim.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import mujoco
import numpy as np

REPO = Path(__file__).resolve().parents[1]
MJCF = REPO / "kinematics/assets/alpha/robot_walk.xml"

JOINT_NAMES = [
    "left_hip_yaw",
    "left_hip_roll",
    "left_hip_pitch",
    "left_knee",
    "left_ankle",
    "neck_pitch",
    "head_pitch",
    "head_yaw",
    "head_roll",
    "mouth",
    "right_hip_yaw",
    "right_hip_roll",
    "right_hip_pitch",
    "right_knee",
    "right_ankle",
]

# Home pose from duck-control. Mouth has no hinge in this MJCF.
STAND = np.array(
    [0.0, -0.0873, -0.4579, -0.0049, 0.4530, 0.3491, 0.3491, 0.0, 0.0, 0.0, 0.0, 0.0873, 0.4579, 0.0049, -0.4530]
)
SIT = STAND.copy()
SIT[2] = -1.25
SIT[3] = 1.35
SIT[4] = 0.15
SIT[12] = 1.25
SIT[13] = -1.35
SIT[14] = -0.15

PROTOCOL = 1


def _vis(body, **kwargs):
    kwargs.setdefault("contype", 0)
    kwargs.setdefault("conaffinity", 0)
    body.add_geom(**kwargs)


def lookat_xyaxes(pos, target, up=(0.0, 0.0, 1.0)):
    pos = np.asarray(pos, dtype=float)
    z = pos - np.asarray(target, dtype=float)
    z /= np.linalg.norm(z)
    x = np.cross(np.asarray(up, dtype=float), z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return np.concatenate([x, y]).tolist()


def compile_model():
    spec = mujoco.MjSpec.from_file(str(MJCF))
    spec.worldbody.add_geom(
        name="floor",
        type=mujoco.mjtGeom.mjGEOM_PLANE,
        size=[2, 2, 0.1],
        rgba=[0.82, 0.78, 0.70, 1],
    )
    spec.worldbody.add_light(name="sun", pos=[0.5, -0.4, 1.4], dir=[-0.3, 0.25, -1], diffuse=[0.85, 0.82, 0.75])
    spec.worldbody.add_light(name="fill", pos=[-0.3, 0.4, 1.0], dir=[0.2, -0.2, -1], diffuse=[0.35, 0.38, 0.42])
    cam_pos = [0.28, -0.24, 0.18]
    spec.worldbody.add_camera(
        name="app_cam",
        pos=cam_pos,
        xyaxes=lookat_xyaxes(cam_pos, [0.0, 0.0, 0.07]),
    )
    duck = [0.95, 0.71, 0.17, 1]
    beak = [0.95, 0.45, 0.12, 1]
    left = [0.22, 0.52, 0.92, 1]
    right = [0.18, 0.72, 0.42, 1]
    # Only decorate the silhouette bodies. Intermediate hinge frames are rotated;
    # capsules there look like a molecule, not a duck.
    for body in spec.bodies:
        name = body.name or ""
        if name == "trunk_base":
            _vis(body, type=mujoco.mjtGeom.mjGEOM_ELLIPSOID, size=[0.058, 0.044, 0.038], pos=[-0.012, 0, 0.01], rgba=duck)
        elif name == "bottom_head_shell":
            _vis(body, type=mujoco.mjtGeom.mjGEOM_SPHERE, size=[0.034, 0, 0], pos=[0.0, 0.0, -0.04], rgba=duck)
            _vis(body, type=mujoco.mjtGeom.mjGEOM_ELLIPSOID, size=[0.022, 0.011, 0.008], pos=[0.012, 0, -0.072], rgba=beak)
        elif name == "ankle_left":
            _vis(body, type=mujoco.mjtGeom.mjGEOM_SPHERE, size=[0.015, 0, 0], pos=[0, -0.02, -0.012], rgba=left)
        elif name == "ankle_right":
            _vis(body, type=mujoco.mjtGeom.mjGEOM_SPHERE, size=[0.015, 0, 0], pos=[0, 0.02, -0.012], rgba=right)
    return spec.compile()


class Body:
    def __init__(self):
        self.model = compile_model()
        self.data = mujoco.MjData(self.model)
        self.lock = threading.Lock()
        self.adr = {}
        for name in JOINT_NAMES:
            jid = mujoco.mj_name2id(self.model, mujoco.mjtObj.mjOBJ_JOINT, name)
            if jid >= 0:
                self.adr[name] = self.model.jnt_qposadr[jid]
        self.sitting = False
        self.target = STAND.copy()
        self.stopped = False
        self.quack_until = 0.0
        self.apply_named(STAND)
        self.data.qpos[2] = 0.12
        mujoco.mj_forward(self.model, self.data)

    def apply_named(self, pose):
        for i, name in enumerate(JOINT_NAMES):
            if name in self.adr:
                self.data.qpos[self.adr[name]] = float(pose[i])

    def read15(self):
        out = [0.0] * 15
        for i, name in enumerate(JOINT_NAMES):
            if name in self.adr:
                out[i] = float(self.data.qpos[self.adr[name]])
        return out

    def write15(self, targets):
        self.target = np.array(targets, dtype=float)
        self.apply_named(self.target)

    def set_skill(self, skill: str) -> str:
        if skill == "sit_toggle":
            self.sitting = not self.sitting
            self.stopped = False
            self.target = SIT.copy() if self.sitting else STAND.copy()
            return "sitting" if self.sitting else "standing"
        if skill in ("stop",):
            self.stopped = True
            self.target = np.array(self.read15())
            return "stopped"
        if skill in ("quack", "sound"):
            self.stopped = False
            self.quack_until = time.time() + 0.35
            return "quack"
        return skill

    def step(self, dt=0.02):
        with self.lock:
            for i, name in enumerate(JOINT_NAMES):
                if name not in self.adr:
                    continue
                cur = self.data.qpos[self.adr[name]]
                tgt = float(self.target[i])
                self.data.qpos[self.adr[name]] = cur + 0.18 * (tgt - cur)
            z_tgt = 0.07 if self.sitting else 0.12
            self.data.qpos[2] += 0.12 * (z_tgt - self.data.qpos[2])
            if time.time() < self.quack_until and "head_pitch" in self.adr:
                self.data.qpos[self.adr["head_pitch"]] = 0.62
            mujoco.mj_forward(self.model, self.data)


BODY = Body()
JPEG = {"bytes": b"", "lock": threading.Lock()}


def physics_loop(stop: threading.Event):
    while not stop.is_set():
        BODY.step()
        time.sleep(0.02)


def render_loop(stop: threading.Event, width=480, height=320):
    renderer = mujoco.Renderer(BODY.model, height=height, width=width)
    while not stop.is_set():
        with BODY.lock:
            renderer.update_scene(BODY.data, camera="app_cam")
            frame = renderer.render().copy()
        try:
            import cv2

            ok, buf = cv2.imencode(".jpg", frame[:, :, ::-1], [int(cv2.IMWRITE_JPEG_QUALITY), 70])
            raw = buf.tobytes() if ok else b""
        except Exception:
            raw = _ppm_fallback(frame)
        if raw:
            with JPEG["lock"]:
                JPEG["bytes"] = raw
        time.sleep(0.05)


def _ppm_fallback(frame) -> bytes:
    # JPEG without OpenCV: write a tiny JFIF via PIL if present, else PPM bytes clients ignore.
    try:
        from io import BytesIO

        from PIL import Image

        img = Image.fromarray(frame)
        buf = BytesIO()
        img.save(buf, format="JPEG", quality=70)
        return buf.getvalue()
    except Exception:
        return b""


class CameraHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path.startswith("/health"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self._cors()
            with JPEG["lock"]:
                has_frame = bool(JPEG["bytes"])
            body = json.dumps(
                {
                    "ok": True,
                    "bridge": "microduck-body",
                    "sitting": BODY.sitting,
                    "camera": has_frame,
                }
            ).encode()
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path.startswith("/camera.jpg"):
            with JPEG["lock"]:
                raw = JPEG["bytes"]
            if not raw:
                self.send_error(503, "no frame yet")
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self._cors()
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        if self.path.startswith("/camera.mjpeg") or self.path.startswith("/camera"):
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self._cors()
            self.end_headers()
            try:
                while True:
                    with JPEG["lock"]:
                        raw = JPEG["bytes"]
                    if raw:
                        self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\n\r\n" + raw + b"\r\n")
                        self.wfile.flush()
                    time.sleep(0.08)
            except BrokenPipeError:
                return
        self.send_error(404)


def rpc_result(req_id, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": req_id}
    if error:
        msg["error"] = {"code": -32000, "message": error}
    else:
        msg["result"] = result if result is not None else {}
    return json.dumps(msg) + "\n"


def handle_call(method: str, params: dict, req_id):
    if method == "hello":
        return rpc_result(req_id, {"api_version": 16, "daemon_version": "body-sim", "channel": "lan"})
    if method == "robot.health":
        return rpc_result(req_id, {"healthy": True, "reason": "mujoco body", "sitting": BODY.sitting})
    if method == "robot.stop":
        BODY.set_skill("stop")
        return rpc_result(req_id, {"ok": True, "state": "stopped", "channel": "lan"})
    if method == "robot.do":
        skill = (params or {}).get("skill") or ""
        state = BODY.set_skill(skill)
        return rpc_result(req_id, {"ok": True, "skill": skill, "state": state, "channel": "lan"})
    if method == "robot.sound":
        BODY.set_skill("quack")
        return rpc_result(req_id, {"ok": True, "channel": "lan"})
    if method == "camera.info":
        with JPEG["lock"]:
            has_frame = bool(JPEG["bytes"])
        return rpc_result(
            req_id,
            {
                "url": "http://127.0.0.1:17435/camera.mjpeg",
                "still": "http://127.0.0.1:17435/camera.jpg",
                "live": has_frame,
            },
        )
    return rpc_result(req_id, error=f"unknown {method}")


async def lan_handler(ws):
    async for raw in ws:
        text = raw if isinstance(raw, str) else raw.decode("utf-8", "replace")
        for line in text.splitlines():
            if not line.strip():
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                await ws.send(rpc_result(None, error="bad json"))
                continue
            reply = handle_call(msg.get("method") or "", msg.get("params") or {}, msg.get("id"))
            await ws.send(reply)


def start_http(port: int):
    httpd = ThreadingHTTPServer(("127.0.0.1", port), CameraHandler)
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    return httpd


def start_remote_io(port: int, stop: threading.Event):
    def serve():
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("127.0.0.1", port))
        sock.listen(4)
        sock.settimeout(0.5)
        while not stop.is_set():
            try:
                conn, _ = sock.accept()
            except socket.timeout:
                continue
            threading.Thread(target=remote_io_client, args=(conn,), daemon=True).start()
        sock.close()

    threading.Thread(target=serve, daemon=True).start()


def remote_io_client(conn: socket.socket):
    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    buf = b""
    try:
        while True:
            chunk = conn.recv(65536)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line:
                    continue
                req = json.loads(line.decode())
                op = req.get("op")
                if op == "hello":
                    reply = {"protocol": PROTOCOL}
                elif op == "read":
                    pos = BODY.read15()
                    reply = {
                        "positions": pos,
                        "velocities": [0.0] * 15,
                        "currents_ma": [0.0] * 15,
                        "imu": {"gyro": [0, 0, 0], "gravity": [0, 0, -1], "quat": [1, 0, 0, 0]},
                    }
                elif op == "write":
                    BODY.write15(req.get("targets") or STAND.tolist())
                    reply = {}
                elif op in ("gain", "torque", "slow"):
                    reply = {"volts": 7.4, "temps_c": [35.0] * 15} if op == "slow" else {}
                else:
                    reply = {"error": f"unknown op {op}"}
                conn.sendall((json.dumps(reply) + "\n").encode())
    except Exception:
        pass
    finally:
        conn.close()


def maybe_viewer(stop: threading.Event):
    try:
        import mujoco.viewer
    except Exception as exc:
        print(f"viewer unavailable: {exc}", flush=True)
        return
    with mujoco.viewer.launch_passive(BODY.model, BODY.data) as viewer:
        while viewer.is_running() and not stop.is_set():
            with BODY.lock:
                viewer.sync()
            time.sleep(0.02)


def serve_lan(args, stop: threading.Event):
    async def run():
        import websockets

        async with websockets.serve(lan_handler, "127.0.0.1", args.lan_port):
            while not stop.is_set():
                await asyncio.sleep(0.2)

    asyncio.run(run())


def start_runtime(args):
    stop = threading.Event()
    threading.Thread(target=physics_loop, args=(stop,), daemon=True, name="physics").start()
    threading.Thread(target=render_loop, args=(stop,), daemon=True, name="render").start()
    start_http(args.camera_port)
    start_remote_io(args.body_port, stop)
    threading.Thread(target=serve_lan, args=(args, stop), daemon=True, name="lan").start()
    print(
        f"body-sim lan ws://127.0.0.1:{args.lan_port}  "
        f"camera http://127.0.0.1:{args.camera_port}/camera.mjpeg  "
        f"remote-io 127.0.0.1:{args.body_port}",
        flush=True,
    )
    return stop


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--lan-port", type=int, default=17434)
    p.add_argument("--camera-port", type=int, default=17435)
    p.add_argument("--body-port", type=int, default=7801)
    p.add_argument("--viewer", action="store_true", default=True)
    p.add_argument("--headless", action="store_true")
    args = p.parse_args()
    if args.headless:
        args.viewer = False
    stop = start_runtime(args)
    if args.viewer:
        try:
            maybe_viewer(stop)
        except Exception as exc:
            print(f"viewer failed, camera/LAN keep running: {exc}", flush=True)
    while not stop.is_set():
        time.sleep(0.5)


if __name__ == "__main__":
    main()
