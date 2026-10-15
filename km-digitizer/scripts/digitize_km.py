"""
KM Plot Digitizer — extract survival curves from Kaplan-Meier plot images.

Usage:
    python digitize_km.py config.json

Config JSON:
{
    "image_path": "path/to/km_plot.png",
    "plot_region": {"left": 150, "top": 85, "right": 820, "bottom": 430},
    "x_range": [0, 72],
    "y_range": [0, 100],
    "calibration_points": [
        {"month": 12, "survival": 69.8, "curve": 0},
        {"month": 12, "survival": 49.6, "curve": 1},
        {"month": 60, "survival": 18.4, "curve": 0},
        {"month": 60, "survival": 9.7,  "curve": 1}
    ],
    "output_path": "output/km_digitized.json",
    "curve_names": ["Arm A", "Arm B"],
    "debug_image": "output/km_debug.png"
}

plot_region: initial estimate of pixel coordinates for the data area.
    If calibration_points are provided, plot_region is auto-refined.
calibration_points: known (month, survival%) values. "curve" field is optional:
    0 = top curve (highest survival, default), 1 = bottom curve.
    Using points from BOTH curves gives much better calibration.
"""

import cv2
import numpy as np
import json
import sys
import os


# ---------------------------------------------------------------------------
# Color detection
# ---------------------------------------------------------------------------

def _hue_to_name(h):
    if h < 10 or h >= 170:
        return "red"
    if h < 25:
        return "orange"
    if h < 35:
        return "yellow"
    if h < 80:
        return "green"
    if h < 105:
        return "cyan"
    if h < 130:
        return "blue"
    if h < 150:
        return "purple"
    return "magenta"


def find_peaks_simple(hist, min_count, min_distance=20):
    peaks = []
    n = len(hist)
    for i in range(1, n - 1):
        if hist[i] < min_count:
            continue
        lo = max(0, i - min_distance)
        hi = min(n, i + min_distance + 1)
        if hist[i] == max(hist[lo:hi]):
            peaks.append(i)
    merged = []
    for p in peaks:
        if merged and p - merged[-1] < min_distance:
            if hist[p] > hist[merged[-1]]:
                merged[-1] = p
        else:
            merged.append(p)
    return merged


def auto_detect_colors(hsv_img):
    """Detect distinct curve colors by clustering high-saturation pixels."""
    h, s, v = cv2.split(hsv_img)
    sat_mask = (s > 50) & (v > 60)
    hues = h[sat_mask]
    if len(hues) == 0:
        return {}

    hist = np.bincount(hues.ravel(), minlength=180).astype(float)
    kernel = np.ones(7) / 7
    hist_smooth = np.convolve(hist, kernel, mode="same")

    min_count = len(hues) * 0.01
    peaks = find_peaks_simple(hist_smooth, min_count, min_distance=20)

    colors = {}
    for peak in peaks:
        h_lo = max(0, peak - 12)
        h_hi = min(179, peak + 12)
        if peak < 12:
            ranges = [(0, h_hi), (180 + peak - 12, 179)]
        elif peak > 167:
            ranges = [(h_lo, 179), (0, peak + 12 - 180)]
        else:
            ranges = [(h_lo, h_hi)]
        colors[_hue_to_name(peak)] = {"h_ranges": ranges, "s_min": 50, "v_min": 60}
    return colors


# ---------------------------------------------------------------------------
# Curve tracking
# ---------------------------------------------------------------------------

def build_color_mask(img_hsv, color_def):
    """Binary mask for one color."""
    h, s, v = cv2.split(img_hsv)
    mask = np.zeros(h.shape, dtype=bool)
    for lo, hi in color_def["h_ranges"]:
        mask |= (h >= lo) & (h <= hi)
    mask &= (s >= color_def["s_min"]) & (v >= color_def["v_min"])
    return mask


