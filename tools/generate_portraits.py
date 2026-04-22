"""
Brainrot Autobattler — Character Portrait Generator
----------------------------------------------------
Runs Flux.1-Dev locally on an RTX 5090 via Hugging Face diffusers.

First run:
  1. Accept the Flux.1-Dev license on HF: https://huggingface.co/black-forest-labs/FLUX.1-dev
  2. `huggingface-cli login` with a read token
  3. `python generate_portraits.py`
  4. First model load downloads ~24GB into the HF cache (one-time).

Usage (run from the repo root):
  python tools/generate_portraits.py                        # generate all characters
  python tools/generate_portraits.py tralalero             # just one
  python tools/generate_portraits.py --steps 50 --seed 42  # override defaults
  python tools/generate_portraits.py --list                # print character keys
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Output location — repo-root/assets/characters.
# This script lives in repo-root/tools/, so hop up one directory.
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT  = SCRIPT_DIR.parent
OUTPUT_DIR = REPO_ROOT / "assets" / "characters"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Shared style preamble — keeps the whole roster visually consistent.
# Tuned for the "chaotic-brainrot but readable game UI" direction:
# bold sticker outlines, saturated cartoon colors, toy-shelf aesthetic.
# ---------------------------------------------------------------------------
STYLE_PREAMBLE = (
    "Bold sticker-outline character illustration, thick 5px solid black outline, "
    "cel-shaded lighting with sharp highlights and soft ambient occlusion, "
    "highly saturated vibrant colors, cartoon toy-shelf aesthetic reminiscent of "
    "Brawl Stars / Fortnite stylized heroes / Roblox hero art, 3/4 hero pose, "
    "centered single character, moody atmospheric gradient background with soft "
    "rim light, subtle particle dust in the background, no text, no logos, "
    "no watermarks, no UI, no border frame, square composition, 1:1 aspect."
)

NEGATIVE_PROMPT = (
    "text, letters, logo, watermark, signature, ui, hud, border, frame, "
    "realistic photo, live action, blurry, low quality, lowres, jpeg artifacts, "
    "extra limbs, deformed anatomy, mutated, low contrast, flat lighting, "
    "muted colors, grayscale, pencil sketch, rough draft"
)

# ---------------------------------------------------------------------------
# Character roster — each entry is one "unit portrait" with the canon vibes.
# Add more characters here as the roster grows.
# ---------------------------------------------------------------------------
CHARACTERS: dict[str, dict[str, str]] = {
    "tralalero": {
        "name": "Tralalero Tralala",
        "prompt": (
            "A sapphire-blue cartoon great white shark standing upright on THREE "
            "muscular human legs, each leg wearing a bright white Nike Air Max "
            "style sneaker with blue swoosh, holding a tiny ceramic espresso cup "
            "in one fin, mischievous grin showing sharp teeth, sunglasses perched "
            "on top of its head, absurd chaotic brainrot energy, "
            "ocean-blue gradient background fading from #1a4a7a at the top to "
            "#0B0D14 at the bottom, underwater god-ray light streaks."
        ),
    },
    "bombardiro": {
        "name": "Bombardiro Crocodilo",
        "prompt": (
            "A stocky cartoon crocodile fused with a WWII-era twin-engine bomber "
            "aircraft — olive-green scaly body, riveted metal aircraft wings "
            "growing from its shoulders with small bombs hanging from hardpoints, "
            "yellow-tipped propeller nose on its snout, aviator goggles over its "
            "eyes, squat stubby arms clutching a lit cigar, stern military "
            "expression, absurd chaotic brainrot energy, "
            "gradient background from deep purple #3a1a6a at the top to burnt "
            "orange #5a2a0a at the bottom, smoke and ember particles in the air."
        ),
    },
    "tung": {
        "name": "Tung Tung Tung Sahur",
        "prompt": (
            "An anthropomorphic wooden log creature — thick cylindrical carved "
            "wooden body with visible bark texture and knotholes, a simple "
            "cartoon face carved into the front with round eyes and an open "
            "shouting mouth, two short stubby arms gripping a wooden baseball "
            "bat raised over its shoulder ready to swing, tiny wooden feet, "
            "ominous wide-eyed stare, absurd chaotic brainrot energy, "
            "gradient background from crimson #2a0a0a at the top to dusk orange "
            "#5a2a1a at the bottom, flickering candlelight atmosphere, "
            "dust motes floating in warm backlight."
        ),
    },
}


def build_prompt(char_key: str) -> str:
    """Glue the style preamble to the character-specific prompt."""
    return f"{STYLE_PREAMBLE} {CHARACTERS[char_key]['prompt']}"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Generate Brainrot autobattler character portraits on a local GPU.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument(
        "characters",
        nargs="*",
        help="Character keys to generate (default: all). See --list.",
    )
    p.add_argument("--list", action="store_true", help="List character keys and exit.")
    p.add_argument("--steps", type=int, default=35, help="Diffusion steps.")
    p.add_argument("--guidance", type=float, default=3.5, help="CFG / guidance scale.")
    p.add_argument("--width", type=int, default=1024, help="Output width.")
    p.add_argument("--height", type=int, default=1024, help="Output height.")
    p.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Fixed seed for reproducibility. Default: random per character.",
    )
    p.add_argument(
        "--version",
        type=str,
        default="v1",
        help="Version tag appended to filenames, e.g. v1, v2, alt.",
    )
    p.add_argument(
        "--model",
        type=str,
        default="black-forest-labs/FLUX.1-dev",
        help="HF model id. Swap to FLUX.1-schnell for faster / lower-quality runs.",
    )
    p.add_argument(
        "--offload",
        action="store_true",
        help="Enable CPU offload (use if VRAM is tight; 5090 32GB should not need it).",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()

    if args.list:
        print("Available characters:")
        for key, cfg in CHARACTERS.items():
            print(f"  {key:<12} -> {cfg['name']}")
        return 0

    to_run = args.characters or list(CHARACTERS.keys())
    unknown = [c for c in to_run if c not in CHARACTERS]
    if unknown:
        print(f"Unknown characters: {unknown}. Use --list to see valid keys.", file=sys.stderr)
        return 1

    # Imports are done lazily so `--list` / `--help` don't pay the torch import cost.
    import torch
    from diffusers import FluxPipeline

    if not torch.cuda.is_available():
        print(
            "CUDA is not available. Verify you installed the CUDA 12.8 PyTorch build "
            "(see GENERATE_SETUP.md) and that your 5090 driver is up to date.",
            file=sys.stderr,
        )
        return 2

    device_name = torch.cuda.get_device_name(0)
    print(f"[info] CUDA device: {device_name}")
    print(f"[info] Loading model: {args.model} (bfloat16) — first run downloads ~24GB")
    t0 = time.time()
    pipe = FluxPipeline.from_pretrained(args.model, torch_dtype=torch.bfloat16)
    if args.offload:
        pipe.enable_model_cpu_offload()
    else:
        pipe.to("cuda")
    print(f"[info] Model ready in {time.time() - t0:.1f}s")

    for char_key in to_run:
        cfg = CHARACTERS[char_key]
        prompt = build_prompt(char_key)
        seed = args.seed if args.seed is not None else torch.seed() & 0xFFFFFFFF
        generator = torch.Generator(device="cuda").manual_seed(int(seed))

        out_path = OUTPUT_DIR / f"{char_key}_{args.version}.png"
        print(f"\n[gen] {cfg['name']}  (seed={seed}, steps={args.steps})")
        t1 = time.time()
        image = pipe(
            prompt=prompt,
            negative_prompt=NEGATIVE_PROMPT,
            width=args.width,
            height=args.height,
            num_inference_steps=args.steps,
            guidance_scale=args.guidance,
            generator=generator,
        ).images[0]
        image.save(out_path)
        print(f"[gen] -> {out_path}  ({time.time() - t1:.1f}s)")

    print("\n[don