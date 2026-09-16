* SHA-256 round critical path: Sigma1 + 7 chained 32-bit adds

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
* --- adder 1 of 7 ---
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
* --- adder 2 of 7 ---
Radd1_0 one addb1_0 0.001
Radd1_1 zero addb1_1 0.001
Radd1_2 one addb1_2 0.001
Radd1_3 zero addb1_3 0.001
Radd1_4 one addb1_4 0.001
Radd1_5 zero addb1_5 0.001
Radd1_6 one addb1_6 0.001
Radd1_7 zero addb1_7 0.001
Radd1_8 one addb1_8 0.001
Radd1_9 zero addb1_9 0.001
Radd1_10 one addb1_10 0.001
Radd1_11 zero addb1_11 0.001
Radd1_12 one addb1_12 0.001
Radd1_13 zero addb1_13 0.001
Radd1_14 one addb1_14 0.001
Radd1_15 zero addb1_15 0.001
Radd1_16 one addb1_16 0.001
Radd1_17 zero addb1_17 0.001
Radd1_18 one addb1_18 0.001
Radd1_19 zero addb1_19 0.001
Radd1_20 one addb1_20 0.001
Radd1_21 zero addb1_21 0.001
Radd1_22 one addb1_22 0.001
Radd1_23 zero addb1_23 0.001
Radd1_24 one addb1_24 0.001
Radd1_25 zero addb1_25 0.001
Radd1_26 one addb1_26 0.001
Radd1_27 zero addb1_27 0.001
Radd1_28 one addb1_28 0.001
Radd1_29 zero addb1_29 0.001
Radd1_30 one addb1_30 0.001
Radd1_31 zero addb1_31 0.001
* add1: sum1 = sum0 + addb1_
Xadd1_0 sum00 addb1_0 zero sum10 add1_c1 vdd 0 FA
Xadd1_1 sum01 addb1_1 add1_c1 sum11 add1_c2 vdd 0 FA
Xadd1_2 sum02 addb1_2 add1_c2 sum12 add1_c3 vdd 0 FA
Xadd1_3 sum03 addb1_3 add1_c3 sum13 add1_c4 vdd 0 FA
Xadd1_4 sum04 addb1_4 add1_c4 sum14 add1_c5 vdd 0 FA
Xadd1_5 sum05 addb1_5 add1_c5 sum15 add1_c6 vdd 0 FA
Xadd1_6 sum06 addb1_6 add1_c6 sum16 add1_c7 vdd 0 FA
Xadd1_7 sum07 addb1_7 add1_c7 sum17 add1_c8 vdd 0 FA
Xadd1_8 sum08 addb1_8 add1_c8 sum18 add1_c9 vdd 0 FA
Xadd1_9 sum09 addb1_9 add1_c9 sum19 add1_c10 vdd 0 FA
Xadd1_10 sum010 addb1_10 add1_c10 sum110 add1_c11 vdd 0 FA
Xadd1_11 sum011 addb1_11 add1_c11 sum111 add1_c12 vdd 0 FA
Xadd1_12 sum012 addb1_12 add1_c12 sum112 add1_c13 vdd 0 FA
Xadd1_13 sum013 addb1_13 add1_c13 sum113 add1_c14 vdd 0 FA
Xadd1_14 sum014 addb1_14 add1_c14 sum114 add1_c15 vdd 0 FA
Xadd1_15 sum015 addb1_15 add1_c15 sum115 add1_c16 vdd 0 FA
Xadd1_16 sum016 addb1_16 add1_c16 sum116 add1_c17 vdd 0 FA
Xadd1_17 sum017 addb1_17 add1_c17 sum117 add1_c18 vdd 0 FA
Xadd1_18 sum018 addb1_18 add1_c18 sum118 add1_c19 vdd 0 FA
Xadd1_19 sum019 addb1_19 add1_c19 sum119 add1_c20 vdd 0 FA
Xadd1_20 sum020 addb1_20 add1_c20 sum120 add1_c21 vdd 0 FA
Xadd1_21 sum021 addb1_21 add1_c21 sum121 add1_c22 vdd 0 FA
Xadd1_22 sum022 addb1_22 add1_c22 sum122 add1_c23 vdd 0 FA
Xadd1_23 sum023 addb1_23 add1_c23 sum123 add1_c24 vdd 0 FA
Xadd1_24 sum024 addb1_24 add1_c24 sum124 add1_c25 vdd 0 FA
Xadd1_25 sum025 addb1_25 add1_c25 sum125 add1_c26 vdd 0 FA
Xadd1_26 sum026 addb1_26 add1_c26 sum126 add1_c27 vdd 0 FA
Xadd1_27 sum027 addb1_27 add1_c27 sum127 add1_c28 vdd 0 FA
Xadd1_28 sum028 addb1_28 add1_c28 sum128 add1_c29 vdd 0 FA
Xadd1_29 sum029 addb1_29 add1_c29 sum129 add1_c30 vdd 0 FA
Xadd1_30 sum030 addb1_30 add1_c30 sum130 add1_c31 vdd 0 FA
Xadd1_31 sum031 addb1_31 add1_c31 sum131 add1_c32 vdd 0 FA
* --- adder 3 of 7 ---
Radd2_0 one addb2_0 0.001
Radd2_1 zero addb2_1 0.001
Radd2_2 one addb2_2 0.001
Radd2_3 zero addb2_3 0.001
Radd2_4 one addb2_4 0.001
Radd2_5 zero addb2_5 0.001
Radd2_6 one addb2_6 0.001
Radd2_7 zero addb2_7 0.001
Radd2_8 one addb2_8 0.001
Radd2_9 zero addb2_9 0.001
Radd2_10 one addb2_10 0.001
Radd2_11 zero addb2_11 0.001
Radd2_12 one addb2_12 0.001
Radd2_13 zero addb2_13 0.001
Radd2_14 one addb2_14 0.001
Radd2_15 zero addb2_15 0.001
Radd2_16 one addb2_16 0.001
Radd2_17 zero addb2_17 0.001
Radd2_18 one addb2_18 0.001
Radd2_19 zero addb2_19 0.001
Radd2_20 one addb2_20 0.001
Radd2_21 zero addb2_21 0.001
Radd2_22 one addb2_22 0.001
Radd2_23 zero addb2_23 0.001
Radd2_24 one addb2_24 0.001
Radd2_25 zero addb2_25 0.001
Radd2_26 one addb2_26 0.001
Radd2_27 zero addb2_27 0.001
Radd2_28 one addb2_28 0.001
Radd2_29 zero addb2_29 0.001
Radd2_30 one addb2_30 0.001
Radd2_31 zero addb2_31 0.001
* add2: sum2 = sum1 + addb2_
Xadd2_0 sum10 addb2_0 zero sum20 add2_c1 vdd 0 FA
Xadd2_1 sum11 addb2_1 add2_c1 sum21 add2_c2 vdd 0 FA
Xadd2_2 sum12 addb2_2 add2_c2 sum22 add2_c3 vdd 0 FA
Xadd2_3 sum13 addb2_3 add2_c3 sum23 add2_c4 vdd 0 FA
Xadd2_4 sum14 addb2_4 add2_c4 sum24 add2_c5 vdd 0 FA
Xadd2_5 sum15 addb2_5 add2_c5 sum25 add2_c6 vdd 0 FA
Xadd2_6 sum16 addb2_6 add2_c6 sum26 add2_c7 vdd 0 FA
Xadd2_7 sum17 addb2_7 add2_c7 sum27 add2_c8 vdd 0 FA
Xadd2_8 sum18 addb2_8 add2_c8 sum28 add2_c9 vdd 0 FA
Xadd2_9 sum19 addb2_9 add2_c9 sum29 add2_c10 vdd 0 FA
Xadd2_10 sum110 addb2_10 add2_c10 sum210 add2_c11 vdd 0 FA
Xadd2_11 sum111 addb2_11 add2_c11 sum211 add2_c12 vdd 0 FA
Xadd2_12 sum112 addb2_12 add2_c12 sum212 add2_c13 vdd 0 FA
Xadd2_13 sum113 addb2_13 add2_c13 sum213 add2_c14 vdd 0 FA
Xadd2_14 sum114 addb2_14 add2_c14 sum214 add2_c15 vdd 0 FA
Xadd2_15 sum115 addb2_15 add2_c15 sum215 add2_c16 vdd 0 FA
Xadd2_16 sum116 addb2_16 add2_c16 sum216 add2_c17 vdd 0 FA
Xadd2_17 sum117 addb2_17 add2_c17 sum217 add2_c18 vdd 0 FA
Xadd2_18 sum118 addb2_18 add2_c18 sum218 add2_c19 vdd 0 FA
Xadd2_19 sum119 addb2_19 add2_c19 sum219 add2_c20 vdd 0 FA
Xadd2_20 sum120 addb2_20 add2_c20 sum220 add2_c21 vdd 0 FA
Xadd2_21 sum121 addb2_21 add2_c21 sum221 add2_c22 vdd 0 FA
Xadd2_22 sum122 addb2_22 add2_c22 sum222 add2_c23 vdd 0 FA
Xadd2_23 sum123 addb2_23 add2_c23 sum223 add2_c24 vdd 0 FA
Xadd2_24 sum124 addb2_24 add2_c24 sum224 add2_c25 vdd 0 FA
Xadd2_25 sum125 addb2_25 add2_c25 sum225 add2_c26 vdd 0 FA
Xadd2_26 sum126 addb2_26 add2_c26 sum226 add2_c27 vdd 0 FA
Xadd2_27 sum127 addb2_27 add2_c27 sum227 add2_c28 vdd 0 FA
Xadd2_28 sum128 addb2_28 add2_c28 sum228 add2_c29 vdd 0 FA
Xadd2_29 sum129 addb2_29 add2_c29 sum229 add2_c30 vdd 0 FA
Xadd2_30 sum130 addb2_30 add2_c30 sum230 add2_c31 vdd 0 FA
Xadd2_31 sum131 addb2_31 add2_c31 sum231 add2_c32 vdd 0 FA
* --- adder 4 of 7 ---
Radd3_0 one addb3_0 0.001
Radd3_1 zero addb3_1 0.001
Radd3_2 one addb3_2 0.001
Radd3_3 zero addb3_3 0.001
Radd3_4 one addb3_4 0.001
Radd3_5 zero addb3_5 0.001
Radd3_6 one addb3_6 0.001
Radd3_7 zero addb3_7 0.001
Radd3_8 one addb3_8 0.001
Radd3_9 zero addb3_9 0.001
Radd3_10 one addb3_10 0.001
Radd3_11 zero addb3_11 0.001
Radd3_12 one addb3_12 0.001
Radd3_13 zero addb3_13 0.001
Radd3_14 one addb3_14 0.001
Radd3_15 zero addb3_15 0.001
Radd3_16 one addb3_16 0.001
Radd3_17 zero addb3_17 0.001
Radd3_18 one addb3_18 0.001
Radd3_19 zero addb3_19 0.001
Radd3_20 one addb3_20 0.001
Radd3_21 zero addb3_21 0.001
Radd3_22 one addb3_22 0.001
Radd3_23 zero addb3_23 0.001
Radd3_24 one addb3_24 0.001
Radd3_25 zero addb3_25 0.001
Radd3_26 one addb3_26 0.001
Radd3_27 zero addb3_27 0.001
Radd3_28 one addb3_28 0.001
Radd3_29 zero addb3_29 0.001
Radd3_30 one addb3_30 0.001
Radd3_31 zero addb3_31 0.001
* add3: sum3 = sum2 + addb3_
Xadd3_0 sum20 addb3_0 zero sum30 add3_c1 vdd 0 FA
Xadd3_1 sum21 addb3_1 add3_c1 sum31 add3_c2 vdd 0 FA
Xadd3_2 sum22 addb3_2 add3_c2 sum32 add3_c3 vdd 0 FA
Xadd3_3 sum23 addb3_3 add3_c3 sum33 add3_c4 vdd 0 FA
Xadd3_4 sum24 addb3_4 add3_c4 sum34 add3_c5 vdd 0 FA
Xadd3_5 sum25 addb3_5 add3_c5 sum35 add3_c6 vdd 0 FA
Xadd3_6 sum26 addb3_6 add3_c6 sum36 add3_c7 vdd 0 FA
Xadd3_7 sum27 addb3_7 add3_c7 sum37 add3_c8 vdd 0 FA
Xadd3_8 sum28 addb3_8 add3_c8 sum38 add3_c9 vdd 0 FA
Xadd3_9 sum29 addb3_9 add3_c9 sum39 add3_c10 vdd 0 FA
Xadd3_10 sum210 addb3_10 add3_c10 sum310 add3_c11 vdd 0 FA
Xadd3_11 sum211 addb3_11 add3_c11 sum311 add3_c12 vdd 0 FA
Xadd3_12 sum212 addb3_12 add3_c12 sum312 add3_c13 vdd 0 FA
Xadd3_13 sum213 addb3_13 add3_c13 sum313 add3_c14 vdd 0 FA
Xadd3_14 sum214 addb3_14 add3_c14 sum314 add3_c15 vdd 0 FA
Xadd3_15 sum215 addb3_15 add3_c15 sum315 add3_c16 vdd 0 FA
Xadd3_16 sum216 addb3_16 add3_c16 sum316 add3_c17 vdd 0 FA
Xadd3_17 sum217 addb3_17 add3_c17 sum317 add3_c18 vdd 0 FA
Xadd3_18 sum218 addb3_18 add3_c18 sum318 add3_c19 vdd 0 FA
Xadd3_19 sum219 addb3_19 add3_c19 sum319 add3_c20 vdd 0 FA
Xadd3_20 sum220 addb3_20 add3_c20 sum320 add3_c21 vdd 0 FA
Xadd3_21 sum221 addb3_21 add3_c21 sum321 add3_c22 vdd 0 FA
Xadd3_22 sum222 addb3_22 add3_c22 sum322 add3_c23 vdd 0 FA
Xadd3_23 sum223 addb3_23 add3_c23 sum323 add3_c24 vdd 0 FA
Xadd3_24 sum224 addb3_24 add3_c24 sum324 add3_c25 vdd 0 FA
Xadd3_25 sum225 addb3_25 add3_c25 sum325 add3_c26 vdd 0 FA
Xadd3_26 sum226 addb3_26 add3_c26 sum326 add3_c27 vdd 0 FA
Xadd3_27 sum227 addb3_27 add3_c27 sum327 add3_c28 vdd 0 FA
Xadd3_28 sum228 addb3_28 add3_c28 sum328 add3_c29 vdd 0 FA
Xadd3_29 sum229 addb3_29 add3_c29 sum329 add3_c30 vdd 0 FA
Xadd3_30 sum230 addb3_30 add3_c30 sum330 add3_c31 vdd 0 FA
Xadd3_31 sum231 addb3_31 add3_c31 sum331 add3_c32 vdd 0 FA
* --- adder 5 of 7 ---
Radd4_0 one addb4_0 0.001
Radd4_1 zero addb4_1 0.001
Radd4_2 one addb4_2 0.001
Radd4_3 zero addb4_3 0.001
Radd4_4 one addb4_4 0.001
Radd4_5 zero addb4_5 0.001
Radd4_6 one addb4_6 0.001
Radd4_7 zero addb4_7 0.001
Radd4_8 one addb4_8 0.001
Radd4_9 zero addb4_9 0.001
Radd4_10 one addb4_10 0.001
Radd4_11 zero addb4_11 0.001
Radd4_12 one addb4_12 0.001
Radd4_13 zero addb4_13 0.001
Radd4_14 one addb4_14 0.001
Radd4_15 zero addb4_15 0.001
Radd4_16 one addb4_16 0.001
Radd4_17 zero addb4_17 0.001
Radd4_18 one addb4_18 0.001
Radd4_19 zero addb4_19 0.001
Radd4_20 one addb4_20 0.001
Radd4_21 zero addb4_21 0.001
Radd4_22 one addb4_22 0.001
Radd4_23 zero addb4_23 0.001
Radd4_24 one addb4_24 0.001
Radd4_25 zero addb4_25 0.001
Radd4_26 one addb4_26 0.001
Radd4_27 zero addb4_27 0.001
Radd4_28 one addb4_28 0.001
Radd4_29 zero addb4_29 0.001
Radd4_30 one addb4_30 0.001
Radd4_31 zero addb4_31 0.001
* add4: sum4 = sum3 + addb4_
Xadd4_0 sum30 addb4_0 zero sum40 add4_c1 vdd 0 FA
Xadd4_1 sum31 addb4_1 add4_c1 sum41 add4_c2 vdd 0 FA
Xadd4_2 sum32 addb4_2 add4_c2 sum42 add4_c3 vdd 0 FA
Xadd4_3 sum33 addb4_3 add4_c3 sum43 add4_c4 vdd 0 FA
Xadd4_4 sum34 addb4_4 add4_c4 sum44 add4_c5 vdd 0 FA
Xadd4_5 sum35 addb4_5 add4_c5 sum45 add4_c6 vdd 0 FA
Xadd4_6 sum36 addb4_6 add4_c6 sum46 add4_c7 vdd 0 FA
Xadd4_7 sum37 addb4_7 add4_c7 sum47 add4_c8 vdd 0 FA
Xadd4_8 sum38 addb4_8 add4_c8 sum48 add4_c9 vdd 0 FA
Xadd4_9 sum39 addb4_9 add4_c9 sum49 add4_c10 vdd 0 FA
Xadd4_10 sum310 addb4_10 add4_c10 sum410 add4_c11 vdd 0 FA
Xadd4_11 sum311 addb4_11 add4_c11 sum411 add4_c12 vdd 0 FA
Xadd4_12 sum312 addb4_12 add4_c12 sum412 add4_c13 vdd 0 FA
Xadd4_13 sum313 addb4_13 add4_c13 sum413 add4_c14 vdd 0 FA
Xadd4_14 sum314 addb4_14 add4_c14 sum414 add4_c15 vdd 0 FA
Xadd4_15 sum315 addb4_15 add4_c15 sum415 add4_c16 vdd 0 FA
Xadd4_16 sum316 addb4_16 add4_c16 sum416 add4_c17 vdd 0 FA
Xadd4_17 sum317 addb4_17 add4_c17 sum417 add4_c18 vdd 0 FA
Xadd4_18 sum318 addb4_18 add4_c18 sum418 add4_c19 vdd 0 FA
Xadd4_19 sum319 addb4_19 add4_c19 sum419 add4_c20 vdd 0 FA
Xadd4_20 sum320 addb4_20 add4_c20 sum420 add4_c21 vdd 0 FA
Xadd4_21 sum321 addb4_21 add4_c21 sum421 add4_c22 vdd 0 FA
Xadd4_22 sum322 addb4_22 add4_c22 sum422 add4_c23 vdd 0 FA
Xadd4_23 sum323 addb4_23 add4_c23 sum423 add4_c24 vdd 0 FA
Xadd4_24 sum324 addb4_24 add4_c24 sum424 add4_c25 vdd 0 FA
Xadd4_25 sum325 addb4_25 add4_c25 sum425 add4_c26 vdd 0 FA
Xadd4_26 sum326 addb4_26 add4_c26 sum426 add4_c27 vdd 0 FA
Xadd4_27 sum327 addb4_27 add4_c27 sum427 add4_c28 vdd 0 FA
Xadd4_28 sum328 addb4_28 add4_c28 sum428 add4_c29 vdd 0 FA
Xadd4_29 sum329 addb4_29 add4_c29 sum429 add4_c30 vdd 0 FA
Xadd4_30 sum330 addb4_30 add4_c30 sum430 add4_c31 vdd 0 FA
Xadd4_31 sum331 addb4_31 add4_c31 sum431 add4_c32 vdd 0 FA
* --- adder 6 of 7 ---
Radd5_0 one addb5_0 0.001
Radd5_1 zero addb5_1 0.001
Radd5_2 one addb5_2 0.001
Radd5_3 zero addb5_3 0.001
Radd5_4 one addb5_4 0.001
Radd5_5 zero addb5_5 0.001
Radd5_6 one addb5_6 0.001
Radd5_7 zero addb5_7 0.001
Radd5_8 one addb5_8 0.001
Radd5_9 zero addb5_9 0.001
Radd5_10 one addb5_10 0.001
Radd5_11 zero addb5_11 0.001
Radd5_12 one addb5_12 0.001
Radd5_13 zero addb5_13 0.001
Radd5_14 one addb5_14 0.001
Radd5_15 zero addb5_15 0.001
Radd5_16 one addb5_16 0.001
Radd5_17 zero addb5_17 0.001
Radd5_18 one addb5_18 0.001
Radd5_19 zero addb5_19 0.001
Radd5_20 one addb5_20 0.001
Radd5_21 zero addb5_21 0.001
Radd5_22 one addb5_22 0.001
Radd5_23 zero addb5_23 0.001
Radd5_24 one addb5_24 0.001
Radd5_25 zero addb5_25 0.001
Radd5_26 one addb5_26 0.001
Radd5_27 zero addb5_27 0.001
Radd5_28 one addb5_28 0.001
Radd5_29 zero addb5_29 0.001
Radd5_30 one addb5_30 0.001
Radd5_31 zero addb5_31 0.001
* add5: sum5 = sum4 + addb5_
Xadd5_0 sum40 addb5_0 zero sum50 add5_c1 vdd 0 FA
Xadd5_1 sum41 addb5_1 add5_c1 sum51 add5_c2 vdd 0 FA
Xadd5_2 sum42 addb5_2 add5_c2 sum52 add5_c3 vdd 0 FA
Xadd5_3 sum43 addb5_3 add5_c3 sum53 add5_c4 vdd 0 FA
Xadd5_4 sum44 addb5_4 add5_c4 sum54 add5_c5 vdd 0 FA
Xadd5_5 sum45 addb5_5 add5_c5 sum55 add5_c6 vdd 0 FA
Xadd5_6 sum46 addb5_6 add5_c6 sum56 add5_c7 vdd 0 FA
Xadd5_7 sum47 addb5_7 add5_c7 sum57 add5_c8 vdd 0 FA
Xadd5_8 sum48 addb5_8 add5_c8 sum58 add5_c9 vdd 0 FA
Xadd5_9 sum49 addb5_9 add5_c9 sum59 add5_c10 vdd 0 FA
Xadd5_10 sum410 addb5_10 add5_c10 sum510 add5_c11 vdd 0 FA
Xadd5_11 sum411 addb5_11 add5_c11 sum511 add5_c12 vdd 0 FA
Xadd5_12 sum412 addb5_12 add5_c12 sum512 add5_c13 vdd 0 FA
Xadd5_13 sum413 addb5_13 add5_c13 sum513 add5_c14 vdd 0 FA
Xadd5_14 sum414 addb5_14 add5_c14 sum514 add5_c15 vdd 0 FA
Xadd5_15 sum415 addb5_15 add5_c15 sum515 add5_c16 vdd 0 FA
Xadd5_16 sum416 addb5_16 add5_c16 sum516 add5_c17 vdd 0 FA
Xadd5_17 sum417 addb5_17 add5_c17 sum517 add5_c18 vdd 0 FA
Xadd5_18 sum418 addb5_18 add5_c18 sum518 add5_c19 vdd 0 FA
Xadd5_19 sum419 addb5_19 add5_c19 sum519 add5_c20 vdd 0 FA
Xadd5_20 sum420 addb5_20 add5_c20 sum520 add5_c21 vdd 0 FA
Xadd5_21 sum421 addb5_21 add5_c21 sum521 add5_c22 vdd 0 FA
Xadd5_22 sum422 addb5_22 add5_c22 sum522 add5_c23 vdd 0 FA
Xadd5_23 sum423 addb5_23 add5_c23 sum523 add5_c24 vdd 0 FA
Xadd5_24 sum424 addb5_24 add5_c24 sum524 add5_c25 vdd 0 FA
Xadd5_25 sum425 addb5_25 add5_c25 sum525 add5_c26 vdd 0 FA
Xadd5_26 sum426 addb5_26 add5_c26 sum526 add5_c27 vdd 0 FA
Xadd5_27 sum427 addb5_27 add5_c27 sum527 add5_c28 vdd 0 FA
Xadd5_28 sum428 addb5_28 add5_c28 sum528 add5_c29 vdd 0 FA
Xadd5_29 sum429 addb5_29 add5_c29 sum529 add5_c30 vdd 0 FA
Xadd5_30 sum430 addb5_30 add5_c30 sum530 add5_c31 vdd 0 FA
Xadd5_31 sum431 addb5_31 add5_c31 sum531 add5_c32 vdd 0 FA
* --- adder 7 of 7 ---
Radd6_0 one addb6_0 0.001
Radd6_1 zero addb6_1 0.001
Radd6_2 one addb6_2 0.001
Radd6_3 zero addb6_3 0.001
Radd6_4 one addb6_4 0.001
Radd6_5 zero addb6_5 0.001
Radd6_6 one addb6_6 0.001
Radd6_7 zero addb6_7 0.001
Radd6_8 one addb6_8 0.001
Radd6_9 zero addb6_9 0.001
Radd6_10 one addb6_10 0.001
Radd6_11 zero addb6_11 0.001
Radd6_12 one addb6_12 0.001
Radd6_13 zero addb6_13 0.001
Radd6_14 one addb6_14 0.001
Radd6_15 zero addb6_15 0.001
Radd6_16 one addb6_16 0.001
Radd6_17 zero addb6_17 0.001
Radd6_18 one addb6_18 0.001
Radd6_19 zero addb6_19 0.001
Radd6_20 one addb6_20 0.001
Radd6_21 zero addb6_21 0.001
Radd6_22 one addb6_22 0.001
Radd6_23 zero addb6_23 0.001
Radd6_24 one addb6_24 0.001
Radd6_25 zero addb6_25 0.001
Radd6_26 one addb6_26 0.001
Radd6_27 zero addb6_27 0.001
Radd6_28 one addb6_28 0.001
Radd6_29 zero addb6_29 0.001
Radd6_30 one addb6_30 0.001
Radd6_31 zero addb6_31 0.001
* add6: sum6 = sum5 + addb6_
Xadd6_0 sum50 addb6_0 zero sum60 add6_c1 vdd 0 FA
Xadd6_1 sum51 addb6_1 add6_c1 sum61 add6_c2 vdd 0 FA
Xadd6_2 sum52 addb6_2 add6_c2 sum62 add6_c3 vdd 0 FA
Xadd6_3 sum53 addb6_3 add6_c3 sum63 add6_c4 vdd 0 FA
Xadd6_4 sum54 addb6_4 add6_c4 sum64 add6_c5 vdd 0 FA
Xadd6_5 sum55 addb6_5 add6_c5 sum65 add6_c6 vdd 0 FA
Xadd6_6 sum56 addb6_6 add6_c6 sum66 add6_c7 vdd 0 FA
Xadd6_7 sum57 addb6_7 add6_c7 sum67 add6_c8 vdd 0 FA
Xadd6_8 sum58 addb6_8 add6_c8 sum68 add6_c9 vdd 0 FA
Xadd6_9 sum59 addb6_9 add6_c9 sum69 add6_c10 vdd 0 FA
Xadd6_10 sum510 addb6_10 add6_c10 sum610 add6_c11 vdd 0 FA
Xadd6_11 sum511 addb6_11 add6_c11 sum611 add6_c12 vdd 0 FA
Xadd6_12 sum512 addb6_12 add6_c12 sum612 add6_c13 vdd 0 FA
Xadd6_13 sum513 addb6_13 add6_c13 sum613 add6_c14 vdd 0 FA
Xadd6_14 sum514 addb6_14 add6_c14 sum614 add6_c15 vdd 0 FA
Xadd6_15 sum515 addb6_15 add6_c15 sum615 add6_c16 vdd 0 FA
Xadd6_16 sum516 addb6_16 add6_c16 sum616 add6_c17 vdd 0 FA
Xadd6_17 sum517 addb6_17 add6_c17 sum617 add6_c18 vdd 0 FA
Xadd6_18 sum518 addb6_18 add6_c18 sum618 add6_c19 vdd 0 FA
Xadd6_19 sum519 addb6_19 add6_c19 sum619 add6_c20 vdd 0 FA
Xadd6_20 sum520 addb6_20 add6_c20 sum620 add6_c21 vdd 0 FA
Xadd6_21 sum521 addb6_21 add6_c21 sum621 add6_c22 vdd 0 FA
Xadd6_22 sum522 addb6_22 add6_c22 sum622 add6_c23 vdd 0 FA
Xadd6_23 sum523 addb6_23 add6_c23 sum623 add6_c24 vdd 0 FA
Xadd6_24 sum524 addb6_24 add6_c24 sum624 add6_c25 vdd 0 FA
Xadd6_25 sum525 addb6_25 add6_c25 sum625 add6_c26 vdd 0 FA
Xadd6_26 sum526 addb6_26 add6_c26 sum626 add6_c27 vdd 0 FA
Xadd6_27 sum527 addb6_27 add6_c27 sum627 add6_c28 vdd 0 FA
Xadd6_28 sum528 addb6_28 add6_c28 sum628 add6_c29 vdd 0 FA
Xadd6_29 sum529 addb6_29 add6_c29 sum629 add6_c30 vdd 0 FA
Xadd6_30 sum530 addb6_30 add6_c30 sum630 add6_c31 vdd 0 FA
Xadd6_31 sum531 addb6_31 add6_c31 sum631 add6_c32 vdd 0 FA

