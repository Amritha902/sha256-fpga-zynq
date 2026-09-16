* SHA-256 round critical path: Sigma1 + 1 chained 32-bit adds

*=============================================================================
*  cmos180.lib -- generic 180 nm static CMOS cell library for ngspice
*
*  PURPOSE
*  -------
*  Transistor-level energy comparison of a plain ripple-carry adder against
*  the same adder wrapped in operand-dependent bypass logic.
*
*  HONEST SCOPE OF THESE MODELS
*  ----------------------------
*  These are generic SPICE LEVEL-1 MOSFET cards with 180 nm-class parameters.
*  They are NOT a foundry PDK and carry no process authority.
*
*  What that means for the results:
*      VALID    : the RATIO of energy between two structurally similar
*                 circuits simulated with the same models and the same
*                 stimulus.  Both designs share the identical full-adder
*                 cell, so systematic model error largely cancels.
*      NOT VALID: absolute energy in joules, absolute delay, or any claim
*                 about a specific foundry process.
*
*  Report the ratio and the break-even point.  Do not report the absolute
*  picojoules as though they were silicon measurements -- that is the same
*  mistake as quoting Vivado's power estimator as a measurement.
*=============================================================================

.model NMOS_M nmos (level=1 vto=0.42 kp=170u gamma=0.50 phi=0.70 lambda=0.04
+ tox=4.1n cgso=3.4e-10 cgdo=3.4e-10 cgbo=1.0e-10
+ cj=1.0e-3 cjsw=2.2e-10 mj=0.5 mjsw=0.33 pb=0.90 rsh=6)

.model PMOS_M pmos (level=1 vto=-0.42 kp=40u gamma=0.60 phi=0.70 lambda=0.06
+ tox=4.1n cgso=3.4e-10 cgdo=3.4e-10 cgbo=1.0e-10
+ cj=1.2e-3 cjsw=2.5e-10 mj=0.5 mjsw=0.33 pb=0.90 rsh=6)

*-----------------------------------------------------------------------------
*  Sizing: PMOS 2.4x NMOS for roughly symmetric rise/fall.
*-----------------------------------------------------------------------------
.param WN=0.5u WP=1.2u LMIN=0.18u

*-----------------------------------------------------------------------------
*  INV -- 2 transistors
*-----------------------------------------------------------------------------
.subckt INV a y vdd vss
MP y a vdd vdd PMOS_M W={WP} L={LMIN}
MN y a vss vss NMOS_M W={WN} L={LMIN}
.ends

*-----------------------------------------------------------------------------
*  NAND2 -- 4 transistors.  Series NMOS sized up to match.
*-----------------------------------------------------------------------------
.subckt NAND2 a b y vdd vss
MP1 y a vdd vdd PMOS_M W={WP} L={LMIN}
MP2 y b vdd vdd PMOS_M W={WP} L={LMIN}
MN1 y a nx  vss NMOS_M W={2*WN} L={LMIN}
MN2 nx b vss vss NMOS_M W={2*WN} L={LMIN}
.ends

*-----------------------------------------------------------------------------
*  NOR2 -- 4 transistors.  Series PMOS sized up to match.
*-----------------------------------------------------------------------------
.subckt NOR2 a b y vdd vss
MP1 px a vdd vdd PMOS_M W={2*WP} L={LMIN}
MP2 y  b px  vdd PMOS_M W={2*WP} L={LMIN}
MN1 y a vss vss NMOS_M W={WN} L={LMIN}
MN2 y b vss vss NMOS_M W={WN} L={LMIN}
.ends

*-----------------------------------------------------------------------------
*  AND2 / OR2 -- 6 transistors each
*-----------------------------------------------------------------------------
.subckt AND2 a b y vdd vss
Xn a b ni vdd vss NAND2
Xi ni y vdd vss INV
.ends

.subckt OR2 a b y vdd vss
Xn a b ni vdd vss NOR2
Xi ni y vdd vss INV
.ends

