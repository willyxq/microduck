"""Load the shipped MicroDuck ONNX gait into the Body-sim MuJoCo world.

The weights are the same 61-D family robotd ships (`policies/alpha_*.onnx`),
trained in microduck_rl and driven here by infer_policy.PolicyInference.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
RL_SCRIPTS = REPO.parent / "microduck_rl" / "scripts"
POLICIES = REPO / "policies"


def default_paths() -> dict[str, Path]:
    return {
        "walk": Path(__import__("os").environ.get("DUCK_BODY_WALK", POLICIES / "alpha_walking.onnx")),
        "stand": Path(__import__("os").environ.get("DUCK_BODY_STAND", POLICIES / "alpha_stand.onnx")),
        "sitstand": Path(__import__("os").environ.get("DUCK_BODY_SITSTAND", POLICIES / "alpha_sitstand.onnx")),
    }


def load_gait(model, data, body_kind: str = "walk"):
    """Return a PolicyInference or None if the bundle cannot be loaded."""
    paths = default_paths()
    if body_kind == "rollers":
        from skills import INSTALLED, AVAILABLE

        roller = INSTALLED / "roller.onnx"
        if not roller.exists():
            roller = AVAILABLE / "roller.onnx"
        if roller.exists():
            paths["walk"] = roller
    if not paths["walk"].exists():
        print(f"gait skipped: no walk policy at {paths['walk']}", flush=True)
        return None
    if str(RL_SCRIPTS) not in sys.path:
        sys.path.insert(0, str(RL_SCRIPTS))
    try:
        import onnxruntime  # noqa: F401
        from infer_policy import PolicyInference
    except Exception as exc:
        print(f"gait skipped: {exc}", flush=True)
        return None
    kwargs = {
        "walking_onnx_path": str(paths["walk"]),
        "new_cmd_obs": True,
        "use_projected_gravity": True,
    }
    if paths["stand"].exists() and body_kind != "rollers":
        kwargs["standing_onnx_path"] = str(paths["stand"])
    if paths["sitstand"].exists() and body_kind != "rollers":
        kwargs["sitstand_onnx_path"] = str(paths["sitstand"])
    policy = PolicyInference(model, data, **kwargs)
    from skills import attach_all

    attach_all(policy, body_kind=body_kind)
    print(
        f"gait onnx body={body_kind} walk={paths['walk'].name} stand={paths['stand'].name if paths['stand'].exists() else '-'} "
        f"sitstand={paths['sitstand'].name if paths['sitstand'].exists() else '-'}",
        flush=True,
    )
    return policy
