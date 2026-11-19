"""Make napari-convpaint store downloaded weights under TORCH_HOME.

convpaint's guided_model_download() hard-codes ~/.cache/torch/hub/checkpoints,
while torch.hub (used for DINOv2) follows TORCH_HOME. With this patch both use
torch.hub.get_dir()/checkpoints, which env.ps1 points into the bundle.
Run with the python of the env to patch. Idempotent.
"""
import importlib.util
import pathlib
import sys

spec = importlib.util.find_spec("napari_convpaint")
if spec is None:
    print("[--] napari_convpaint not installed in", sys.prefix)
    sys.exit(0)
p = pathlib.Path(spec.origin).parent / "utils.py"
src = p.read_text(encoding="utf-8")
old = "model_dir = os.path.expanduser('~/.cache/torch/hub/checkpoints')"
new = "model_dir = os.path.join(__import__('torch').hub.get_dir(), 'checkpoints')  # faro-offline patch"
if new in src:
    print("[ok] convpaint already patched:", p)
elif old in src:
    p.write_text(src.replace(old, new), encoding="utf-8")
    print("[ok] convpaint patched:", p)
else:
    print("[!!] convpaint download code changed upstream, patch not applied:", p)
    sys.exit(1)