Cl0 sum60 0 5f
Cl1 sum61 0 5f
Cl2 sum62 0 5f
Cl3 sum63 0 5f
Cl4 sum64 0 5f
Cl5 sum65 0 5f
Cl6 sum66 0 5f
Cl7 sum67 0 5f
Cl8 sum68 0 5f
Cl9 sum69 0 5f
Cl10 sum610 0 5f
Cl11 sum611 0 5f
Cl12 sum612 0 5f
Cl13 sum613 0 5f
Cl14 sum614 0 5f
Cl15 sum615 0 5f
Cl16 sum616 0 5f
Cl17 sum617 0 5f
Cl18 sum618 0 5f
Cl19 sum619 0 5f
Cl20 sum620 0 5f
Cl21 sum621 0 5f
Cl22 sum622 0 5f
Cl23 sum623 0 5f
Cl24 sum624 0 5f
Cl25 sum625 0 5f
Cl26 sum626 0 5f
Cl27 sum627 0 5f
Cl28 sum628 0 5f
Cl29 sum629 0 5f
Cl30 sum630 0 5f
Cl31 sum631 0 5f

.tran 5p 80.0000n

.meas tran tp0 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum60) VAL=0.9 CROSS=LAST
.meas tran tp1 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum61) VAL=0.9 CROSS=LAST
.meas tran tp2 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum62) VAL=0.9 CROSS=LAST
.meas tran tp3 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum63) VAL=0.9 CROSS=LAST
.meas tran tp4 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum64) VAL=0.9 CROSS=LAST
.meas tran tp5 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum65) VAL=0.9 CROSS=LAST
.meas tran tp6 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum66) VAL=0.9 CROSS=LAST
.meas tran tp7 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum67) VAL=0.9 CROSS=LAST
.meas tran tp8 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum68) VAL=0.9 CROSS=LAST
.meas tran tp9 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum69) VAL=0.9 CROSS=LAST
.meas tran tp10 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum610) VAL=0.9 CROSS=LAST
.meas tran tp11 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum611) VAL=0.9 CROSS=LAST
.meas tran tp12 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum612) VAL=0.9 CROSS=LAST
.meas tran tp13 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum613) VAL=0.9 CROSS=LAST
.meas tran tp14 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum614) VAL=0.9 CROSS=LAST
.meas tran tp15 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum615) VAL=0.9 CROSS=LAST
.meas tran tp16 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum616) VAL=0.9 CROSS=LAST
.meas tran tp17 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum617) VAL=0.9 CROSS=LAST
.meas tran tp18 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum618) VAL=0.9 CROSS=LAST
.meas tran tp19 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum619) VAL=0.9 CROSS=LAST
.meas tran tp20 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum620) VAL=0.9 CROSS=LAST
.meas tran tp21 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum621) VAL=0.9 CROSS=LAST
.meas tran tp22 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum622) VAL=0.9 CROSS=LAST
.meas tran tp23 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum623) VAL=0.9 CROSS=LAST
.meas tran tp24 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum624) VAL=0.9 CROSS=LAST
.meas tran tp25 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum625) VAL=0.9 CROSS=LAST
.meas tran tp26 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum626) VAL=0.9 CROSS=LAST
.meas tran tp27 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum627) VAL=0.9 CROSS=LAST
.meas tran tp28 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum628) VAL=0.9 CROSS=LAST
.meas tran tp29 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum629) VAL=0.9 CROSS=LAST
.meas tran tp30 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum630) VAL=0.9 CROSS=LAST
.meas tran tp31 TRIG v(e0) VAL=0.9 RISE=1 TARG v(sum631) VAL=0.9 CROSS=LAST
.end
