#!/usr/bin/env python3
"""Review slides for the 2x2 design space.

Style is lifted from the user's existing SHA256_Review1.pptx so these drop
straight into that deck: same 13.333x7.5in canvas, same rust/charcoal palette,
same Century Schoolbook titles over Calibri body, same margins and geometry.
"""
from pptx import Presentation
from pptx.util import Emu, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

# ---- palette, sampled from Review 1 ----------------------------------------
ACCENT = RGBColor(0xC1, 0x44, 0x0E)   # rust
DARK   = RGBColor(0x2B, 0x33, 0x3C)   # charcoal
MUTED  = RGBColor(0x6B, 0x70, 0x78)   # grey
BANNER = RGBColor(0xFB, 0xED, 0xE4)   # pale peach
CARD_N = RGBColor(0xF2, 0xF3, 0xF0)   # neutral card
CARD_A = RGBColor(0xED, 0xEF, 0xEA)   # alt neutral card
WHITE  = RGBColor(0xFF, 0xFF, 0xFF)

SERIF = "Century Schoolbook"
SANS  = "Calibri"

IN = 914400
def i(x): return Emu(int(x * IN))

# ---- geometry, matching Review 1 -------------------------------------------
CONTENT_L, CONTENT_W = 0.90, 11.50


def deck():
    p = Presentation()
    p.slide_width, p.slide_height = Emu(12192000), Emu(6858000)
    return p


def blank(prs):
    return prs.slides.add_slide(prs.slide_layouts[6])


def rect(slide, x, y, w, h, fill, shape=MSO_SHAPE.RECTANGLE):
    s = slide.shapes.add_shape(shape, i(x), i(y), i(w), i(h))
    s.fill.solid()
    s.fill.fore_color.rgb = fill
    s.line.fill.background()
    s.shadow.inherit = False
    return s