*-----------------------------------------------------------------------------
*  XOR2 -- 16 transistors, four NAND2.  Chosen for robustness over a leaner
*  transmission-gate version: both designs use the identical cell, so the
*  transistor count cancels in the ratio that matters.
*-----------------------------------------------------------------------------
.subckt XOR2 a b y vdd vss
Xn1 a b   n1 vdd vss NAND2
Xn2 a n1  n2 vdd vss NAND2
Xn3 b n1  n3 vdd vss NAND2
Xn4 n2 n3 y  vdd vss NAND2
.ends

*-----------------------------------------------------------------------------
*  FULL ADDER -- 50 transistors
*      s    = a XOR b XOR cin
*      cout = (a AND b) OR (cin AND (a XOR b))
*
*  THE SAME CELL IS USED BY BOTH DESIGNS.  That is what makes the energy
*  ratio meaningful: any model error in the adder is common to both.
*-----------------------------------------------------------------------------
.subckt FA a b cin s cout vdd vss
Xx1 a b     ab   vdd vss XOR2
Xx2 ab cin  s    vdd vss XOR2
Xa1 a b     g    vdd vss AND2
Xa2 ab cin  p    vdd vss AND2
Xo1 g p     cout vdd vss OR2
.ends

*-----------------------------------------------------------------------------
*  MUX2 -- 2:1 multiplexer, y = sel ? b : a.  12 transistors.
*-----------------------------------------------------------------------------
.subckt MUX2 a b sel y vdd vss
Xi  sel selb  vdd vss INV
Xa1 a selb ta vdd vss AND2
Xa2 b sel  tb vdd vss AND2
Xo  ta tb  y  vdd vss OR2
.ends

Vvdd vdd 0 DC 1.8

* ---- stimulus ----
Ve0 e0 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve1 e1 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve2 e2 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve3 e3 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve4 e4 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve5 e5 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve6 e6 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve7 e7 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve8 e8 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve9 e9 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve10 e10 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve11 e11 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve12 e12 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve13 e13 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve14 e14 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve15 e15 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve16 e16 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve17 e17 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve18 e18 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve19 e19 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve20 e20 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve21 e21 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve22 e22 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve23 e23 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve24 e24 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve25 e25 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve26 e26 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve27 e27 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve28 e28 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve29 e29 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve30 e30 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Ve31 e31 0 PWL(0 0 20.0000n 0 20.0500n 1.8)
Vone one 0 DC 1.8
Vzero zero 0 DC 0