def find_curve_start(mask):
    """Find the starting (leftmost, topmost) position of a curve."""
    u8 = cv2.morphologyEx(mask.astype(np.uint8) * 255,
                          cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    n, labels, stats, _ = cv2.connectedComponentsWithStats(u8, 8)
    if n <= 1:
        return None, None
    biggest = np.argmax(stats[1:, cv2.CC_STAT_AREA]) + 1
    main = (labels == biggest)
    for c in range(main.shape[1]):
        rows = np.where(main[:, c])[0]
        if len(rows) > 0:
            return c, float(np.median(rows))
    return None, None


def track_curve(mask, start_col, start_row):
    """Track a KM curve bidirectionally using the raw color mask.

    Scans rightward (survival drops) and leftward (survival rises) from start.
    """
    profile = {}
    current_row = start_row
    gap = 0

    # --- Rightward: survival drops, rows increase ---
    for c in range(start_col, mask.shape[1]):
        extra = min(gap * 8, 120)
        # KM survival is non-increasing → rows only increase.
        # Setting lo = current_row excludes all pixels above the current
        # position, which is where censoring ticks live.  A 1-pixel tolerance
        # handles anti-aliasing at the horizontal flat segments.
        lo = max(0, int(current_row) - 1)
        hi = min(mask.shape[0], int(current_row + 15 + extra))
        rows = np.where(mask[lo:hi, c])[0] + lo

        if len(rows) > 0:
            # Gap check: if disconnected clusters remain (rare with tight lo),
            # take the bottom cluster (curve, not a nearby artifact above).
            pixel_gaps = np.diff(rows)
            split = np.where(pixel_gaps > 3)[0]
            curve_rows = rows[split[-1] + 1:] if len(split) > 0 else rows
            y = float(np.median(curve_rows))
            profile[c] = y
            current_row = max(current_row, y)  # never allow upward drift
            gap = 0
        else:
            gap += 1
            if gap > 50:
                break

    # --- Leftward: survival rises, rows decrease ---
    current_row = start_row
    gap = 0
    for c in range(start_col - 1, -1, -1):
        extra = min(gap * 8, 120)
        lo = max(0, int(current_row - 15 - extra))
        hi = min(mask.shape[0], int(current_row + 5))
        rows = np.where(mask[lo:hi, c])[0] + lo

        if len(rows) > 0:
            y = float(np.median(rows))
            profile[c] = y
            current_row = min(current_row + 2, y)
            gap = 0
        else:
            gap += 1
            if gap > 50:
                break

    return profile


# ---------------------------------------------------------------------------
# Calibration — uses ALL curves' calibration points jointly
# ---------------------------------------------------------------------------

def optimize_region(profiles_ordered, cal_pts, x_range, init_region, img_shape):
    """Refine plot_region using iterative least-squares + local refinement.

    Runs in <1 second regardless of image size (replaces slow grid search).
    """
    x_min, x_max = x_range
    x_span = x_max - x_min

    # Build per-curve column arrays for fast nearest-neighbor lookup
    curve_col_arrays = [np.array(sorted(prof.keys())) for prof in profiles_ordered]

    def find_row(ci, col):
        arr = curve_col_arrays[ci]
        idx = int(np.argmin(np.abs(arr - col)))
        if abs(int(arr[idx]) - col) > 10:
            return None
        return profiles_ordered[ci][int(arr[idx])]

    # --- Step 1: Iterative least-squares (fast, O(n) per iteration) ---
    L, T = float(init_region["left"]), float(init_region["top"])
    R, B = float(init_region["right"]), float(init_region["bottom"])

    for _ in range(8):
        fxs, fys, cols_found, rows_found = [], [], [], []
        for pt in cal_pts:
            ci = pt.get("curve", 0)
            if ci >= len(profiles_ordered):
                continue
            fx = (pt["month"] - x_min) / x_span
            fy = 1.0 - pt["survival"] / 100.0
            col = int(L + fx * (R - L))
            row = find_row(ci, col)
            if row is None:
                continue
            fxs.append(fx)
            fys.append(fy)
            cols_found.append(col)
            rows_found.append(row)

        if len(rows_found) < 2:
            break

        # Solve row_i = T*(1-fy_i) + B*fy_i  for T, B
        A_y = np.column_stack([1.0 - np.array(fys), np.array(fys)])
        tb, _, _, _ = np.linalg.lstsq(A_y, np.array(rows_found), rcond=None)
        T_new, B_new = float(tb[0]), float(tb[1])
        T_new = max(-10.0, T_new)  # allow slight negative top (plot frame above image edge)

        # Solve col_i = L*(1-fx_i) + R*fx_i  for L, R
        A_x = np.column_stack([1.0 - np.array(fxs), np.array(fxs)])
        lr, _, _, _ = np.linalg.lstsq(A_x, np.array(cols_found, dtype=float),
                                       rcond=None)
        L_new, R_new = float(lr[0]), float(lr[1])

        if (abs(L_new - L) < 1 and abs(R_new - R) < 1 and
                abs(T_new - T) < 1 and abs(B_new - B) < 1):
            L, T, R, B = L_new, T_new, R_new, B_new
            break
        L, T, R, B = L_new, T_new, R_new, B_new

    L, T, R, B = int(round(L)), int(round(T)), int(round(R)), int(round(B))

    # --- Step 2: Small local grid refinement (+/-5 px, ~160k evals) ---
    def eval_params(L, T, R, B):
        total_err, count = 0.0, 0
        for pt in cal_pts:
            ci = pt.get("curve", 0)
            if ci >= len(profiles_ordered):
                continue
            col = int(L + (pt["month"] - x_min) / x_span * (R - L))
            row = find_row(ci, col)
            if row is None:
                return 1e6
            if B == T:
                return 1e6
            surv = 100 * (1 - (row - T) / (B - T))
            total_err += (surv - pt["survival"]) ** 2
            count += 1
        return total_err / max(count, 1)

    best_err = eval_params(L, T, R, B)
    best = (L, T, R, B)
    for dL in range(-5, 6):
        for dT in range(-5, 6):
            if T + dT < -10:
                continue
            for dR in range(-5, 6):
                for dB in range(-8, 9):
                    e = eval_params(L + dL, T + dT, R + dR, B + dB)
                    if e < best_err:
                        best_err, best = e, (L + dL, T + dT, R + dR, B + dB)

    L, T, R, B = best
    return {"left": L, "top": T, "right": R, "bottom": B}, np.sqrt(best_err)


# ---------------------------------------------------------------------------
# Point extraction & simplification
# ---------------------------------------------------------------------------

def profile_to_points(profile, region, x_range, y_range):
    L, T, R, B = region["left"], region["top"], region["right"], region["bottom"]
    x_min, x_max = x_range
    y_min, y_max = y_range
    points = []
    for c in sorted(profile.keys()):
        x = x_min + (c - L) / (R - L) * (x_max - x_min)
        y = y_max - (profile[c] - T) / (B - T) * (y_max - y_min)
        y = max(y_min, min(y_max, y))
        x = max(x_min, min(x_max, x))
        points.append((round(x, 2), round(y, 2)))
    return points


def simplify_to_changes(points, y_tol=1.0):
    """Reduce to step-function change points."""
    if len(points) < 2:
        return [{"time": p[0], "survival": p[1]} for p in points]
    out = [points[0]]
    for i in range(1, len(points)):
        if abs(points[i][1] - out[-1][1]) > y_tol:
            if points[i - 1] != out[-1]:
                out.append(points[i - 1])
            out.append(points[i])
    if points[-1] != out[-1]:
        out.append(points[-1])
    return [{"time": round(p[0], 2), "survival": round(p[1], 1)} for p in out]


# ---------------------------------------------------------------------------
# Debug overlay
# ---------------------------------------------------------------------------

def save_debug_image(img, region, profiles, color_names, output_path):
    overlay = img.copy()
    pr = region
    cv2.rectangle(overlay, (pr["left"], pr["top"]), (pr["right"], pr["bottom"]),
                  (0, 255, 0), 2)
    bright = [(0, 255, 255), (255, 0, 255), (0, 165, 255), (255, 255, 0)]
    for idx, (prof, name) in enumerate(zip(profiles, color_names)):
        color = bright[idx % len(bright)]
        for c, r in prof.items():
            r_int = int(round(r))
            if 0 <= r_int < overlay.shape[0] and 0 <= c < overlay.shape[1]:
                cv2.circle(overlay, (c, r_int), 4, color, -1)
    cv2.imwrite(output_path, overlay)
    print(f"Debug overlay saved: {output_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def digitize_km(config):
    img = cv2.imread(config["image_path"])
    if img is None:
        raise ValueError(f"Cannot read: {config['image_path']}")

    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    x_range = config["x_range"]
    y_range = config["y_range"]
    region = config["plot_region"]
    curve_names = config.get("curve_names", [])
    cal_pts = config.get("calibration_points", [])

    # Default "curve" field to 0 (top curve) if not specified
    for pt in cal_pts:
        pt.setdefault("curve", 0)

    # Restrict color detection to the approximate plot area (with margin)
    margin = 50
    roi_t = max(0, region["top"] - margin)
    roi_b = min(img.shape[0], region["bottom"] + margin)
    roi_l = max(0, region["left"] - margin)
    roi_r = min(img.shape[1], region["right"] + margin)
    hsv_roi = hsv[roi_t:roi_b, roi_l:roi_r]

    colors = auto_detect_colors(hsv_roi)
    if not colors:
        raise ValueError("No colored curves detected.")

    print(f"Colors detected: {list(colors.keys())}")

    extract_idx = config.get("extract_curve")

    # Build full-image masks and track each curve
    profiles = []
    profile_names = []
    masks = []

    for color_name, color_def in colors.items():
        mask = build_color_mask(hsv, color_def)
        start_col, start_row = find_curve_start(mask)
        if start_col is None:
            continue

        prof = track_curve(mask, start_col, start_row)
        if len(prof) < 100:
            print(f"  {color_name}: skipped ({len(prof)} cols, too sparse)")
            continue

        # Discard leftward-tracked columns where the tracker failed to move
        # meaningfully upward from start_row (stuck plateau from overlap zone
        # where both curves' pixels are interleaved near 100% survival).
        # Only keep leftward columns that rose at least 10 px above start_row.
        stuck_threshold = start_row - 30
        prof = {c: r for c, r in prof.items()
                if c >= start_col or r < stuck_threshold}

        plot_left = region["left"]
        plot_top = region["top"]
        plot_bot = region["bottom"]

        rows_range = (min(prof.values()), max(prof.values()))
        print(f"  {color_name}: {len(prof)} cols, rows {rows_range[0]:.0f}-{rows_range[1]:.0f}")
        profiles.append(prof)
        profile_names.append(color_name)
        masks.append(mask)

    if not profiles:
        raise ValueError("No curves tracked successfully.")

    # If extracting a single curve, keep only that one
    if extract_idx is not None and extract_idx < len(profiles):
        profiles = [profiles[extract_idx]]
        profile_names = [profile_names[extract_idx]]
        masks = [masks[extract_idx]]

    # Sort profiles by starting row (lowest row = highest survival = top curve)
    profiles_sorted_idx = sorted(range(len(profiles)),
                                 key=lambda i: list(profiles[i].values())[0])
    profiles_ordered = [profiles[i] for i in profiles_sorted_idx]
    names_ordered = [profile_names[i] for i in profiles_sorted_idx]

    # Calibrate using ALL calibration points from all curves
    if cal_pts:
        n_top = sum(1 for p in cal_pts if p["curve"] == 0)
        n_bot = sum(1 for p in cal_pts if p["curve"] == 1)
        print(f"\nCalibrating with {len(cal_pts)} points "
              f"({n_top} top + {n_bot} bottom curve)...")
        region, rmse = optimize_region(
            profiles_ordered, cal_pts, x_range, region, img.shape[:2])
        print(f"  Optimized region: {region} (RMSE={rmse:.2f}%)")
    else:
        print("\nNo calibration points -- using plot_region as-is.")

    # Number-at-risk data for tail truncation
    nar = config.get("number_at_risk")
    nar_names = list(nar["counts"].keys()) if nar else []

    # Convert all profiles to data coordinates
    curves = []
    for i, (prof, pname) in enumerate(zip(profiles_ordered, names_ordered)):
        points = profile_to_points(prof, region, x_range, y_range)

        # KM curves always start at (0, 100%)
        if points and (points[0][0] > 0.01 or points[0][1] < y_range[1] - 0.5):
            points.insert(0, (x_range[0], y_range[1]))

        change_pts = simplify_to_changes(points, y_tol=config.get("y_tolerance", 1.0))

        # After simplification, if there's a large survival drop near
        # time=0 followed by a time gap (untracked overlap zone), place
        # the drop at the midpoint instead of at time=0.
        if len(change_pts) >= 3:
            p0 = change_pts[0]  # (0, 100)
            p1 = change_pts[1]  # (0, ~91)  — the cliff
            p2 = change_pts[2]  # (3.66, ~89.7) — first real tracked
            if (p0["time"] == 0 and p1["time"] == 0
                    and p0["survival"] - p1["survival"] > 3.0
                    and p2["time"] > 1.0):
                mid_t = round(p2["time"] / 2, 2)
                change_pts[1] = {"time": mid_t, "survival": p1["survival"]}

        # KM survival is monotonically non-increasing.  Remove any
        # upward jumps (caused by censoring tick marks, legend artifacts,
        # or cross-talk from the other curve at the tail).
        mono = [change_pts[0]]
        for p in change_pts[1:]:
            if p["survival"] <= mono[-1]["survival"]:
                mono.append(p)
        change_pts = mono

        # Truncate at the last number-at-risk timepoint where count > 0.
        # Beyond that, pixel data is unreliable (censoring ticks, noise).
        if nar and i < len(nar_names):
            counts = nar["counts"][nar_names[i]]
            last_nonzero_t = 0.0
            for t_idx, c in zip(nar["times"], counts):
                if c > 0:
                    last_nonzero_t = t_idx
            if last_nonzero_t > 0:
                change_pts = [p for p in change_pts
                              if p["time"] <= last_nonzero_t + 1.0]

        # Extend flat tail to x_range max so the digitized curve spans
        # the full plot width even when the tracker loses pixels in the tail.
        x_max = x_range[1]
        if change_pts and change_pts[-1]["time"] < x_max:
            change_pts.append({"time": round(float(x_max), 2),
                               "survival": change_pts[-1]["survival"]})

        name = curve_names[i] if i < len(curve_names) else f"Curve {i+1} ({pname})"
        curves.append({"name": name, "points": change_pts, "n_points": len(change_pts)})

    result = {
        "source_image": os.path.basename(config["image_path"]),
        "image_path": config["image_path"],
        "x_axis": {"label": config.get("x_label", "Time"), "range": x_range},
        "y_axis": {"label": config.get("y_label", "Survival (%)"), "range": y_range},
        "plot_region": region,
        "curves": curves,
    }
    if "number_at_risk" in config:
        result["number_at_risk"] = config["number_at_risk"]

    out = config["output_path"]
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w") as f:
        json.dump(result, f, indent=2)

    print(f"\nSaved: {out}")
    for c in curves:
        first = c["points"][0] if c["points"] else {}
        last = c["points"][-1] if c["points"] else {}
        print(f"  {c['name']}: {c['n_points']} pts, "
              f"({first.get('time', '?')}, {first.get('survival', '?')}) -> "
              f"({last.get('time', '?')}, {last.get('survival', '?')})")

    if "debug_image" in config:
        save_debug_image(img, region, profiles_ordered, names_ordered,
                         config["debug_image"])

    return result


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python digitize_km.py config.json")
        sys.exit(1)
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    digitize_km(cfg)
