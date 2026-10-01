// build_results_deck.js — Review 3 deck: measured results, verification,
// toolchain, patent assessment. Every number below comes from a committed
// report (reports_open/, reports_cosim/, reports_gatesim/, formal/,
// reports_ooc/round_path_delay.csv).
//
//   NODE_PATH=<dir with pptxgenjs> node scripts/build_results_deck.js
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_16x9";               // 10 x 5.625 in
pres.author = "Amritha S (23BEC1368)";
pres.title = "SHA-256 Accelerator on Zynq-7000 — Results";

const C = {
  ink: "2B333C", rust: "C1440E", muted: "6B7078", peach: "FBEDE4",
  card: "F2F3F0", line: "D5D8D2", white: "FFFFFF", green: "2E7D4F",
};
const HF = "Cambria", BF = "Calibri";

function title(s, t, sub) {
  s.background = { color: C.white };
  s.addText(t, { x: 0.5, y: 0.3, w: 9, h: 0.6, fontFace: HF, fontSize: 28, bold: true, color: C.ink, margin: 0, isTextBox: true });
  if (sub) s.addText(sub, { x: 0.5, y: 0.88, w: 9, h: 0.35, fontFace: BF, fontSize: 14, color: C.rust, margin: 0, isTextBox: true });
}
function foot(s, n) {
  s.addText(`${n}`, { x: 9.2, y: 5.25, w: 0.4, h: 0.25, fontFace: BF, fontSize: 9, color: C.muted, align: "right", margin: 0, isTextBox: true });
}
function stat(s, x, y, w, big, label, color, fs) {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h: 1.15, fill: { color: C.card }, rectRadius: 0.08, line: { color: C.card } });
  s.addText(big, { x: x + 0.15, y: y + 0.1, w: w - 0.3, h: 0.6, fontFace: HF, fontSize: fs || 30, bold: true, color: color || C.ink, margin: 0, isTextBox: true });
  s.addText(label, { x: x + 0.15, y: y + 0.7, w: w - 0.3, h: 0.35, fontFace: BF, fontSize: 11, color: C.muted, margin: 0, isTextBox: true });
}
const axis = { catAxisLabelColor: C.muted, valAxisLabelColor: C.muted, catAxisLabelFontFace: BF, valAxisLabelFontFace: BF,
  valGridLine: { color: "E6E8E4", size: 0.5 }, catGridLine: { style: "none" } };

let n = 1;

// 1 — title --------------------------------------------------------------
{
  const s = pres.addSlide();
  s.background = { color: C.ink };
  s.addText("SHA-256 Accelerator on Zynq-7000", { x: 0.6, y: 1.3, w: 8.8, h: 0.8, fontFace: HF, fontSize: 30, bold: true, color: C.white, margin: 0, isTextBox: true });
  s.addText("Measured results · verification · patent assessment", { x: 0.6, y: 2.25, w: 8.8, h: 0.5, fontFace: BF, fontSize: 18, color: "F3B08F", margin: 0, isTextBox: true });
  s.addText("Amritha S  ·  23BEC1368  ·  ZedBoard XC7Z020-1CLG484  ·  Review 3, October 2026",
    { x: 0.6, y: 4.6, w: 8.8, h: 0.4, fontFace: BF, fontSize: 12, color: "B9BEC4", margin: 0, isTextBox: true });
  s.addNotes("Review 3. Results of the controlled 2x2 measurement, the verification stack, the toolchain, and the patent assessment.");
  n++;
}