* Sigma1 network: e -> s1
Xs1a_0 e6 e11 s1_t0 vdd 0 XOR2
Xs1b_0 s1_t0 e25 s10 vdd 0 XOR2
Xs1a_1 e7 e12 s1_t1 vdd 0 XOR2
Xs1b_1 s1_t1 e26 s11 vdd 0 XOR2
Xs1a_2 e8 e13 s1_t2 vdd 0 XOR2
Xs1b_2 s1_t2 e27 s12 vdd 0 XOR2
Xs1a_3 e9 e14 s1_t3 vdd 0 XOR2
Xs1b_3 s1_t3 e28 s13 vdd 0 XOR2
Xs1a_4 e10 e15 s1_t4 vdd 0 XOR2
Xs1b_4 s1_t4 e29 s14 vdd 0 XOR2
Xs1a_5 e11 e16 s1_t5 vdd 0 XOR2
Xs1b_5 s1_t5 e30 s15 vdd 0 XOR2
Xs1a_6 e12 e17 s1_t6 vdd 0 XOR2
Xs1b_6 s1_t6 e31 s16 vdd 0 XOR2
Xs1a_7 e13 e18 s1_t7 vdd 0 XOR2
Xs1b_7 s1_t7 e0 s17 vdd 0 XOR2
Xs1a_8 e14 e19 s1_t8 vdd 0 XOR2
Xs1b_8 s1_t8 e1 s18 vdd 0 XOR2
Xs1a_9 e15 e20 s1_t9 vdd 0 XOR2
Xs1b_9 s1_t9 e2 s19 vdd 0 XOR2
Xs1a_10 e16 e21 s1_t10 vdd 0 XOR2
Xs1b_10 s1_t10 e3 s110 vdd 0 XOR2
Xs1a_11 e17 e22 s1_t11 vdd 0 XOR2
Xs1b_11 s1_t11 e4 s111 vdd 0 XOR2
Xs1a_12 e18 e23 s1_t12 vdd 0 XOR2
Xs1b_12 s1_t12 e5 s112 vdd 0 XOR2
Xs1a_13 e19 e24 s1_t13 vdd 0 XOR2
Xs1b_13 s1_t13 e6 s113 vdd 0 XOR2
Xs1a_14 e20 e25 s1_t14 vdd 0 XOR2
Xs1b_14 s1_t14 e7 s114 vdd 0 XOR2
Xs1a_15 e21 e26 s1_t15 vdd 0 XOR2
Xs1b_15 s1_t15 e8 s115 vdd 0 XOR2
Xs1a_16 e22 e27 s1_t16 vdd 0 XOR2
Xs1b_16 s1_t16 e9 s116 vdd 0 XOR2
Xs1a_17 e23 e28 s1_t17 vdd 0 XOR2
Xs1b_17 s1_t17 e10 s117 vdd 0 XOR2
Xs1a_18 e24 e29 s1_t18 vdd 0 XOR2
Xs1b_18 s1_t18 e11 s118 vdd 0 XOR2
Xs1a_19 e25 e30 s1_t19 vdd 0 XOR2
Xs1b_19 s1_t19 e12 s119 vdd 0 XOR2
Xs1a_20 e26 e31 s1_t20 vdd 0 XOR2
Xs1b_20 s1_t20 e13 s120 vdd 0 XOR2
Xs1a_21 e27 e0 s1_t21 vdd 0 XOR2
Xs1b_21 s1_t21 e14 s121 vdd 0 XOR2
Xs1a_22 e28 e1 s1_t22 vdd 0 XOR2
Xs1b_22 s1_t22 e15 s122 vdd 0 XOR2
Xs1a_23 e29 e2 s1_t23 vdd 0 XOR2
Xs1b_23 s1_t23 e16 s123 vdd 0 XOR2
Xs1a_24 e30 e3 s1_t24 vdd 0 XOR2
Xs1b_24 s1_t24 e17 s124 vdd 0 XOR2
Xs1a_25 e31 e4 s1_t25 vdd 0 XOR2
Xs1b_25 s1_t25 e18 s125 vdd 0 XOR2
Xs1a_26 e0 e5 s1_t26 vdd 0 XOR2
Xs1b_26 s1_t26 e19 s126 vdd 0 XOR2
Xs1a_27 e1 e6 s1_t27 vdd 0 XOR2
Xs1b_27 s1_t27 e20 s127 vdd 0 XOR2
Xs1a_28 e2 e7 s1_t28 vdd 0 XOR2
Xs1b_28 s1_t28 e21 s128 vdd 0 XOR2
Xs1a_29 e3 e8 s1_t29 vdd 0 XOR2
Xs1b_29 s1_t29 e22 s129 vdd 0 XOR2
Xs1a_30 e4 e9 s1_t30 vdd 0 XOR2
Xs1b_30 s1_t30 e23 s130 vdd 0 XOR2
Xs1a_31 e5 e10 s1_t31 vdd 0 XOR2
Xs1b_31 s1_t31 e24 s131 vdd 0 XOR2