def txt(slide, x, y, w, h, runs, size=14, font=SANS, color=DARK, bold=False,
        align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, space=0):
    """runs: a string, or a list of (text, {overrides}) tuples."""
    tb = slide.shapes.add_textbox(i(x), i(y), i(w), i(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = anchor
    para = tf.paragraphs[0]
    para.alignment = align
    if space:
        para.space_after = Pt(space)
    if isinstance(runs, str):
        runs = [(runs, {})]
    for text, ov in runs:
        r = para.add_run()
        r.text = text
        f = r.font
        f.name = ov.get("font", font)
        f.size = Pt(ov.get("size", size))
        f.bold = ov.get("bold", bold)
        f.color.rgb = ov.get("color", color)
    return tb


def bullets(slide, x, y, w, h, items, size=14, color=MUTED, space=9):
    """items: list of strings, or (bold_lead, rest) tuples."""
    tb = slide.shapes.add_textbox(i(x), i(y), i(w), i(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    for n, item in enumerate(items):
        para = tf.paragraphs[0] if n == 0 else tf.add_paragraph()
        para.space_after = Pt(space)
        parts = [(item, {})] if isinstance(item, str) else item
        for text, ov in parts:
            r = para.add_run()
            r.text = text
            f = r.font
            f.name = ov.get("font", SANS)
            f.size = Pt(ov.get("size", size))
            f.bold = ov.get("bold", False)
            f.color.rgb = ov.get("color", color)
    return tb


def header(slide, title, num):
    rect(slide, 0.60, 0.44, 0.16, 0.16, ACCENT)
    txt(slide, 0.92, 0.28, 10.60, 0.62, title, size=32, font=SERIF,
        color=DARK, bold=True)
    txt(slide, 12.10, 0.34, 0.70, 0.35, num, size=11, color=MUTED, bold=True,
        align=PP_ALIGN.RIGHT)


def banner(slide, text, y=1.10, h=1.15):
    rect(slide, CONTENT_L, y, CONTENT_W, h, BANNER)
    txt(slide, CONTENT_L + 0.35, y + 0.25, CONTENT_W - 0.70, h - 0.45,
        text, size=19, font=SERIF, color=ACCENT, bold=True,
        anchor=MSO_ANCHOR.MIDDLE)


def footnote(slide, y, lead, rest, h=0.75):
    txt(slide, CONTENT_L, y, CONTENT_W, 0.30, lead, size=15, bold=True,
        color=DARK)
    txt(slide, CONTENT_L, y + 0.34, CONTENT_W, h, rest, size=14, color=MUTED)


# =============================================================================
prs = deck()

# ---------------------------------------------------------------- SLIDE 04 --
s = blank(prs)
header(s, "The Design Space", "04")
banner(s, "Unrolling is one lever. Interleaving is a second, independent one. "
          "This project measures both.")

COL_X = [2.80, 7.70]
COL_W = 4.70
ROW_Y = [2.92, 4.54]
ROW_H = 1.50

# column headers
for n, lab in enumerate(["U = 1   one round per stage",
                         "U = 2   two rounds per stage"]):
    txt(s, COL_X[n], 2.50, COL_W, 0.32, lab, size=13, bold=True, color=DARK)

# row labels
for n, (lab, sub) in enumerate([("C = 1", "one message"),
                                ("C = 2", "two messages")]):
    txt(s, CONTENT_L, ROW_Y[n] + 0.42, 1.75, 0.32, lab, size=17, font=SERIF,
        bold=True, color=DARK)
    txt(s, CONTENT_L, ROW_Y[n] + 0.78, 1.75, 0.30, sub, size=12.5, color=MUTED)

cells = [
    (0, 0, "A", "baseline",     "66 cycles / block", "critical path: 1 round",  CARD_N, DARK),
    (1, 0, "B", "unrolled",     "34 cycles / block", "critical path: 2 rounds", CARD_A, DARK),
    (0, 1, "C", "interleaved",  "33 cycles / block", "critical path: 1 round",  BANNER, ACCENT),
    (1, 1, "D", "both levers",  "17 cycles / block", "critical path: 2 rounds", BANNER, ACCENT),
]
for col, row, letter, name, cyc, path, fill, lcol in cells:
    x, y = COL_X[col], ROW_Y[row]
    rect(s, x, y, COL_W, ROW_H, fill)
    txt(s, x + 0.28, y + 0.30, 0.70, 0.75, letter, size=30, font=SERIF,
        bold=True, color=lcol)
    txt(s, x + 1.05, y + 0.26, 3.40, 0.28, name.upper(), size=12.5, bold=True,
        color=lcol)
    txt(s, x + 1.05, y + 0.58, 3.40, 0.38, cyc, size=19, font=SERIF, bold=True,
        color=DARK)
    txt(s, x + 1.05, y + 1.02, 3.40, 0.32, path, size=12.5, color=MUTED)

footnote(s, 6.28,
         "One round module, four configurations",
         "The number of round instances and the placement of registers are the "
         "only variables between them.", h=0.42)
s.notes_slide.notes_text_frame.text = (
    "U is unroll depth, C is interleave depth. C and D hash two independent "
    "messages at once, so their per-block cost is the effective figure: 66 "
    "cycles retiring two blocks is 33 per block. Cycle counts are confirmed "
    "in simulation, not estimated.")

# ---------------------------------------------------------------- SLIDE 05 --
s = blank(prs)
header(s, "Two Levers, Two Bargains", "05")
banner(s, "Moving across the grid and moving down it are not the same trade.")

CW, CH = 5.50, 2.50
CY = 2.60
for n, (x, fill, kicker, head, body, verdict, vcol) in enumerate([
    (0.90, CARD_N, "ACROSS A ROW — UNROLLING",
     "Buys cycles, pays frequency",
     "Two rounds chained combinationally put two five-input adder chains in "
     "series. The critical path doubles, so the clock must slow. Whether the "
     "cycle saving outweighs it is a real question.",
     "May lose.  Break-even at 0.624.", ACCENT),
    (6.90, BANNER, "DOWN A COLUMN — INTERLEAVING",
     "Buys cycles, pays area",
     "A register between the round instances is legal because the two messages "
     "are independent. The critical path is unchanged, so no frequency is "
     "traded. The cost is a second set of registers.",
     "Cannot lose, absent a build error.", ACCENT),
]):
    rect(s, x, CY, CW, CH, fill)
    txt(s, x + 0.35, CY + 0.28, CW - 0.70, 0.28, kicker, size=12.5, bold=True,
        color=ACCENT)
    txt(s, x + 0.35, CY + 0.62, CW - 0.70, 0.36, head, size=20, font=SERIF,
        bold=True, color=DARK)
    txt(s, x + 0.35, CY + 1.08, CW - 0.70, 1.00, body, size=13.5, color=MUTED)
    txt(s, x + 0.35, CY + 2.10, CW - 0.70, 0.28, verdict, size=13.5, bold=True,
        color=vcol)

footnote(s, 5.45, "The prediction",
         "Because the interleave register never touches the combinational path, "
         "the gain down a column should not depend on which column it is: "
         "A→C and B→D should both be close to 2×, whatever unrolling "
         "does. That independence is the claim the measurement tests.", h=0.95)
s.notes_slide.notes_text_frame.text = (
    "0.624 is the system-level break-even: Config B wins only if it keeps more "
    "than 62.4% of Config A's frequency. It was derived from cycle counts and "
    "committed before synthesis. It can still fail, and that remains a valid "
    "reportable outcome.")

# ---------------------------------------------------------------- SLIDE 06 --
s = blank(prs)
header(s, "Novelty and Contribution", "06")
banner(s, "The contribution is a controlled re-test of a published result "
          "that contradicts theory.")

items = [
    ("01", "A re-test of a contradictory result",
     "Suhaili & Julai (2022) report the same 64-to-34-cycle design improving "
     "Fmax, against theory and the classical literature. Their designs were "
     "built separately, so architecture, device and toolchain cannot be told "
     "apart."),
    ("02", "A controlled 2\u00d72 measurement",
     "Four cores, one round module, one script, one constraint set, one "
     "device. It also tests whether the interleave gain stays independent of "
     "unroll depth on real fabric, as C-slow retiming theory predicts."),
    ("03", "A threshold that can still fail",
     "Config B's break-even was fixed before synthesis and may be missed. "
     "Adding C and D gives a positive result without softening that."),
]
Y = 2.55
for n, (num, head, body) in enumerate(items):
    y = Y + n * 1.25
    rect(s, CONTENT_L, y + 0.10, 0.16, 0.16, ACCENT)
    txt(s, CONTENT_L + 0.40, y, 0.60, 0.30, num, size=13, bold=True, color=ACCENT)
    txt(s, CONTENT_L + 1.05, y - 0.04, 9.80, 0.32, head, size=18, font=SERIF,
        bold=True, color=DARK)
    txt(s, CONTENT_L + 1.05, y + 0.36, 9.80, 0.70, body, size=13.5, color=MUTED)

rect(s, CONTENT_L, 6.28, CONTENT_W, 0.80, CARD_N)
txt(s, CONTENT_L + 0.35, 6.46, CONTENT_W - 0.70, 0.52,
    [("No novelty is claimed in unrolling, interleaving or pipelining. ",
      {"bold": True, "color": DARK}),
     ("All three are published, and the independence of the two axes follows "
      "from C-slow retiming theory. What is new is the controlled re-test.",
      {"color": MUTED})],
    size=13.5)
s.notes_slide.notes_text_frame.text = (
    "This slide replaces the Review 1 novelty slide. That one offered "
    "experimental method as the contribution and conceded a negative result "
    "was possible. This one offers a structural claim about the design space "
    "and keeps the falsifiable threshold intact.")

# ---------------------------------------------------------------- SLIDE 07 --
s = blank(prs)
header(s, "What the Literature Says", "07")
banner(s, "A 2022 result contradicts the structural theory. That is the gap.")

CY, CH = 2.55, 1.95
for x, fill, kicker, head, body in [
    (0.90, CARD_N, "SUHAILI & JULAI, 2022  ·  ARRIA II GX",
     "Unrolling improved Fmax",
     "Builds the same unfolding-by-two design, 64 rounds in 34 cycles, and "
     "reports that it surpassed the iterative design on maximum frequency."),
    (6.90, CARD_A, "THE STRUCTURAL ARGUMENT",
     "Fmax must fall",
     "Two adder chains in series cannot be separated by a register without "
     "losing the cycle saving. The critical path doubles, so the clock slows."),
]:
    rect(s, x, CY, 5.50, CH, fill)
    txt(s, x + 0.35, CY + 0.26, 4.80, 0.28, kicker, size=11.5, bold=True,
        color=ACCENT)
    txt(s, x + 0.35, CY + 0.60, 4.80, 0.36, head, size=19, font=SERIF,
        bold=True, color=DARK)
    txt(s, x + 0.35, CY + 1.06, 4.80, 0.85, body, size=13, color=MUTED)

txt(s, CONTENT_L, 4.78, CONTENT_W, 0.30,
    "Why it is still open", size=15, bold=True, color=DARK)
bullets(s, CONTENT_L, 5.15, CONTENT_W, 1.90, [
    [("Their three designs were built separately, ", {"bold": True, "color": DARK}),
     ("so a frequency difference cannot be attributed to unroll depth rather "
      "than to the device or the toolchain.", {})],
    [("Arria II GX is not Zynq-7020. ", {"bold": True, "color": DARK}),
     ("Whether a second adder chain fits the timing budget is a device "
      "question. An Altera answer does not transfer to Xilinx fabric.", {})],
    [("The field is active, not settled. ", {"bold": True, "color": DARK}),
     ("Two 2026 papers place SHA-256 on Zynq-7000, one on the ZedBoard "
      "itself.", {})],
], size=13.5)
s.notes_slide.notes_text_frame.text = (
    "This is the honest answer to 'hasn't this been done'. Yes, and the "
    "published answers disagree with each other and with theory. Our "
    "construction removes the confound: identical round module, identical "
    "constraints, one device.")

# ---------------------------------------------------------------- SLIDE 08 --
s = blank(prs)
header(s, "Verification Status", "08")
banner(s, "69 RTL checks and 10 software checks, all passing.")

stats = [("69", "RTL checks"), ("10", "software checks"),
         ("64", "rounds traced"), ("0", "failures")]
for n, (big, lab) in enumerate(stats):
    x = 0.90 + n * 2.95
    rect(s, x, 2.55, 2.65, 1.20, CARD_N)
    txt(s, x + 0.30, 2.72, 2.05, 0.60, big, size=34, font=SERIF, bold=True,
        color=ACCENT)
    txt(s, x + 0.30, 3.36, 2.05, 0.28, lab, size=12.5, color=MUTED)

txt(s, CONTENT_L, 4.10, CONTENT_W, 0.30, "What is checked", size=15,
    bold=True, color=DARK)
bullets(s, CONTENT_L, 4.47, 5.30, 2.00, [
    [("Logical functions and K ROM ", {"bold": True, "color": DARK}),
     ("against the Python model", {})],
    [("Message schedule ", {"bold": True, "color": DARK}),
     ("W[0..63] at all 64 rounds", {})],
    [("Per-round a..h ", {"bold": True, "color": DARK}),
     ("at all 64 rounds", {})],
    [("NIST vectors ", {"bold": True, "color": DARK}),
     ("including multi-block chaining", {})],
], size=13.5)
bullets(s, 6.90, 4.47, 5.50, 2.00, [
    [("Soak: 12 messages ", {"bold": True, "color": DARK}),
     ("at 55, 56, 63, 64 and 65 bytes — the padding boundaries that break "
      "most designs", {})],
    [("Four-way agreement: ", {"bold": True, "color": DARK}),
     ("A, B and both streams of C and D must produce bit-identical digests", {})],
    [("Cycle counts ", {"bold": True, "color": DARK}),
     ("66, 34, 33 and 17 confirmed in simulation", {})],
], size=13.5)
s.notes_slide.notes_text_frame.text = (
    "The four-way agreement check is the strongest one: it needs no external "
    "reference. The four cores share a round module but differ in control, so "
    "any control-path error breaks the match immediately.")

# ---------------------------------------------------------------- SLIDE 09 --
s = blank(prs)
header(s, "The Measurement", "09")
banner(s, "Four out-of-context builds, one script, one constraint set.")

txt(s, CONTENT_L, 2.50, CONTENT_W, 0.30,
    "Why the timing constraint is deliberately unreachable", size=15,
    bold=True, color=DARK)
txt(s, CONTENT_L, 2.87, CONTENT_W, 0.95,
    "Vivado stops optimising once timing is met, so at 100 MHz all four would "
    "meet it with slack and the result would record where the tool chose to "
    "stop. The target is set at 250 MHz instead, pushing every configuration "
    "to its own limit under the same pressure. Negative slack is the "
    "measurement, not a failure.", size=13.5, color=MUTED)

rows = [
    ("Config B clears 0.624", "Unrolling pays. Report the gain and the ratio.",
     CARD_N),
    ("Config B misses 0.624", "A net loss on this device — the stated "
     "falsifiable outcome, and a valid finding.", CARD_A),
    ("A→C and B→D agree", "The two axes are independent. The orthogonality "
     "claim is confirmed.", BANNER),
]
Y = 3.98
for n, (cond, meaning, fill) in enumerate(rows):
    y = Y + n * 0.88
    rect(s, CONTENT_L, y, CONTENT_W, 0.76, fill)
    txt(s, CONTENT_L + 0.30, y + 0.24, 3.30, 0.30, cond, size=13.5, bold=True,
        color=DARK)
    txt(s, CONTENT_L + 3.90, y + 0.24, 7.30, 0.50, meaning, size=13.5,
        color=MUTED)

txt(s, CONTENT_L, 6.78, CONTENT_W, 0.32,
    [("Every outcome is reportable. ", {"bold": True, "color": ACCENT}),
     ("The project does not depend on any one of them landing a particular way.",
      {"color": MUTED})], size=13.5)
s.notes_slide.notes_text_frame.text = (
    "Throughput-per-LUT is the headline metric because the four configurations "
    "differ in area. State the caveat out loud: C and D need independent "
    "messages, and single-message latency is unchanged.")

out = "/Users/amritha/Downloads/files 2/sha_project/Review_SHA256_2x2.pptx"
prs.save(out)
print("wrote", out, "-", len(prs.slides.__iter__.__self__._sldIdLst), "slides")