// 2 — design space ---------------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Design Space", "One round module · five configurations · one constraint set");
  const cells = [
    ["A", "Iterative", "66 cycles / block", 0, 0, C.card],
    ["B", "2× unrolled", "34 cycles / block", 1, 0, C.card],
    ["C", "2-message interleaved", "33 cycles / block (eff.)", 0, 1, C.peach],
    ["D", "Unrolled + interleaved", "17 cycles / block (eff.)", 1, 1, C.peach],
  ];
  const X0 = 1.9, Y0 = 1.75, W = 3.3, H = 1.35, G = 0.25;
  s.addText("U = 1", { x: X0, y: 1.4, w: W, h: 0.3, fontFace: BF, fontSize: 12, bold: true, color: C.muted, margin: 0, isTextBox: true });
  s.addText("U = 2", { x: X0 + W + G, y: 1.4, w: W, h: 0.3, fontFace: BF, fontSize: 12, bold: true, color: C.muted, margin: 0, isTextBox: true });
  s.addText("C = 1", { x: 0.5, y: Y0 + 0.5, w: 1.2, h: 0.3, fontFace: BF, fontSize: 12, bold: true, color: C.muted, margin: 0, isTextBox: true });
  s.addText("C = 2", { x: 0.5, y: Y0 + H + G + 0.5, w: 1.2, h: 0.3, fontFace: BF, fontSize: 12, bold: true, color: C.muted, margin: 0, isTextBox: true });
  for (const [k, name, cyc, cx, cy, fill] of cells) {
    const x = X0 + cx * (W + G), y = Y0 + cy * (H + G);
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: W, h: H, fill: { color: fill }, rectRadius: 0.08, line: { color: fill } });
    s.addText(k, { x: x + 0.2, y: y + 0.2, w: 0.7, h: 0.9, fontFace: HF, fontSize: 40, bold: true, color: k === "A" || k === "B" ? C.ink : C.rust, margin: 0, isTextBox: true });
    s.addText([{ text: name, options: { bold: true, breakLine: true } }, { text: cyc, options: { color: C.muted } }],
      { x: x + 1.0, y: y + 0.3, w: W - 1.1, h: 0.8, fontFace: BF, fontSize: 14, color: C.ink, margin: 0, isTextBox: true });
  }
  s.addText("B′ = B with h + K + W summed in parallel with the first round (operand-scheduled)",
    { x: 0.5, y: 4.85, w: 9, h: 0.3, fontFace: BF, fontSize: 11, italic: true, color: C.muted, margin: 0, isTextBox: true });
  foot(s, n++);
}

// 3 — Fmax ------------------------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Maximum Frequency on XC7Z020", "Post-route · median of 5 placement seeds · Yosys + nextpnr-xilinx");
  s.addChart(pres.charts.BAR, [{ name: "Fmax (MHz)", labels: ["A", "B", "B′", "C", "D"], values: [68.24, 45.92, 44.41, 68.20, 40.18] }], {
    x: 0.4, y: 1.35, w: 5.6, h: 3.9, barDir: "col", chartColors: [C.ink], showValue: true, dataLabelPosition: "outEnd",
    dataLabelFontSize: 11, dataLabelColor: C.ink, dataLabelFormatCode: "0.0", showLegend: false,
    showTitle: true, title: "Fmax (MHz)", titleFontSize: 12, titleColor: C.muted, valAxisMinVal: 0, valAxisMaxVal: 80, ...axis,
  });
  stat(s, 6.3, 1.45, 3.2, "0.673", "Fmax(B) / Fmax(A)", C.rust);
  stat(s, 6.3, 2.75, 3.2, "0.999", "Fmax(C) / Fmax(A)", C.ink);
  stat(s, 6.3, 4.05, 3.2, "0.651", "Fmax(B′) / Fmax(A)", C.ink);
  s.addNotes("Absolute MHz come from the open-source timing model and are conservative; the ratios are the measurement. Seed ranges: A 64.5-70.5, B 44.5-48.2, B' 41.5-45.7, C 65.8-70.6, D 39.6-46.4.");
  foot(s, n++);
}

