#!/usr/bin/env python3
"""
setup_wizard.py - Interactive setup wizard for the KM plot digitizer.

Usage:
    python setup_wizard.py <image_path> [output_dir]

Displays the KM plot image and guides the user through clicking to define
plot boundaries and calibration points, then writes config.json ready for
digitize_km.py.
"""

import sys
import os
import json
import subprocess

import matplotlib
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np


# ---------------------------------------------------------------------------
# Terminal input helpers
# ---------------------------------------------------------------------------

def prompt(msg, default=None):
    suffix = f" [{default}]" if default is not None else ""
    val = input(f"{msg}{suffix}: ").strip()
    return str(default) if (val == "" and default is not None) else val


def prompt_float(msg, default=None):
    while True:
        try:
            return float(prompt(msg, default))
        except ValueError:
            print("  Please enter a number.")


def prompt_int(msg, default=None):
    while True:
        try:
            return int(prompt(msg, default))
        except ValueError:
            print("  Please enter an integer.")


def prompt_pair(msg, default=None):
    """Parse 'a, b' into [float, float]. Accepts brackets, commas, or spaces."""
    while True:
        raw = prompt(msg, default).strip("[]() ")
        parts = raw.replace(",", " ").split()
        try:
            return [float(parts[0]), float(parts[1])]
        except (ValueError, IndexError):
            print("  Please enter two numbers, e.g. 0, 72")


def prompt_list(msg, default=None):
    """Parse comma/tab-separated values into list of ints."""
    while True:
        raw = prompt(msg, default)
        parts = raw.replace("\t", ",").replace(" ", ",").split(",")
        parts = [p.strip() for p in parts if p.strip()]
        try:
            return [int(float(p)) for p in parts]
        except ValueError:
            print("  Please enter integers separated by commas.")


# ---------------------------------------------------------------------------
# Figure helpers
# ---------------------------------------------------------------------------

CAL_COLORS = ["#e74c3c", "#3498db", "#2ecc71", "#f39c12", "#9b59b6",
              "#1abc9c", "#e67e22", "#8e44ad"]


def set_instruction(ax, fig, text):
    ax.set_title(text, fontsize=10, color="navy", pad=6, wrap=True)
    fig.canvas.draw_idle()
    plt.pause(0.05)


def draw_vline(ax, fig, x, label=None):
    ax.axvline(x=x, color="limegreen", linewidth=1.5, linestyle="--", alpha=0.9, zorder=4)
    if label:
        ylim = ax.get_ylim()
        ax.text(x + 4, (ylim[0] + ylim[1]) / 2, label,
                color="limegreen", fontsize=8, va="center",
                bbox=dict(facecolor="white", alpha=0.6, edgecolor="none", pad=1))
    fig.canvas.draw_idle()
    plt.pause(0.05)


def draw_hline(ax, fig, y, label=None):
    ax.axhline(y=y, color="limegreen", linewidth=1.5, linestyle="--", alpha=0.9, zorder=4)
    if label:
        xlim = ax.get_xlim()
        ax.text((xlim[0] + xlim[1]) / 2, y - 5, label,
                color="limegreen", fontsize=8, ha="center",
                bbox=dict(facecolor="white", alpha=0.6, edgecolor="none", pad=1))
    fig.canvas.draw_idle()
    plt.pause(0.05)


def draw_box(ax, fig, left, top, right, bottom):
    rect = patches.Rectangle(
        (left, top), right - left, bottom - top,
        linewidth=2, edgecolor="limegreen", facecolor="none", linestyle="-", zorder=5
    )
    ax.add_patch(rect)
    fig.canvas.draw_idle()
    plt.pause(0.05)


def draw_cal_point(ax, fig, x, y, time_val, surv_val, curve_idx):
    color = CAL_COLORS[curve_idx % len(CAL_COLORS)]
    ax.plot(x, y, "o", color=color, markersize=10,
            markeredgecolor="white", markeredgewidth=1.5, zorder=6)
    ax.annotate(
        f"t={time_val}, {surv_val}%",
        (x, y), xytext=(8, -14), textcoords="offset points",
        fontsize=8, color=color,
        bbox=dict(boxstyle="round,pad=0.2", facecolor="white", alpha=0.75, edgecolor=color)
    )
    fig.canvas.draw_idle()
    plt.pause(0.05)