* ---- chained additions ----
* --- adder 1 of 1 ---
Radd0_0 one addb0_0 0.001
Radd0_1 zero addb0_1 0.001
Radd0_2 one addb0_2 0.001
Radd0_3 zero addb0_3 0.001
Radd0_4 one addb0_4 0.001
Radd0_5 zero addb0_5 0.001
Radd0_6 one addb0_6 0.001
Radd0_7 zero addb0_7 0.001
Radd0_8 one addb0_8 0.001
Radd0_9 zero addb0_9 0.001
Radd0_10 one addb0_10 0.001
Radd0_11 zero addb0_11 0.001
Radd0_12 one addb0_12 0.001
Radd0_13 zero addb0_13 0.001
Radd0_14 one addb0_14 0.001
Radd0_15 zero addb0_15 0.001
Radd0_16 one addb0_16 0.001
Radd0_17 zero addb0_17 0.001
Radd0_18 one addb0_18 0.001
Radd0_19 zero addb0_19 0.001
Radd0_20 one addb0_20 0.001
Radd0_21 zero addb0_21 0.001
Radd0_22 one addb0_22 0.001
Radd0_23 zero addb0_23 0.001
Radd0_24 one addb0_24 0.001
Radd0_25 zero addb0_25 0.001
Radd0_26 one addb0_26 0.001
Radd0_27 zero addb0_27 0.001
Radd0_28 one addb0_28 0.001
Radd0_29 zero addb0_29 0.001
Radd0_30 one addb0_30 0.001
Radd0_31 zero addb0_31 0.001
* add0: sum0 = s1 + addb0_
Xadd0_0 s10 addb0_0 zero sum00 add0_c1 vdd 0 FA
Xadd0_1 s11 addb0_1 add0_c1 sum01 add0_c2 vdd 0 FA
Xadd0_2 s12 addb0_2 add0_c2 sum02 add0_c3 vdd 0 FA
Xadd0_3 s13 addb0_3 add0_c3 sum03 add0_c4 vdd 0 FA
Xadd0_4 s14 addb0_4 add0_c4 sum04 add0_c5 vdd 0 FA
Xadd0_5 s15 addb0_5 add0_c5 sum05 add0_c6 vdd 0 FA
Xadd0_6 s16 addb0_6 add0_c6 sum06 add0_c7 vdd 0 FA
Xadd0_7 s17 addb0_7 add0_c7 sum07 add0_c8 vdd 0 FA
Xadd0_8 s18 addb0_8 add0_c8 sum08 add0_c9 vdd 0 FA
Xadd0_9 s19 addb0_9 add0_c9 sum09 add0_c10 vdd 0 FA
Xadd0_10 s110 addb0_10 add0_c10 sum010 add0_c11 vdd 0 FA
Xadd0_11 s111 addb0_11 add0_c11 sum011 add0_c12 vdd 0 FA
Xadd0_12 s112 addb0_12 add0_c12 sum012 add0_c13 vdd 0 FA
Xadd0_13 s113 addb0_13 add0_c13 sum013 add0_c14 vdd 0 FA
Xadd0_14 s114 addb0_14 add0_c14 sum014 add0_c15 vdd 0 FA
Xadd0_15 s115 addb0_15 add0_c15 sum015 add0_c16 vdd 0 FA
Xadd0_16 s116 addb0_16 add0_c16 sum016 add0_c17 vdd 0 FA
Xadd0_17 s117 addb0_17 add0_c17 sum017 add0_c18 vdd 0 FA
Xadd0_18 s118 addb0_18 add0_c18 sum018 add0_c19 vdd 0 FA
Xadd0_19 s119 addb0_19 add0_c19 sum019 add0_c20 vdd 0 FA
Xadd0_20 s120 addb0_20 add0_c20 sum020 add0_c21 vdd 0 FA
Xadd0_21 s121 addb0_21 add0_c21 sum021 add0_c22 vdd 0 FA
Xadd0_22 s122 addb0_22 add0_c22 sum022 add0_c23 vdd 0 FA
Xadd0_23 s123 addb0_23 add0_c23 sum023 add0_c24 vdd 0 FA
Xadd0_24 s124 addb0_24 add0_c24 sum024 add0_c25 vdd 0 FA
Xadd0_25 s125 addb0_25 add0_c25 sum025 add0_c26 vdd 0 FA
Xadd0_26 s126 addb0_26 add0_c26 sum026 add0_c27 vdd 0 FA
Xadd0_27 s127 addb0_27 add0_c27 sum027 add0_c28 vdd 0 FA
Xadd0_28 s128 addb0_28 add0_c28 sum028 add0_c29 vdd 0 FA
Xadd0_29 s129 addb0_29 add0_c29 sum029 add0_c30 vdd 0 FA
Xadd0_30 s130 addb0_30 add0_c30 sum030 add0_c31 vdd 0 FA
Xadd0_31 s131 addb0_31 add0_c31 sum031 add0_c32 vdd 0 FA