// 4 — thresholds -------------------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Pre-Registered Thresholds", "Fixed at Review 1 · not moved");
  const L = 0.8, R = 9.2, lo = 0.48, hi = 0.70, Y = 2.95;
  const px = (v) => L + ((v - lo) / (hi - lo)) * (R - L);
  s.addShape(pres.shapes.LINE, { x: L, y: Y, w: R - L, h: 0, line: { color: C.ink, width: 1.5 } });
  // pass region
  s.addShape(pres.shapes.RECTANGLE, { x: px(0.624), y: Y - 0.35, w: R - px(0.624), h: 0.7, fill: { color: "E3F1E8" }, line: { color: "E3F1E8" } });
  s.addText("clears both", { x: R - 1.2, y: Y + 0.05, w: 1.1, h: 0.25, align: "right", fontFace: BF, fontSize: 11, color: C.green, margin: 0, isTextBox: true });
  // [value, label, colour, row]: rows -2/-1 above the axis, 1/2 below
  const marks = [
    [0.515, "0.515  core break-even", C.ink, -1], [0.624, "0.624  system break-even", C.ink, -1],
    [0.680, "0.680  ngspice, scheduled", C.muted, -2], [0.500, "0.500  ngspice, serial chain", C.muted, 1],
    [0.651, "0.651  B′ measured", C.rust, 1], [0.673, "0.673  B measured", C.rust, 2],
  ];
  for (const [v, label, col, row] of marks) {
    const x = px(v);
    const yl = row < 0 ? Y - 0.3 - 0.45 * -row : Y + 0.3 + 0.45 * (row - 1);
    s.addShape(pres.shapes.LINE, { x, y: Math.min(Y, yl + 0.25), w: 0, h: Math.abs(yl + 0.12 - Y) + 0.15, line: { color: col, width: v === 0.673 ? 2.5 : 1 } });
    const right = x > 6.5;
    s.addText(label, { x: right ? x - 2.45 : x + 0.05, y: yl, w: 2.4, h: 0.28, fontFace: BF, fontSize: 11,
      bold: col === C.rust, color: col, align: right ? "right" : "left", margin: 0, isTextBox: true });
  }
  s.addText([{ text: "Unrolling is a net throughput gain on this device: ", options: {} },
             { text: "1.31× core, 1.08× system.", options: { bold: true } }],
    { x: 0.5, y: 4.6, w: 9, h: 0.4, fontFace: BF, fontSize: 15, color: C.ink, margin: 0, isTextBox: true });
  s.addNotes("The pre-registered prediction was a net loss (ratio below 0.515). The measurement falsifies it on this flow; the thresholds themselves were not changed.");
  foot(s, n++);
}

// 5 — mechanism ---------------------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Mechanism", "Critical-path composition, post-route (seed 3)");
  s.addChart(pres.charts.BAR, [
    { name: "Logic (ns)", labels: ["A", "B"], values: [3.7, 4.8] },
    { name: "Routing (ns)", labels: ["A", "B"], values: [10.9, 17.0] },
  ], { x: 0.4, y: 1.35, w: 5.0, h: 3.9, barDir: "bar", barGrouping: "stacked", chartColors: [C.rust, "8A9099"],
       showValue: true, dataLabelPosition: "ctr", dataLabelFontSize: 11, dataLabelColor: C.white, dataLabelFormatCode: "0.0",
       showLegend: true, legendPos: "b", legendFontSize: 11, legendColor: C.muted, ...axis });
  const rows = [
    ["Carry-chain stages on path", "A 10 · B 9"],
    ["Logic delay, B vs A", "+30 %, not +100 %"],
    ["Synthesis of T1", "adder tree, not serial chain"],
    ["Hand-scheduled RTL (B′)", "no gain · B′ ≡ B proven"],
  ];
  rows.forEach(([k, v], i) => {
    const y = 1.5 + i * 0.9;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 5.7, y, w: 3.8, h: 0.75, fill: { color: i === 3 ? C.peach : C.card }, rectRadius: 0.06, line: { color: i === 3 ? C.peach : C.card } });
    s.addText([{ text: k, options: { color: C.muted, fontSize: 11, breakLine: true } }, { text: v, options: { bold: true, fontSize: 14 } }],
      { x: 5.85, y: y + 0.08, w: 3.5, h: 0.6, fontFace: BF, color: C.ink, margin: 0, isTextBox: true });
  });
  s.addNotes("The outcome of unrolling is decided by how synthesis structures the T1 adder, not by unroll depth and not by the operand order written in RTL.");
  foot(s, n++);
}