def get_one_click(ax, fig, instruction):
    set_instruction(ax, fig, instruction + "\n(click once in the image)")
    pts = plt.ginput(1, timeout=-1)
    if not pts:
        print("  No click received.")
        return None
    return pts[0]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2:
        print("Usage: python setup_wizard.py <image_path> [output_dir]")
        sys.exit(1)

    image_path = os.path.abspath(sys.argv[1])
    if not os.path.isfile(image_path):
        print(f"Error: image not found: {image_path}")
        sys.exit(1)

    default_output_dir = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.dirname(image_path)

    # ── Load image ───────────────────────────────────────────────────────────
    img = plt.imread(image_path)
    h_px, w_px = img.shape[:2]

    fig, ax = plt.subplots(figsize=(14, 9))
    ax.imshow(img, origin="upper")
    ax.axis("off")
    fig.suptitle("KM Digitizer Setup Wizard", fontsize=12, fontweight="bold")
    plt.tight_layout()
    plt.show(block=False)
    plt.pause(0.3)

    print("\n" + "=" * 60)
    print("  KM Digitizer — Interactive Setup Wizard")
    print("=" * 60)
    print(f"  Image : {image_path}")
    print(f"  Size  : {w_px} x {h_px} px")
    print("=" * 60)

    # ── STEP 1: Axis boundaries (4 individual clicks) ────────────────────────
    print("\n[Step 1/5] Click to define plot boundaries.")
    print("  Use the image window. Instructions appear in the figure title.")

    pt = get_one_click(ax, fig, "Click 1/4 — Y-axis (left edge of data area)")
    if pt is None: sys.exit(1)
    left = int(round(pt[0]))
    draw_vline(ax, fig, left, f"left={left}")
    print(f"  Left  : col = {left}")

    pt = get_one_click(ax, fig, "Click 2/4 — Right edge of data area (t = max)")
    if pt is None: sys.exit(1)
    right = int(round(pt[0]))
    draw_vline(ax, fig, right, f"right={right}")
    print(f"  Right : col = {right}")

    pt = get_one_click(ax, fig, "Click 3/4 — 100% survival gridline (top of Y-axis)")
    if pt is None: sys.exit(1)
    top = int(round(pt[1]))
    draw_hline(ax, fig, top, f"top={top} (100%)")
    print(f"  Top   : row = {top}")

    pt = get_one_click(ax, fig, "Click 4/4 — X-axis / 0% level (bottom of Y-axis)")
    if pt is None: sys.exit(1)
    bottom = int(round(pt[1]))
    draw_hline(ax, fig, bottom, f"bottom={bottom} (0%)")
    print(f"  Bottom: row = {bottom}")

    # Sanitize order
    if left > right:
        left, right = right, left
    if top > bottom:
        top, bottom = bottom, top

    draw_box(ax, fig, left, top, right, bottom)
    print(f"\n  plot_region: left={left}, top={top}, right={right}, bottom={bottom}")

    # ── STEP 2: Axis metadata ────────────────────────────────────────────────
    print("\n[Step 2/5] Axis metadata (type in terminal).")

    x_range  = prompt_pair("  X-axis range (min, max)", "0, 72")
    y_range  = prompt_pair("  Y-axis range (min, max)", "0, 100")
    x_label  = prompt("  X-axis label", "Time (months)")
    y_label  = prompt("  Y-axis label", "OS (%)")
    n_curves = prompt_int("  Number of curve arms", 2)

    curve_names = []
    for i in range(n_curves):
        default_name = f"Arm {chr(65 + i)}"
        name = prompt(f"  Curve {i + 1} name (rank order: 0 = highest survival)", default_name)
        curve_names.append(name)

    # ── STEP 3: Calibration points ───────────────────────────────────────────
    print("\n[Step 3/5] Calibration points.")
    print("  Click a point whose time and survival% you know from the figure annotation.")
    print("  Recommended: 2+ points per curve (4+ total) for best accuracy.")
    n_cal = prompt_int("  How many calibration points? (0 to skip)", 4)

    calibration_points = []
    for i in range(n_cal):
        print(f"\n  Calibration point {i + 1}/{n_cal}:")
        curve_idx = prompt_int(
            f"  Curve index (0={curve_names[0] if curve_names else 'top'}, "
            f"1={curve_names[1] if len(curve_names) > 1 else 'bottom'})", 0)

        pt = get_one_click(
            ax, fig,
            f"Cal point {i + 1}/{n_cal} (curve {curve_idx}={curve_names[curve_idx] if curve_idx < len(curve_names) else curve_idx})"
            f" — then type values in terminal"
        )
        if pt is None:
            print("  Skipped.")
            continue

        time_val = prompt_float("  Time value at this point")
        surv_val = prompt_float("  Survival% at this point")

        calibration_points.append({"month": time_val, "survival": surv_val, "curve": curve_idx})
        draw_cal_point(ax, fig, pt[0], pt[1], time_val, surv_val, curve_idx)
        print(f"  Recorded: t={time_val}, survival={surv_val}%, curve={curve_idx}")

    # ── STEP 4: Number at risk ───────────────────────────────────────────────
    print("\n[Step 4/5] Number at risk table.")
    add_nar = prompt("  Add number at risk? (y/n)", "y").lower().startswith("y")

    number_at_risk = None
    if add_nar:
        n_ticks = int(round((x_range[1] - x_range[0]) / 12)) + 1
        default_times = ", ".join(str(int(x_range[0] + 12 * i)) for i in range(n_ticks))
        nar_times = prompt_list("  Timepoints (comma-separated)", default_times)

        nar_counts = {}
        for name in curve_names:
            raw = prompt(
                f"  Counts for '{name}' ({len(nar_times)} values, comma-separated)",
                ", ".join(["0"] * len(nar_times))
            )
            parts = raw.replace("\t", ",").split(",")
            counts = []
            for p in parts:
                p = p.strip()
                if p:
                    try:
                        counts.append(int(float(p)))
                    except ValueError:
                        counts.append(0)
            while len(counts) < len(nar_times):
                counts.append(0)
            nar_counts[name] = counts[:len(nar_times)]

        number_at_risk = {"times": nar_times, "counts": nar_counts}

    # ── STEP 5: Output paths ─────────────────────────────────────────────────
    print("\n[Step 5/5] Output paths.")
    study_name = prompt("  Study name (used for filenames)", "km_study")
    output_dir = prompt(
        "  Output directory",
        os.path.join(default_output_dir, study_name)
    )
    output_path = os.path.join(output_dir, "km_digitized.json")
    debug_image = os.path.join(output_dir, "km_debug.png")

    # ── Final figure update and close ────────────────────────────────────────
    set_instruction(ax, fig, "Setup complete — close this window to write config.json")
    print("\nClose the figure window to continue...")
    plt.show(block=True)

    # ── Assemble config ──────────────────────────────────────────────────────
    config = {
        "image_path": image_path.replace("\\", "/"),
        "plot_region": {"left": left, "top": top, "right": right, "bottom": bottom},
        "x_range": x_range,
        "y_range": y_range,
        "x_label": x_label,
        "y_label": y_label,
        "curve_names": curve_names,
        "output_path": output_path.replace("\\", "/"),
        "debug_image": debug_image.replace("\\", "/"),
    }
    if calibration_points:
        config["calibration_points"] = calibration_points
    if number_at_risk:
        config["number_at_risk"] = number_at_risk

    # ── Write config.json ────────────────────────────────────────────────────
    os.makedirs(output_dir, exist_ok=True)
    config_path = os.path.join(output_dir, "config.json")

    with open(config_path, "w") as f:
        json.dump(config, f, indent=4)

    print(f"\nConfig written to: {config_path}")
    print(json.dumps(config, indent=4))

    # ── Optionally run digitizer ─────────────────────────────────────────────
    run_now = prompt("\nRun digitize_km.py now? (y/n)", "y").lower().startswith("y")
    if run_now:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        digitize_script = os.path.join(script_dir, "digitize_km.py")
        print(f"\nRunning digitizer...\n")
        subprocess.run([sys.executable, digitize_script, config_path], check=True)
        print(f"\nOutput : {output_path}")
        print(f"Debug  : {debug_image}")
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        print(f"\nRun when ready:")
        print(f"  python {os.path.join(script_dir, 'digitize_km.py')} {config_path}")


if __name__ == "__main__":
    main()
