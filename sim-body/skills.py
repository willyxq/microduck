"""Capability catalog for Body-sim.

Users pick a skill (行走 / 前滚翻 / 太空步). This module maps that name to an
ONNX file, copies it into installed/, and attaches the session onto the live
PolicyInference. The phone never names a .onnx file.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

import onnxruntime as ort

REPO = Path(__file__).resolve().parents[1]
TRAINED = REPO / "policies" / "trained"
AVAILABLE = TRAINED / "available"
INSTALLED = TRAINED / "installed"
CATALOG_PATH = TRAINED / "catalog.json"


def load_catalog() -> list[dict]:
    raw = json.loads(CATALOG_PATH.read_text())
    return list(raw.get("skills") or [])


def lookup(skill_id: str) -> dict | None:
    return next((s for s in load_catalog() if s["id"] == skill_id), None)


def _builtin(skill: dict) -> Path | None:
    rel = skill.get("builtin")
    if not rel:
        return None
    path = REPO / rel
    return path if path.exists() else None


def _available(skill: dict) -> Path | None:
    path = AVAILABLE / skill["file"]
    return path if path.exists() else None


def _copied(skill: dict) -> Path | None:
    path = INSTALLED / skill["file"]
    return path if path.exists() else None


def _installed(skill: dict) -> Path | None:
    return _copied(skill) or _builtin(skill)


def describe(locomotion: str = "walk", body_kind: str = "walk") -> list[dict]:
    out = []
    for skill in load_catalog():
        installed = _installed(skill)
        available = _available(skill)
        copied = _copied(skill)
        out.append(
            {
                "id": skill["id"],
                "title": skill["title"],
                "blurb": skill["blurb"],
                "kind": skill["kind"],
                "body": skill["body"],
                "ready": installed is not None,
                "installed": installed is not None,
                "removable": copied is not None,
                "available": available is not None or installed is not None,
                "active": skill["id"] == locomotion,
                "bytes": (available or installed).stat().st_size if (available or installed) else 0,
                "source": skill.get("run") or "",
                "current_body": body_kind,
            }
        )
    return out


def install(skill_id: str) -> dict:
    skill = lookup(skill_id)
    if skill is None:
        raise ValueError(f"没有这个能力：{skill_id}")
    src = _available(skill) or _builtin(skill)
    if src is None:
        raise FileNotFoundError(f"{skill['title']} 的模型还没拷到本机")
    INSTALLED.mkdir(parents=True, exist_ok=True)
    dest = INSTALLED / skill["file"]
    if src.resolve() != dest.resolve():
        shutil.copy2(src, dest)
    return {"id": skill_id, "installed": True, "path": str(dest)}


def install_all() -> list[dict]:
    return [install(skill["id"]) for skill in load_catalog()]


def uninstall(skill_id: str) -> dict:
    skill = lookup(skill_id)
    if skill is None:
        raise ValueError(f"没有这个能力：{skill_id}")
    dest = INSTALLED / skill["file"]
    if not dest.exists():
        if _builtin(skill):
            raise ValueError(f"「{skill['title']}」是出厂能力，不能卸载")
        raise ValueError(f"「{skill['title']}」还没安装")
    dest.unlink()
    return {"id": skill_id, "installed": False, "ready": _installed(skill) is not None}


def uninstall_all() -> list[dict]:
    return [uninstall(skill["id"]) for skill in load_catalog() if _copied(skill)]


def detach_skill(policy, skill: dict) -> None:
    sid = skill["id"]
    if sid == "pick":
        policy.ground_pick_session = None
    if sid == "sitstand" and _installed(skill) is None:
        policy.sit_session = None
    if sid == "roller_crouch":
        policy.crouch_session = None
    getattr(policy, "locomotion_sessions", {}).pop(sid, None)
    getattr(policy, "behavior_sessions", {}).pop(sid, None)
    getattr(policy, "behavior_durations", {}).pop(sid, None)


def attach(policy, skill: dict) -> bool:
    """Load one installed skill onto an existing PolicyInference. Return True if loaded."""
    path = _installed(skill)
    if path is None:
        return False
    session = ort.InferenceSession(str(path))
    sid = skill["id"]
    if not hasattr(policy, "locomotion_sessions"):
        policy.locomotion_sessions = {}
    if sid == "sitstand":
        policy.sit_session = session
        policy.is_sitstand = True
        return True
    if sid == "roller_crouch":
        policy.crouch_session = session
        return True
    if sid == "pick":
        policy.ground_pick_session = session
        return True
    if skill["kind"] == "trick":
        policy.behavior_sessions[sid] = session
        policy.behavior_durations[sid] = float(skill.get("duration") or 3.0)
        return True
    if skill["kind"] == "locomotion":
        policy.locomotion_sessions[sid] = session
        return True
    if skill["kind"] == "pose":
        policy.behavior_sessions[sid] = session
        policy.behavior_durations[sid] = float(skill.get("duration") or 3.0)
        return True
    return False


def attach_all(policy, body_kind: str = "walk") -> list[str]:
    loaded = []
    for skill in load_catalog():
        if skill.get("body", "walk") != body_kind:
            continue
        try:
            if attach(policy, skill):
                loaded.append(skill["id"])
        except Exception as exc:
            print(f"skill {skill['id']} skipped: {exc}", flush=True)
    if not hasattr(policy, "locomotion_sessions"):
        policy.locomotion_sessions = {}
    if policy.walking_session is not None:
        policy.locomotion_sessions.setdefault("walk", policy.walking_session)
    default = "roller" if body_kind == "rollers" else "walk"
    session = policy.locomotion_sessions.get(default)
    if session is not None:
        policy.walking_session = session
        policy.ort_session = session
        policy.current_policy = "walking"
    if body_kind == "rollers" and getattr(policy, "crouch_session", None) is not None:
        policy.sit_session = policy.crouch_session
        policy.is_sitstand = True
    print(f"skills attached ({body_kind}): {', '.join(loaded) or 'none'}", flush=True)
    return loaded


def set_locomotion(policy, skill_id: str) -> str:
    sessions = getattr(policy, "locomotion_sessions", {})
    session = sessions.get(skill_id)
    if session is None:
        raise ValueError(f"还没下载「{skill_id}」")
    if policy.sit_mode or policy.ground_pick_mode or policy.behavior_mode:
        raise ValueError("现在正做别的动作，做完再切步态")
    policy.walking_session = session
    policy.current_policy = "walking"
    policy.ort_session = session
    policy.vel_cmd[:] = 0
    policy._update_command()
    return skill_id