// 6 — transistor level -----------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Transistor-Level Check", "ngspice · Σ1 + N chained 32-bit adders · 180 nm LEVEL-1");
  const nAdd = ["1", "2", "3", "5", "7", "10"];
  s.addChart(pres.charts.LINE, [
    { name: "Simulated", labels: nAdd, values: [0.5506, 0.8461, 1.0890, 1.8387, 2.4562, 3.3595] },
    { name: "Fit 0.2110 + 0.3169 N", labels: nAdd, values: [1, 2, 3, 5, 7, 10].map((k) => +(0.2110 + 0.3169 * k).toFixed(4)) },
  ], { x: 0.4, y: 1.35, w: 5.8, h: 3.9, chartColors: [C.rust, "8A9099"], lineSize: 2, lineDataSymbol: "circle", lineDataSymbolSize: 7,
       showLegend: true, legendPos: "b", legendFontSize: 11, legendColor: C.muted,
       showValAxisTitle: true, valAxisTitle: "delay (ns)", valAxisTitleFontSize: 11, valAxisTitleColor: C.muted,
       showCatAxisTitle: true, catAxisTitle: "adders in series", catAxisTitleFontSize: 11, catAxisTitleColor: C.muted, ...axis });
  stat(s, 6.5, 1.45, 3.0, "R² = 0.998", "delay linear in chain depth");
  stat(s, 6.5, 2.75, 3.0, "0.500 → 0.680", "B / A: serial vs scheduled", C.ink, 22);
  stat(s, 6.5, 4.05, 3.0, "≤ 0.06 %", "re-run deviation, 1 Oct 2026");
  foot(s, n++);
}

// 7 — throughput ----------------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Throughput and Area", "Core level at measured Fmax · system level with measured AXI cycles");
  s.addChart(pres.charts.BAR, [
    { name: "Core (Mbit/s)", labels: ["A", "B", "C", "D"], values: [529.4, 691.5, 1058.1, 1210.1] },
    { name: "System (Mbit/s)", labels: ["A", "B", "C", "D"], values: [411.0, 443.6, 684.7, 587.8] },
  ], { x: 0.4, y: 1.35, w: 5.6, h: 3.9, barDir: "col", barGrouping: "clustered", chartColors: [C.ink, C.rust],
       showValue: true, dataLabelPosition: "outEnd", dataLabelFontSize: 10, dataLabelColor: C.ink, dataLabelFormatCode: "0",
       showLegend: true, legendPos: "b", legendFontSize: 11, legendColor: C.muted, valAxisMaxVal: 1400, ...axis });
  s.addTable([
    [{ text: "", options: {} }, { text: "LUT", options: { bold: true } }, { text: "FF", options: { bold: true } }, { text: "Mb/s/LUT", options: { bold: true } }],
    ["A", "1921", "1035", "0.276"], ["B", "2298", "1035", { text: "0.301", options: { bold: true, color: C.rust } }],
    ["C", "3611", "2059", "0.293"], ["D", "4486", "2059", "0.270"],
  ], { x: 6.3, y: 1.5, w: 3.2, colW: [0.5, 0.8, 0.8, 1.1], fontFace: BF, fontSize: 12, color: C.ink,
       border: { type: "solid", pt: 0.5, color: C.line }, rowH: 0.36 });
  s.addText("0 DSP · 0 BRAM in every configuration", { x: 6.3, y: 3.5, w: 3.2, h: 0.3, fontFace: BF, fontSize: 11, color: C.muted, margin: 0, isTextBox: true });
  s.addText([{ text: "Highest throughput: D, 2.29× A", options: { breakLine: true } }, { text: "Best per LUT: B" }],
    { x: 6.3, y: 4.1, w: 3.3, h: 0.7, fontFace: BF, fontSize: 12, bold: true, color: C.ink, margin: 0, isTextBox: true });
  foot(s, n++);
}

