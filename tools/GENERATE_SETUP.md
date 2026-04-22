# Portrait Generation — Local Setup (RTX 5090)

This document walks you through running `generate_portraits.py` on your RTX 5090 using Hugging Face `diffusers` and Flux.1-Dev. After setup, each character portrait takes roughly 15–25 seconds at 1024×1024 on a 5090.

---

## 0. One-time prerequisites

### Accept the Flux.1-Dev license on Hugging Face

Flux.1-Dev is a gated model. You cannot download it until you accept the license.

1. Open https://huggingface.co/black-forest-labs/FLUX.1-dev in a browser.
2. Log in with the same HF account you're using locally (`rescuedbuffalo`).
3. Click "Agree and access repository".

> If you skip this step the first run will fail with a 403 or "gated repo" error.

### Create a read token

1. Go to https://huggingface.co/settings/tokens → "New token" → role "Read".
2. Copy the token. You'll paste it into `huggingface-cli login` below.

---

## 1. Install Python 3.11

PowerShell (not admin required):

```powershell
winget install --id Python.Python.3.11 -e
```

Close and reopen PowerShell so `python --version` picks up the new install. Confirm:

```powershell
python --version
# Python 3.11.x
```

## 2. Create a virtual environment (recommended)

Keeps the ~5 GB of ML deps out of your global site-packages.

```powershell
cd C:\Users\aidan\workspace\brainrot-battlers
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

> The `.venv` folder is already in `.gitignore`. Do not commit it.

If activation is blocked by execution policy, run once:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Your prompt should now show `(.venv)` at the start.

## 3. Install PyTorch with CUDA 12.8 (required for Blackwell / RTX 5090)

The RTX 5090 uses the Blackwell architecture, which needs PyTorch built against CUDA 12.8 or newer. The default `pip install torch` pulls an older CUDA build that will NOT detect your 5090.

```powershell
pip install --upgrade pip
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128
```

Verify CUDA is visible:

```powershell
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
# Expected: True NVIDIA GeForce RTX 5090
```

> If `torch.cuda.is_available()` prints `False`, try the nightly build instead:
> `pip install --pre torch torchvision --index-url https://download.pytorch.org/whl/nightly/cu128`

## 4. Install diffusers + the rest

```powershell
pip install diffusers transformers accelerate sentencepiece protobuf pillow huggingface_hub
```

## 5. Log in to Hugging Face

```powershell
huggingface-cli login
```

Paste the read token from step 0. It's cached in `%USERPROFILE%\.cache\huggingface\token`, so you only do this once per machine.

## 6. First run

```powershell
python tools/generate_portraits.py
```

What to expect:

- First launch downloads **~24 GB** of Flux.1-Dev weights into `%USERPROFILE%\.cache\huggingface\hub\`. This is a one-time cost. Subsequent runs load from cache in about 20–40 seconds.
- VRAM use peaks around 24–28 GB during generation. Your 5090's 32 GB handles it comfortably without offload.
- Each 1024×1024 portrait takes roughly 15–25 seconds at the default 35 steps.

Outputs land in `assets/characters/`:

```
tralalero_v1.png
bombardiro_v1.png
tung_v1.png
```

---

## Useful invocations

```powershell
# Just regenerate Tralalero (other two stay on disk untouched)
python tools/generate_portraits.py tralalero

# Try a second take of all three with a new version tag
python tools/generate_portraits.py --version v2

# Reproducible output — same seed, same result
python tools/generate_portraits.py --seed 1337 --version seed1337

# Faster preview pass (lower quality)
python tools/generate_portraits.py --steps 20 --version quick

# List the character keys the script knows about
python tools/generate_portraits.py --list
```

---

## Troubleshooting

**`torch.cuda.is_available()` returns False**
Your PyTorch build is likely CPU-only or CUDA 12.1. Uninstall and reinstall with the cu128 index URL from step 3. If the stable cu128 build still doesn't detect your 5090, use the nightly wheel (see step 3 note).

**`OSError: You are trying to access a gated repo`**
You skipped step 0 — open the Flux.1-Dev page and click "Agree and access repository", then rerun.

**Out-of-memory (unlikely on 5090, but if you see CUDA OOM):**
Add `--offload` to the command: `python tools/generate_portraits.py --offload`. This streams weights between CPU and GPU memory at a ~2x speed cost.

**Very slow generation (>2 min per image)**
CUDA probably isn't actually being used. Re-verify step 3. Also confirm the printed `[info] CUDA device: ...` line says `RTX 5090` and not `cpu`.

**Character doesn't match the canon well enough**
Edit the relevant entry in `CHARACTERS` inside `generate_portraits.py`. The style preamble is shared, so keep character-specific changes in the per-character `prompt` string. Regenerate with `--version v2` to keep v1 around as a reference.

---

## When you add new characters

Open `generate_portraits.py`, add an entry to the `CHARACTERS` dict:

```python
"new_key": {
    "name": "Character Display Name",
    "prompt": (
        "Character-specific description: body, pose, key accessories, "
        "color palette hints, background gradient."
    ),
},
```

Then: `python tools/generate_portraits.py new_key`.

## Model alternatives

- `black-forest-labs/FLUX.1-dev` (default) — best quality, 35 steps, gated.
- `black-forest-labs/FLUX.1-schnell` — 4-step distilled variant, ~4x faster, less detail. Not gated. Swap via `--model black-forest-labs/FLUX.1-schnell --steps 4 --guidan