Cl0 sum00 0 5f
Cl1 sum01 0 5f
Cl2 sum02 0 5f
Cl3 sum03 0 5f
Cl4 sum04 0 5f
Cl5 sum05 0 5f
Cl6 sum06 0 5f
Cl7 sum07 0 5f
Cl8 sum08 0 5f
Cl9 sum09 0 5f
Cl10 sum010 0 5f
Cl11 sum011 0 5f
Cl12 sum012 0 5f
Cl13 sum013 0 5f
Cl14 sum014 0 5f
Cl15 sum015 0 5f
Cl16 sum016 0 5f
Cl17 sum017 0 5f
Cl18 sum018 0 5f
Cl19 sum019 0 5f
Cl20 sum020 0 5f
Cl21 sum021 0 5f
Cl22 sum022 0 5f
Cl23 sum023 0 5f
Cl24 sum024 0 5f
Cl25 sum025 0 5f
Cl26 sum026 0 5f
Cl27 sum027 0 5f
Cl28 sum028 0 5f
Cl29 sum029 0 5f
Cl30 sum030 0 5f
Cl31 sum031 0 5f

.tran 5p 80.0000n

.meas tran tp0 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum00) VAL=0.9 CROSS=LAST
.meas tran tp1 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum01) VAL=0.9 CROSS=LAST
.meas tran tp2 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum02) VAL=0.9 CROSS=LAST
.meas tran tp3 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum03) VAL=0.9 CROSS=LAST
.meas tran tp4 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum04) VAL=0.9 CROSS=LAST
.meas tran tp5 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum05) VAL=0.9 CROSS=LAST
.meas tran tp6 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum06) VAL=0.9 CROSS=LAST
.meas tran tp7 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum07) VAL=0.9 CROSS=LAST
.meas tran tp8 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum08) VAL=0.9 CROSS=LAST
.meas tran tp9 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum09) VAL=0.9 CROSS=LAST
.meas tran tp10 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum010) VAL=0.9 CROSS=LAST
.meas tran tp11 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum011) VAL=0.9 CROSS=LAST
.meas tran tp12 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum012) VAL=0.9 CROSS=LAST
.meas tran tp13 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum013) VAL=0.9 CROSS=LAST
.meas tran tp14 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum014) VAL=0.9 CROSS=LAST
.meas tran tp15 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum015) VAL=0.9 CROSS=LAST
.meas tran tp16 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum016) VAL=0.9 CROSS=LAST
.meas tran tp17 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum017) VAL=0.9 CROSS=LAST
.meas tran tp18 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum018) VAL=0.9 CROSS=LAST
.meas tran tp19 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum019) VAL=0.9 CROSS=LAST
.meas tran tp20 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum020) VAL=0.9 CROSS=LAST
.meas tran tp21 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum021) VAL=0.9 CROSS=LAST
.meas tran tp22 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum022) VAL=0.9 CROSS=LAST
.meas tran tp23 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum023) VAL=0.9 CROSS=LAST
.meas tran tp24 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum024) VAL=0.9 CROSS=LAST
.meas tran tp25 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum025) VAL=0.9 CROSS=LAST
.meas tran tp26 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum026) VAL=0.9 CROSS=LAST
.meas tran tp27 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum027) VAL=0.9 CROSS=LAST
.meas tran tp28 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum028) VAL=0.9 CROSS=LAST
.meas tran tp29 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum029) VAL=0.9 CROSS=LAST
.meas tran tp30 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum030) VAL=0.9 CROSS=LAST
.meas tran tp31 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum031) VAL=0.9 CROSS=LAST
.end