// 8 — verification ----------------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Verification", "Every layer runs in one command · all passing");
  const items = [
    ["129", "RTL checks", "Icarus Verilog"], ["21", "software checks", "gcc"],
    ["67", "gate-level checks", "Yosys netlist + Icarus"], ["2", "formal proofs, B′ ≡ B", "Yosys SAT + induction"],
    ["4 / 4", "configs on virtual board", "Verilator + unmodified main.c"], ["0", "A9 build warnings", "arm-none-eabi-gcc -Werror"],
  ];
  items.forEach(([big, lab, tool], i) => {
    const x = 0.5 + (i % 3) * 3.05, y = 1.45 + Math.floor(i / 3) * 1.85;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 2.85, h: 1.6, fill: { color: C.card }, rectRadius: 0.08, line: { color: C.card } });
    s.addText(big, { x: x + 0.2, y: y + 0.12, w: 2.5, h: 0.65, fontFace: HF, fontSize: 32, bold: true, color: C.rust, margin: 0, isTextBox: true });
    s.addText([{ text: lab, options: { bold: true, breakLine: true } }, { text: tool, options: { color: C.muted, fontSize: 11 } }],
      { x: x + 0.2, y: y + 0.8, w: 2.5, h: 0.7, fontFace: BF, fontSize: 13, color: C.ink, margin: 0, isTextBox: true });
  });
  s.addNotes("RTL: 103 checks for A-D plus 26 for B'. Gate-level: synthesised netlists of A, B, B', C, D under the unchanged RTL testbenches with Xilinx cell models. Formal: one round over all inputs, and the whole core over every state (4599 equivalence points). Virtual board: the bare-metal program runs against a Verilator model with real AXI4-Lite and AXI4-Stream transactions.");
  foot(s, n++);
}

// 9 — defects found ---------------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Defects Identified and Corrected", "Found by gate-level simulation and the virtual board");
  const rows = [
    ["Driver", "Single-message hash stalled on dual-stream cores (C, D)", "Lone message issued as a pair; one slot unused"],
    ["Testbench", "Stimulus applied at the clock edge (race)", "Drive and sample 1 ns after the edge; 66 / 34 cycles confirmed"],
    ["Firmware text", "112-byte NIST vector labelled 3 blocks", "Corrected to 2 blocks"],
  ];
  s.addTable([
    [{ text: "Area", options: { bold: true, color: C.white, fill: { color: C.ink } } },
     { text: "Defect", options: { bold: true, color: C.white, fill: { color: C.ink } } },
     { text: "Correction", options: { bold: true, color: C.white, fill: { color: C.ink } } }],
    ...rows,
  ], { x: 0.5, y: 1.5, w: 9, colW: [1.5, 3.9, 3.6], fontFace: BF, fontSize: 13, color: C.ink, valign: "middle",
       border: { type: "solid", pt: 0.5, color: C.line }, rowH: 0.75, fill: { color: C.white } });
  s.addText("None of the three was visible to the original 103 RTL checks.", { x: 0.5, y: 4.75, w: 9, h: 0.35, fontFace: BF, fontSize: 13, italic: true, color: C.muted, margin: 0, isTextBox: true });
  foot(s, n++);
}

// 10 — toolchain -------------------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Toolchain", "Open-source verification flow · vendor flow for the board");
  const left = [
    ["Icarus Verilog 12", "RTL and gate-level simulation"], ["Verilator 5.020", "virtual board (RTL + firmware)"],
    ["Yosys 0.69", "synthesis to LUT6 / CARRY4 · formal equivalence"], ["nextpnr-xilinx + Project X-Ray", "place, route, timing on XC7Z020"],
    ["ngspice 42", "transistor-level delay"], ["arm-none-eabi-gcc 13.2", "Cortex-A9 cross-compilation"],
  ];
  const right = [
    ["AMD Vivado 2022.2", "block design · bitstream · OOC Fmax"], ["AMD Vitis 2022.2 (XSCT)", "platform · application · JTAG"],
    ["ZedBoard XC7Z020-1CLG484", "target hardware"],
  ];
  s.addText("Run in this project's cloud environment", { x: 0.5, y: 1.35, w: 5.2, h: 0.3, fontFace: BF, fontSize: 12, bold: true, color: C.rust, margin: 0, isTextBox: true });
  left.forEach(([t, d], i) => {
    s.addText([{ text: t, options: { bold: true, breakLine: true } }, { text: d, options: { color: C.muted, fontSize: 11 } }],
      { x: 0.5, y: 1.75 + i * 0.58, w: 5.2, h: 0.55, fontFace: BF, fontSize: 13, color: C.ink, margin: 0, isTextBox: true });
  });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 6.0, y: 1.3, w: 3.5, h: 3.75, fill: { color: C.peach }, rectRadius: 0.08, line: { color: C.peach } });
  s.addText("Board flow (scripts ready)", { x: 6.2, y: 1.45, w: 3.1, h: 0.3, fontFace: BF, fontSize: 12, bold: true, color: C.rust, margin: 0, isTextBox: true });
  right.forEach(([t, d], i) => {
    s.addText([{ text: t, options: { bold: true, breakLine: true } }, { text: d, options: { color: C.muted, fontSize: 11 } }],
      { x: 6.2, y: 1.9 + i * 0.75, w: 3.1, h: 0.65, fontFace: BF, fontSize: 13, color: C.ink, margin: 0, isTextBox: true });
  });
  s.addText("board/run_zedboard.sh A", { x: 6.2, y: 4.35, w: 3.1, h: 0.35, fontFace: "Courier New", fontSize: 12, color: C.ink, margin: 0, isTextBox: true });
  foot(s, n++);
}

