#!/usr/bin/env python3
"""Body twin: MuJoCo duck + LAN control + camera + world viewer.

Motion lives here, not on the BLE-shaped App-sim pipe (sim-btd :17432).
The phone talks JSON-RPC over ws://127.0.0.1:17434:
  robot.stop / robot.do / robot.sound / robot.move {vx, vy, vyaw}

robot.move is the official teleop intent. The default gait is the shipped
ONNX walk/stand/sitstand bundle (same 61-D family as robotd), run in this
MuJoCo world at 50 Hz. Deadman zeros after 500 ms. If the weights or
onnxruntime are missing, it falls back to kinematic slide.

The GLFW window is the same virtual world as microduck_rl's infer_policy demo:
scene.xml + robot_allcollisions.xml + Cream STL meshes. The JPEG on :17435 is a
follow camera on that same duck.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import signal
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import mujoco
import numpy as np

from gait import load_gait
from skills import (
    attach,
    describe,
    detach_skill,
    install as install_skill,
    install_all as install_all_skills,
    load_catalog,
    lookup,
    set_locomotion,
    _installed as skill_file,
    uninstall as uninstall_skill,
    uninstall_all as uninstall_all_skills,
)

REPO = Path(__file__).resolve().parents[1]
CONTROL_DT = 0.02
DECIMATION = 4
SIM_TIMESTEP = 0.005
RL_DIR = REPO.parent / "microduck_rl/src/mjlab_microduck/robot/microduck"
SCENES = {
    "walk": Path(os.environ["DUCK_BODY_MJCF"]) if os.environ.get("DUCK_BODY_MJCF") else RL_DIR / "scene.xml",
    "rollers": RL_DIR / "scene_rollers.xml",
}
FALLBACK_MJCF = REPO / "kinematics/assets/alpha/robot_walk.xml"

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

# Home pose from infer_policy DEFAULT_POSE / scene.xml STAND. Mouth has no hinge.
STAND = np.array(
    [0.0, -0.0873, -0.4579, -0.0049, 0.4530, 0.3491, 0.3491, 0.0, 0.0, 0.0, 0.0, 0.0873, 0.4579, 0.0049, -0.4530]
)
SIT = np.array([0.0, 0.0, -0.5236, 1.0472, 0.0, 0.5, 1.6, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5236, -1.0472, 0.0])

PROTOCOL = 1
DEADMAN = 0.5
MAX_LINEAR = 0.3
MAX_ANGULAR = 1.5


def lookat_xyaxes(pos, target, up=(0.0, 0.0, 1.0)):
    pos = np.asarray(pos, dtype=float)
    z = pos - np.asarray(target, dtype=float)
    z /= np.linalg.norm(z)
    x = np.cross(np.asarray(up, dtype=float), z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return np.concatenate([x, y])


def yaw_of(qpos) -> float:
    qw, qx, qy, qz = (float(qpos[3]), float(qpos[4]), float(qpos[5]), float(qpos[6]))
    return float(np.arctan2(2 * (qw * qz + qx * qy), 1 - 2 * (qy * qy + qz * qz)))


def compile_model(kind: str = "walk"):
    mjcf = SCENES.get(kind) if SCENES.get(kind) and SCENES[kind].exists() else None
    if mjcf is None:
        mjcf = FALLBACK_MJCF
    if not mjcf.exists():
        raise FileNotFoundError(f"no MicroDuck MJCF for {kind} at {SCENES.get(kind)} or {FALLBACK_MJCF}")
    print(f"body-sim mesh {kind} {mjcf}", flush=True)
    spec = mujoco.MjSpec.from_file(str(mjcf))
    cam_pos = [0.32, -0.28, 0.20]
    spec.worldbody.add_camera(
        name="app_cam",
        pos=cam_pos,
        xyaxes=lookat_xyaxes(cam_pos, [0.0, 0.0, 0.07]).tolist(),
    )
    if mjcf == FALLBACK_MJCF:
        spec.worldbody.add_geom(
            name="floor",
            type=mujoco.mjtGeom.mjGEOM_PLANE,
            size=[4, 4, 0.1],
            rgba=[0.78, 0.74, 0.66, 1],
        )
        spec.worldbody.add_light(name="sun", pos=[0.8, -0.6, 2.0], dir=[-0.25, 0.2, -1], diffuse=[0.9, 0.86, 0.78])
    return spec.compile()


class Body:
    def __init__(self):
        self.lock = threading.Lock()
        self.generation = 0
        self.retired = []
        self.body_kind = "walk"
        self.sitting = False
        self.target = STAND.copy()
        self.stopped = False
        self.quack_until = 0.0
        self.twist = np.zeros(3)
        self.last_move = 0.0
        self.phase = 0.0
        self.ticks = 0
        self.locomotion = "walk"
        self.swap_until = 0.0
        self.viewer_pause = False
        self._init_world("walk")

    def _init_world(self, kind: str):
        self.model = compile_model(kind)
        self.model.opt.timestep = SIM_TIMESTEP
        self.data = mujoco.MjData(self.model)
        self.body_kind = kind
        self.adr = {}
        for name in JOINT_NAMES:
            jid = mujoco.mj_name2id(self.model, mujoco.mjtObj.mjOBJ_JOINT, name)
            if jid >= 0:
                self.adr[name] = self.model.jnt_qposadr[jid]
        self.cam_id = mujoco.mj_name2id(self.model, mujoco.mjtObj.mjOBJ_CAMERA, "app_cam")
        kid = mujoco.mj_name2id(self.model, mujoco.mjtObj.mjOBJ_KEY, "STAND")
        if kid >= 0:
            mujoco.mj_resetDataKeyframe(self.model, self.data, kid)
        else:
            self.apply_named(STAND)
            self.data.qpos[0:3] = [0.0, 0.0, 0.12]
            self.data.qpos[3:7] = [1.0, 0.0, 0.0, 0.0]
        self.gait = load_gait(self.model, self.data, body_kind=kind)
        if self.gait is not None:
            nctrl = min(len(self.gait.default_pose), self.model.nu)
            for i, qpos_idx in enumerate(self.gait.joint_qpos_indices[:nctrl]):
                self.data.qpos[qpos_idx] = self.gait.default_pose[i]
            self.data.ctrl[:nctrl] = self.gait.default_pose[:nctrl]
            self.gait.vel_cmd[:] = 0
            self.gait._update_policy_session()
            self.gait._update_command()
        mujoco.mj_forward(self.model, self.data)
        self.update_follow_cam()

    def ensure_body(self, kind: str) -> bool:
        if kind not in SCENES:
            raise ValueError(f"没有这种机体：{kind}")
        if self.body_kind == kind:
            return False
        print(f"body-sim switch {self.body_kind} → {kind}", flush=True)
        # Keep the previous MjModel/MjData alive: the GLFW viewer and JPEG
        # renderer still hold them until they notice generation change.
        self.retired.append((self.model, self.data, self.gait))
        self._init_world(kind)
        self.generation += 1
        self.sitting = False
        self.stopped = False
        self.twist[:] = 0
        self.locomotion = "roller" if kind == "rollers" else "walk"
        self.swap_until = time.time() + 0.25
        return True

    def _clear_modes(self, keep_sit: bool = False):
        gait = self.gait
        if gait is None:
            return
        if gait.behavior_mode:
            gait.behavior_mode = None
            gait.behavior_time_left = 0.0
        if gait.ground_pick_mode:
            gait.ground_pick_mode = False
        if not keep_sit and gait.sit_mode:
            gait.sit_mode = False
            self.sitting = False
        gait._update_policy_session()
        gait._update_command()

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
        with self.lock:
            return self._set_skill_locked(skill)

    def _set_skill_locked(self, skill: str) -> str:
        if skill == "sit_toggle":
            self.stopped = False
            self.twist[:] = 0
            if self.gait is not None and self.gait.sit_session is not None:
                self.gait.toggle_sit()
                self.sitting = bool(self.gait.sit_mode)
                return "sitting" if self.sitting else "standing"
            self.sitting = not self.sitting
            self.target = SIT.copy() if self.sitting else STAND.copy()
            return "sitting" if self.sitting else "standing"
        if skill in ("stop",):
            self.stopped = True
            self.twist[:] = 0
            if self.gait is not None:
                self.gait.vel_cmd[:] = 0
                if self.gait.sit_mode:
                    self.gait.toggle_sit()
                self.sitting = False
                self.gait._update_policy_session()
                self.gait._update_command()
            self.target = np.array(self.read15())
            return "stopped"
        if skill in ("quack", "sound"):
            self.stopped = False
            self.quack_until = time.time() + 0.35
            return "quack"
        spec = lookup(skill)
        if spec is not None:
            self.ensure_body(spec.get("body") or "walk")
        if self.gait is None:
            raise ValueError("还没有步态模型")
        if skill in ("sitstand", "roller_crouch"):
            self._clear_modes(keep_sit=True)
            self.stopped = False
            self.twist[:] = 0
            self.gait.toggle_sit()
            self.sitting = bool(self.gait.sit_mode)
            return "sitting" if self.sitting else "standing"
        self._clear_modes()
        if skill == "pick":
            if self.gait.ground_pick_session is None:
                raise ValueError("先到模型页下载「低头捡」")
            self.stopped = False
            self.gait.trigger_ground_pick()
            if not self.gait.ground_pick_mode:
                raise ValueError("低头捡没能开始")
            return "pick"
        if skill in getattr(self.gait, "behavior_sessions", {}):
            self.stopped = False
            self.gait.trigger_behavior(skill)
            if self.gait.behavior_mode != skill:
                raise ValueError(f"「{skill}」没能开始")
            return skill
        if skill in getattr(self.gait, "locomotion_sessions", {}):
            self.locomotion = set_locomotion(self.gait, skill)
            self.stopped = False
            return self.locomotion
        if spec is not None:
            raise ValueError(f"先到模型页下载「{spec['title']}」")
        raise ValueError(f"不会这个动作：{skill}")

    def set_twist(self, vx, vy, vyaw):
        self.twist[0] = float(np.clip(vx, -MAX_LINEAR, MAX_LINEAR))
        self.twist[1] = float(np.clip(vy, -MAX_LINEAR, MAX_LINEAR))
        self.twist[2] = float(np.clip(vyaw, -MAX_ANGULAR, MAX_ANGULAR))
        self.last_move = time.time()
        self.stopped = False
        if self.sitting and (abs(self.twist[0]) + abs(self.twist[1]) + abs(self.twist[2])) > 1e-3:
            self.sitting = False
            self.target = STAND.copy()
            if self.gait is not None and self.gait.sit_mode:
                self.gait.sit_mode = False
                self.gait._update_command()

    def update_follow_cam(self):
        x, y, z = float(self.data.qpos[0]), float(self.data.qpos[1]), float(self.data.qpos[2])
        yaw = yaw_of(self.data.qpos)
        back, side, up = 0.34, -0.22, 0.14
        cx = x - back * np.cos(yaw) - side * np.sin(yaw)
        cy = y - back * np.sin(yaw) + side * np.cos(yaw)
        cz = z + up
        pos = np.array([cx, cy, cz])
        self.model.cam_pos[self.cam_id] = pos
        axes = lookat_xyaxes(pos, [x, y, z + 0.05])
        xaxis, yaxis = axes[:3], axes[3:]
        zaxis = np.cross(xaxis, yaxis)
        mat = np.column_stack([xaxis, yaxis, zaxis]).ravel(order="C")
        quat = np.zeros(4)
        mujoco.mju_mat2Quat(quat, mat)
        self.model.cam_quat[self.cam_id] = quat

    def snapshot(self) -> dict:
        hip = 0.0
        if "left_hip_pitch" in self.adr:
            hip = float(self.data.qpos[self.adr["left_hip_pitch"]])
        return {
            "gait": "onnx" if self.gait is not None else "slide",
            "policy": getattr(self.gait, "current_policy", "slide"),
            "x": float(self.data.qpos[0]),
            "y": float(self.data.qpos[1]),
            "z": float(self.data.qpos[2]),
            "hip_pitch": hip,
            "sitting": self.sitting,
            "ticks": self.ticks,
            "locomotion": self.locomotion,
            "body": self.body_kind,
        }

    def step(self, dt=CONTROL_DT):
        with self.lock:
            if self.last_move and (time.time() - self.last_move) > DEADMAN:
                self.twist[:] = 0
            if self.viewer_pause or time.time() < self.swap_until:
                mujoco.mj_forward(self.model, self.data)
            elif self.gait is not None:
                self._step_gait(dt)
            else:
                self._step_slide(dt)
            self.ticks += 1
            self.update_follow_cam()

    def _step_gait(self, dt):
        vx, vy, vyaw = (float(self.twist[0]), float(self.twist[1]), float(self.twist[2]))
        if self.stopped:
            vx = vy = vyaw = 0.0
        self.gait.vel_cmd[:] = (vx, vy, vyaw)
        self.gait.update_ground_pick_phase(dt)
        self.gait.update_behavior(dt)
        self.gait._update_policy_session()
        self.gait._update_command()
        action = self.gait.infer()
        self.gait.apply_action(action)
        if time.time() < self.quack_until and self.gait.n_joints > 6:
            self.data.ctrl[6] = 0.62
        try:
            for _ in range(DECIMATION):
                mujoco.mj_step(self.model, self.data)
        except Exception as exc:
            print(f"mj_step failed ({self.body_kind}): {exc}", flush=True)
            kid = mujoco.mj_name2id(self.model, mujoco.mjtObj.mjOBJ_KEY, "STAND")
            if kid >= 0:
                mujoco.mj_resetDataKeyframe(self.model, self.data, kid)
            mujoco.mj_forward(self.model, self.data)

    def _step_slide(self, dt):
        vx, vy, vyaw = (float(self.twist[0]), float(self.twist[1]), float(self.twist[2]))
        moving = (vx * vx + vy * vy + vyaw * vyaw) > 4e-4
        if moving and not self.stopped:
            yaw = yaw_of(self.data.qpos)
            self.data.qpos[0] += (vx * np.cos(yaw) - vy * np.sin(yaw)) * dt
            self.data.qpos[1] += (vx * np.sin(yaw) + vy * np.cos(yaw)) * dt
            yaw += vyaw * dt
            self.data.qpos[3] = np.cos(yaw / 2)
            self.data.qpos[4] = 0.0
            self.data.qpos[5] = 0.0
            self.data.qpos[6] = np.sin(yaw / 2)
            self.phase += dt * (3.6 + 10.0 * min((vx * vx + vy * vy) ** 0.5, 0.3))
            swing = 0.32 * np.sin(self.phase)
            pose = STAND.copy()
            pose[2] = STAND[2] + swing
            pose[3] = STAND[3] - 0.55 * swing
            pose[12] = STAND[12] - swing
            pose[13] = STAND[13] + 0.55 * swing
            self.target = pose
        z_tgt = 0.07 if self.sitting else 0.12
        self.data.qpos[2] += 0.16 * (z_tgt - self.data.qpos[2])
        for i, name in enumerate(JOINT_NAMES):
            if name not in self.adr:
                continue
            cur = self.data.qpos[self.adr[name]]
            tgt = float(self.target[i])
            self.data.qpos[self.adr[name]] = cur + 0.22 * (tgt - cur)
        if time.time() < self.quack_until and "head_pitch" in self.adr:
            self.data.qpos[self.adr["head_pitch"]] = 0.62
        mujoco.mj_forward(self.model, self.data)


BODY = Body()
JPEG = {"bytes": b"", "lock": threading.Lock()}


def physics_loop(stop: threading.Event):
    nxt = time.perf_counter()
    while not stop.is_set():
        BODY.step()
        nxt += CONTROL_DT
        delay = nxt - time.perf_counter()
        if delay > 0:
            time.sleep(delay)
        else:
            nxt = time.perf_counter()


def render_loop(stop: threading.Event, width=480, height=320):
    renderer = mujoco.Renderer(BODY.model, height=height, width=width)
    gen = BODY.generation
    while not stop.is_set():
        if BODY.viewer_pause:
            time.sleep(0.03)
            continue
        if BODY.generation != gen:
            try:
                renderer.close()
            except Exception:
                pass
            renderer = mujoco.Renderer(BODY.model, height=height, width=width)
            gen = BODY.generation
        with BODY.lock:
            renderer.update_scene(BODY.data, camera="app_cam")
        frame = renderer.render().copy()
        try:
            import cv2

            ok, buf = cv2.imencode(".jpg", frame[:, :, ::-1], [int(cv2.IMWRITE_JPEG_QUALITY), 70])
            raw = buf.tobytes() if ok else b""
        except Exception:
            raw = _jpeg(frame)
        if raw:
            with JPEG["lock"]:
                JPEG["bytes"] = raw
        time.sleep(0.05)


def _jpeg(frame) -> bytes:
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
            snap = BODY.snapshot()
            body = json.dumps(
                {
                    "ok": True,
                    "bridge": "microduck-body",
                    "sitting": BODY.sitting,
                    "camera": has_frame,
                    "viewer": True,
                    **snap,
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
    params = params or {}
    if method == "hello":
        return rpc_result(req_id, {"api_version": 16, "daemon_version": "body-sim", "channel": "lan", "teleop": True})
    if method == "robot.health":
        snap = BODY.snapshot()
        return rpc_result(req_id, {"healthy": True, "reason": "mujoco body", **snap})
    if method == "robot.stop":
        BODY.set_skill("stop")
        return rpc_result(req_id, {"ok": True, "state": "stopped", "channel": "lan"})
    if method == "robot.do":
        skill = params.get("skill") or ""
        try:
            state = BODY.set_skill(skill)
        except ValueError as exc:
            return rpc_result(req_id, error=str(exc))
        return rpc_result(req_id, {"ok": True, "skill": skill, "state": state, "channel": "lan"})
    if method == "skill.list":
        return rpc_result(
            req_id,
            {
                "skills": describe(BODY.locomotion, BODY.body_kind),
                "locomotion": BODY.locomotion,
                "body": BODY.body_kind,
            },
        )
    if method == "skill.install":
        skill_id = params.get("id") or params.get("skill") or ""
        try:
            if skill_id in ("all", "*", "全部"):
                infos = install_all_skills()
                info = {"id": "all", "installed": True, "count": len(infos)}
                skills = load_catalog()
            else:
                info = install_skill(skill_id)
                skills = [s for s in load_catalog() if s["id"] == skill_id]
            if BODY.gait is not None:
                with BODY.lock:
                    for skill in skills:
                        attach(BODY.gait, skill)
        except (ValueError, FileNotFoundError) as exc:
            return rpc_result(req_id, error=str(exc))
        return rpc_result(req_id, {"ok": True, **info, "skills": describe(BODY.locomotion, BODY.body_kind)})
    if method == "skill.uninstall":
        skill_id = params.get("id") or params.get("skill") or ""
        try:
            if skill_id in ("all", "*", "全部"):
                infos = uninstall_all_skills()
                info = {"id": "all", "installed": False, "count": len(infos)}
                skills = load_catalog()
            else:
                info = uninstall_skill(skill_id)
                skills = [s for s in load_catalog() if s["id"] == skill_id]
            if BODY.gait is not None:
                with BODY.lock:
                    for skill in skills:
                        detach_skill(BODY.gait, skill)
                        if skill_file(skill) is not None:
                            attach(BODY.gait, skill)
                    if BODY.locomotion not in getattr(BODY.gait, "locomotion_sessions", {}):
                        fallback = "roller" if BODY.body_kind == "rollers" else "walk"
                        if fallback in getattr(BODY.gait, "locomotion_sessions", {}):
                            BODY.locomotion = set_locomotion(BODY.gait, fallback)
                        elif BODY.body_kind == "rollers":
                            BODY.ensure_body("walk")
        except (ValueError, FileNotFoundError) as exc:
            return rpc_result(req_id, error=str(exc))
        return rpc_result(req_id, {"ok": True, **info, "skills": describe(BODY.locomotion, BODY.body_kind)})
    if method == "robot.sound":
        BODY.set_skill("quack")
        return rpc_result(req_id, {"ok": True, "channel": "lan"})
    if method == "robot.move":
        BODY.set_twist(params.get("vx") or 0, params.get("vy") or 0, params.get("vyaw") or 0)
        return rpc_result(req_id, {"ok": True, "channel": "lan", "deadman_ms": int(DEADMAN * 1000)})
    if method == "camera.info":
        with JPEG["lock"]:
            has_frame = bool(JPEG["bytes"])
        snap = BODY.snapshot()
        return rpc_result(
            req_id,
            {
                "url": "http://127.0.0.1:17435/camera.mjpeg",
                "still": "http://127.0.0.1:17435/camera.jpg",
                "live": has_frame,
                "gait": snap["gait"],
                "policy": snap["policy"],
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
            if msg.get("id") is not None:
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
    """GLFW 'real world' window. Pause physics around close/open so
    mj_copyDataVisual does not run while mj_step holds the data stack."""
    try:
        import mujoco.viewer
    except Exception as exc:
        print(f"viewer unavailable: {exc}", flush=True)
        return
    while not stop.is_set():
        gen = BODY.generation
        model, data = BODY.model, BODY.data
        BODY.viewer_pause = True
        time.sleep(0.15)
        try:
            with mujoco.viewer.launch_passive(model, data, show_left_ui=False, show_right_ui=False) as viewer:
                print(f"world viewer open — {BODY.body_kind}", flush=True)
                BODY.viewer_pause = False
                while viewer.is_running() and not stop.is_set() and BODY.generation == gen:
                    with BODY.lock:
                        viewer.sync()
                    time.sleep(0.02)
                BODY.viewer_pause = True
                time.sleep(0.1)
            print("world viewer closed", flush=True)
        except Exception as exc:
            print(f"viewer failed: {exc}", flush=True)
            BODY.viewer_pause = False
        if stop.is_set():
            return
        time.sleep(0.8)


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


def detach():
    try:
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
    except Exception:
        pass
    try:
        os.setsid()
    except OSError:
        pass


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
    detach()
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
