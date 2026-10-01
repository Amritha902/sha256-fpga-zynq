#!/usr/bin/env python3
"""make_demo_video.py — render the verification demo video.

Every terminal segment is the captured output of the real command, run in
the project's cloud environment (scripts/capture_demo.sh writes the
captures). Time is compressed: output is revealed line by line at a fixed
rate, not at the tools' real speed. The waveform is plotted from the VCD the
RTL testbench dumps.

    python3 scripts/make_demo_video.py <capture_dir> <vcd> <out.mp4>
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1280, 720, 10
BG, INK, MUTED, RUST, GREEN, PROMPT = (30, 35, 41), (232, 234, 237), (150, 156, 164), (226, 112, 64), (110, 200, 140), (120, 190, 255)
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
SANSB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SERIFB = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
f_mono = ImageFont.truetype(MONO, 17)
LH, MAXCOL, ROWS = 23, 104, 26


class Video:
    def __init__(self, path):
        self.p = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                                   "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264",
                                   "-pix_fmt", "yuv420p", "-r", "30", "-crf", "20", str(path)], stdin=subprocess.PIPE)
        self.frames = 0

    def put(self, img, n=1):
        b = img.tobytes()
        for _ in range(n):
            self.p.stdin.write(b)
        self.frames += n

    def close(self):
        self.p.stdin.close()
        self.p.wait()


def card(v, title, sub="", foot="", secs=3.0, dark=True):
    im = Image.new("RGB", (W, H), BG if dark else (255, 255, 255))
    d = ImageDraw.Draw(im)
    d.text((80, 250), title, font=ImageFont.truetype(SERIFB, 46), fill=INK if dark else BG)
    if sub:
        d.text((80, 330), sub, font=ImageFont.truetype(SANS, 26), fill=RUST)
    if foot:
        y = 420
        for line in foot.split("\n"):
            d.text((80, y), line, font=ImageFont.truetype(SANS, 20), fill=MUTED)
            y += 32
    v.put(im, int(secs * FPS))


def section(v, num, title, tool, secs=2.2):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    d.ellipse((80, 270, 160, 350), fill=RUST)
    d.text((120, 310), str(num), font=ImageFont.truetype(SANSB, 38), fill=(255, 255, 255), anchor="mm")
    d.text((190, 268), title, font=ImageFont.truetype(SERIFB, 40), fill=INK)
    d.text((192, 325), tool, font=ImageFont.truetype(SANS, 22), fill=MUTED)
    v.put(im, int(secs * FPS))


def colour(line):
    u = line.upper()
    if "FAIL" in u and "FAILURES : 0" not in u and "0 FAIL" not in u:
        return RUST
    if any(k in u for k in ("PASS", "PROVEN", "SUCCESS", "FAILURES : 0", "ALL ", "OK", "CLEARS BOTH")):
        return GREEN
    if "MAX FREQUENCY" in u or "VERDICT" in u or "RATIO" in u:
        return RUST
    return INK


def wrap(lines):
    out = []
    for ln in lines:
        ln = ln.rstrip("\n").replace("\t", "    ")
        while len(ln) > MAXCOL:
            out.append(ln[:MAXCOL])
            ln = "  " + ln[MAXCOL:]
        out.append(ln)
    return out


def terminal(v, header, text, lines_per_frame=2, hold=3.0, max_lines=None):
    lines = text.splitlines()
    cmd, body = lines[0], wrap(lines[1:])
    if max_lines:
        body = body[:max_lines]
    head_f = ImageFont.truetype(SANS, 16)

    def frame(cmd_shown, shown):
        im = Image.new("RGB", (W, H), BG)
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, W, 34), fill=(44, 50, 58))
        for i, c in enumerate(((236, 95, 87), (245, 190, 79), (98, 196, 98))):
            d.ellipse((14 + i * 22, 11, 26 + i * 22, 23), fill=c)
        d.text((90, 8), header, font=head_f, fill=MUTED)
        rows = [("$ ", cmd_shown)] + [("", s) for s in shown]
        rows = rows[-ROWS:]
        y = 48
        for pre, s in rows:
            if pre:
                d.text((20, y), pre, font=f_mono, fill=PROMPT)
                d.text((20 + f_mono.getlength(pre), y), s, font=f_mono, fill=INK)
            else:
                d.text((20, y), s, font=f_mono, fill=colour(s))
            y += LH
        return im

    c = cmd[2:] if cmd.startswith("$ ") else cmd
    c_disp = c if len(c) <= MAXCOL - 2 else c[:MAXCOL - 5] + "..."
    step = max(1, len(c_disp) // 20)
    for i in range(0, len(c_disp) + 1, step):
        v.put(frame(c_disp[:i] + "_", []))
    v.put(frame(c_disp, []), 4)
    for k in range(0, len(body) + 1, lines_per_frame):
        v.put(frame(c_disp, body[:k]))
    v.put(frame(c_disp, body), int(hold * FPS))


def parse_vcd(path, wanted):
    ids, vals, cur_t, scope = {}, {}, 0, []
    with open(path) as fh:
        for line in fh:
            t = line.split()
            if not t:
                continue
            if t[0] == "$scope":
                scope.append(t[2])
            elif t[0] == "$upscope":
                scope.pop()
            elif t[0] == "$var":
                name = ".".join(scope[1:] + [t[4]])
                if name in wanted:
                    ids.setdefault(t[3], []).append(name)
                    vals[name] = []
            elif t[0].startswith("#"):
                cur_t = int(t[0][1:])
            elif t[0][0] in "01xz" and len(t) == 1 and t[0][1:] in ids:
                for n in ids[t[0][1:]]:
                    vals[n].append((cur_t, t[0][0]))
            elif t[0][0] == "b" and len(t) == 2 and t[1] in ids:
                for n in ids[t[1]]:
                    vals[n].append((cur_t, t[0][1:]))
    return vals


def waveform(v, vcd, secs=7.0):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    sigs = [("clk", "clk"), ("a_bv", "block_valid"), ("u_iter.state", "state"), ("u_iter.t", "round t"),
            ("a_dv", "digest_valid"), ("u_iter.h0", "H0")]
    vals = parse_vcd(vcd, {s for s, _ in sigs})
    ups = [t for t, x in vals.get("a_bv", []) if x == "1"]
    t0 = ups[0] - 30000 if ups else 0                   # first block: "abc"
    t1 = t0 + 700000 + 60000
    fig, axes = plt.subplots(len(sigs), 1, figsize=(12.8, 7.2), dpi=100, sharex=True)
    fig.patch.set_facecolor("#1e2329")
    for ax, (s, label) in zip(axes, sigs):
        ax.set_facecolor("#1e2329")
        ax.set_yticks([])
        for sp in ax.spines.values():
            sp.set_visible(False)
        ax.text(-0.01, 0.5, label, transform=ax.transAxes, ha="right", va="center", color="#e8eaed", fontsize=11)
        ev = vals.get(s, [])
        pts = [(t, x) for t, x in ev if t <= t1]
        last = None
        for t, x in pts:
            if t <= t0:
                last = (t0, x)
        seq = ([last] if last else []) + [(t, x) for t, x in pts if t > t0]
        if s in ("clk", "a_bv", "a_dv"):
            xs, ys = [], []
            for i, (t, x) in enumerate(seq):
                tn = seq[i + 1][0] if i + 1 < len(seq) else t1
                y = 1 if x == "1" else 0
                xs += [t / 1000, tn / 1000]
                ys += [y, y]
            ax.plot(xs, ys, color="#e27040" if s != "clk" else "#7a8290", lw=1.4 if s != "clk" else 0.6)
            ax.set_ylim(-0.3, 1.3)
        else:
            for i, (t, x) in enumerate(seq):
                tn = seq[i + 1][0] if i + 1 < len(seq) else t1
                ax.fill_between([t / 1000, tn / 1000], 0.15, 0.85, color="#2f6f4e", alpha=0.6)
                if (tn - t) > 25000:
                    try:
                        txt = format(int(x, 2), "x") if s == "u_iter.h0" else str(int(x, 2))
                    except ValueError:
                        txt = x
                    ax.text((t + tn) / 2000, 0.5, txt, ha="center", va="center", color="#e8eaed", fontsize=9)
            ax.set_ylim(0, 1)
    axes[-1].set_xlim(t0 / 1000, t1 / 1000)
    axes[-1].tick_params(colors="#9aa0a6")
    axes[-1].set_xlabel("time (ns) — Config A hashing \"abc\", 66 cycles from load to digest", color="#9aa0a6")
    fig.suptitle("RTL waveform (Icarus Verilog VCD)", color="#e8eaed", fontsize=14, x=0.08, ha="left")
    fig.subplots_adjust(left=0.12, right=0.98, top=0.92, bottom=0.08, hspace=0.25)
    fig.canvas.draw()
    im = Image.frombuffer("RGBA", fig.canvas.get_width_height(), fig.canvas.buffer_rgba()).convert("RGB").resize((W, H))
    plt.close(fig)
    v.put(im, int(secs * FPS))


def main():
    cap, vcd, out = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    r = lambda n: (cap / f"{n}.txt").read_text()
    v = Video(out)
    card(v, "SHA-256 Accelerator on Zynq-7000", "Verification demonstration",
         "Amritha S · 23BEC1368 · ZedBoard XC7Z020-1CLG484\nAll output captured from the tools, run in the project's cloud environment\nTime-compressed", 5)
    section(v, 1, "RTL simulation", "Icarus Verilog · 129 checks across A, B, B′, C, D")
    terminal(v, "RTL verification — make all sched", r("01_rtl"), 2, 4)
    waveform(v, vcd)
    section(v, 2, "Formal equivalence", "Yosys SAT and induction · B′ ≡ B")
    terminal(v, "Formal proof — make formal", r("02_formal"), 1, 4)
    section(v, 3, "Gate-level simulation", "Yosys netlist (LUT6 · CARRY4 · FDCE) + Xilinx cell models")
    terminal(v, "Post-synthesis simulation — openflow/gatesim.sh", r("03_gatesim"), 1, 4)
    section(v, 4, "Place and route on XC7Z020", "Yosys + nextpnr-xilinx + Project X-Ray · Config B, seed 1")
    terminal(v, "Place and route — nextpnr-xilinx", r("04_pnr"), 1, 4)
    section(v, 5, "Measured results", "Median of 5 seeds per configuration")
    terminal(v, "2×2 comparison — scripts/compare_configs.py", r("05_compare"), 3, 6)
    section(v, 6, "Transistor-level check", "ngspice · 180 nm · Σ1 + N chained adders")
    terminal(v, "ngspice — spice/gen_round_delay.py", r("06_spice"), 1, 4)
    section(v, 7, "Virtual board", "Verilator model of sha256_top + unmodified bare-metal program")
    terminal(v, "Board program against the RTL — cosim/run_cosim.sh", r("07_cosim"), 2, 4)
    terminal(v, "UART transcript, Config C", r("07b_uart"), 2, 5)
    section(v, 8, "Cortex-A9 build", "arm-none-eabi-gcc · -Wall -Wextra -Werror")
    terminal(v, "Cross-compilation", r("08_arm"), 1, 3)
    card(v, "Results", "B / A = 0.673 · C / A = 0.999 · B′ ≡ B",
         "Unrolling clears both pre-registered thresholds on XC7Z020\nSynthesis builds the T1 adder tree; RTL operand order does not change the outcome\n"
         "129 RTL · 21 software · 67 gate-level checks · 2 proofs · 4 / 4 configs on the virtual board\n"
         "Patent assessment: not patentable — prior art for every claim\nNext: Vivado 2022.2 OOC Fmax and on-board run (board/run_zedboard.sh)", 9)
    v.close()
    print(f"{out}: {v.frames / FPS:.0f} s")


if __name__ == "__main__":
    main()