// 11 — board flow ------------------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Hardware Realisation — ZedBoard", "Vivado → Vitis → JTAG → UART");
  const steps = [
    ["1", "Vivado", "PS7 + AXI DMA + accelerator\nbitstream · XSA"], ["2", "Vitis", "standalone platform\nsha256_app.elf"],
    ["3", "JTAG", "fpga · ps7_init\ndownload · run"], ["4", "UART", "115200 8N1\nconformance report"],
  ];
  steps.forEach(([k, t, d], i) => {
    const x = 0.5 + i * 2.3;
    s.addShape(pres.shapes.OVAL, { x: x + 0.7, y: 1.5, w: 0.6, h: 0.6, fill: { color: C.rust }, line: { color: C.rust } });
    s.addText(k, { x: x + 0.7, y: 1.5, w: 0.6, h: 0.6, fontFace: HF, fontSize: 18, bold: true, color: C.white, align: "center", valign: "middle", margin: 0, isTextBox: true });
    s.addText(t, { x, y: 2.25, w: 2.0, h: 0.4, fontFace: HF, fontSize: 18, bold: true, color: C.ink, align: "center", margin: 0, isTextBox: true });
    s.addText(d, { x, y: 2.7, w: 2.0, h: 0.7, fontFace: BF, fontSize: 12, color: C.muted, align: "center", margin: 0, isTextBox: true });
    if (i < 3) s.addShape(pres.shapes.LINE, { x: x + 1.45, y: 1.8, w: 1.4, h: 0, line: { color: C.line, width: 1.5, endArrowType: "triangle" } });
  });
  s.addTable([
    [{ text: "Item", options: { bold: true } }, { text: "Status", options: { bold: true } }],
    ["Vivado system build, Vitis build, JTAG run scripts", { text: "ready", options: { color: C.green, bold: true } }],
    ["Expected UART transcript (virtual board, A–D)", { text: "recorded", options: { color: C.green, bold: true } }],
    ["Vivado OOC Fmax, on-board run, measured power", { text: "pending: Vivado host, ZedBoard", options: { color: C.rust, bold: true } }],
  ], { x: 0.5, y: 3.65, w: 9, colW: [5.2, 3.8], fontFace: BF, fontSize: 12, color: C.ink, border: { type: "solid", pt: 0.5, color: C.line }, rowH: 0.36 });
  foot(s, n++);
}

// 12 — patent ---------------------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Patent Assessment", "Each candidate claim tested against prior art");
  const rows = [
    ["Two-message interleaved core (C)", "Helion 2010 (commercial IP) · IBM US20250070957A1 · SHARMONY, TCHES 2026"],
    ["Unrolling with pipelining (D)", "McEvoy, ISVLSI 2006 · Gamgam, ISCTürkiye 2023"],
    ["Operand rescheduling of T1", "Chaves, CHES 2006 · Yao et al., Comput. J. 2025 · Intel SHA256RNDS2"],
    ["Independence of the two axes", "Leiserson & Saxe, Algorithmica 1991"],
  ];
  s.addTable([
    [{ text: "Candidate claim", options: { bold: true, color: C.white, fill: { color: C.ink } } },
     { text: "Prior art", options: { bold: true, color: C.white, fill: { color: C.ink } } }],
    ...rows,
  ], { x: 0.5, y: 1.4, w: 6.3, colW: [2.3, 4.0], fontFace: BF, fontSize: 11, color: C.ink, valign: "middle",
       border: { type: "solid", pt: 0.5, color: C.line }, rowH: 0.62 });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 7.1, y: 1.4, w: 2.4, h: 1.5, fill: { color: C.ink }, rectRadius: 0.08, line: { color: C.ink } });
  s.addText([{ text: "Not patentable", options: { bold: true, fontSize: 18, breakLine: true } }, { text: "no inventive step", options: { fontSize: 12, color: "F3B08F" } }],
    { x: 7.25, y: 1.6, w: 2.1, h: 1.1, fontFace: BF, color: C.white, margin: 0, isTextBox: true });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 7.1, y: 3.1, w: 2.4, h: 1.95, fill: { color: C.peach }, rectRadius: 0.08, line: { color: C.peach } });
  s.addText([{ text: "Contribution", options: { bold: true, color: C.rust, breakLine: true } },
             { text: "Controlled re-test of a published result, with a measured mechanism", options: { color: C.ink } }],
    { x: 7.25, y: 3.25, w: 2.1, h: 1.7, fontFace: BF, fontSize: 12, margin: 0, isTextBox: true });
  foot(s, n++);
}

// 13 — literature position ---------------------------------------------------
{
  const s = pres.addSlide();
  title(s, "Position in the Literature", "44 works reviewed · 2002–2026");
  stat(s, 0.5, 1.45, 2.8, "44", "works tracked");
  stat(s, 0.5, 2.75, 2.8, "4", "claims tested against prior art");
  stat(s, 0.5, 4.05, 2.8, "1", "published result re-tested");
  s.addTable([
    [{ text: "Published claim", options: { bold: true } }, { text: "This work, XC7Z020", options: { bold: true } }],
    ["Unfolding ×2 raises Fmax (Suhaili & Julai 2022)", { text: "does not reproduce — 0.673", options: { color: C.rust, bold: true } }],
    ["Unfolding ×2 raises throughput (Suhaili & Julai 2022)", { text: "reproduces — 1.31×", options: { color: C.green, bold: true } }],
    ["Serial-chain model: Fmax halves", { text: "does not hold — synthesis builds a tree", options: { color: C.rust, bold: true } }],
    ["Interleaving preserves Fmax (structural)", { text: "confirmed — 0.999", options: { color: C.green, bold: true } }],
  ], { x: 3.6, y: 1.45, w: 5.9, colW: [3.2, 2.7], fontFace: BF, fontSize: 12, color: C.ink, valign: "middle",
       border: { type: "solid", pt: 0.5, color: C.line }, rowH: 0.7 });
  foot(s, n++);
}

// 14 — conclusion --------------------------------------------------------
{
  const s = pres.addSlide();
  s.background = { color: C.ink };
  s.addText("Findings", { x: 0.6, y: 0.5, w: 8.8, h: 0.6, fontFace: HF, fontSize: 32, bold: true, color: C.white, margin: 0, isTextBox: true });
  const f = [
    ["0.673", "Unrolling clears both pre-registered thresholds on XC7Z020."],
    ["Tree", "Synthesis, not unroll depth or RTL operand order, decides the outcome."],
    ["0.999", "Interleaving preserves Fmax; 2.00× throughput for independent messages."],
    ["Ready", "Board flow scripted; Vivado Fmax and on-board run remain."],
  ];
  f.forEach(([k, t], i) => {
    const y = 1.45 + i * 0.95;
    s.addText(k, { x: 0.6, y, w: 1.6, h: 0.7, fontFace: HF, fontSize: 26, bold: true, color: "F3B08F", margin: 0, valign: "middle", isTextBox: true });
    s.addText(t, { x: 2.3, y, w: 7.1, h: 0.7, fontFace: BF, fontSize: 16, color: C.white, margin: 0, valign: "middle", isTextBox: true });
  });
}

pres.writeFile({ fileName: process.argv[2] || "Review3_SHA256_Results.pptx" }).then((f) => console.log("wrote " + f));
