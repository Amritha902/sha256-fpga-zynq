# Literature tracker

| File | What |
|---|---|
| `SHA256_Literature_Tracker.xlsx` | 44 entries: author, venue, impact factor, problem, what they did, main achievement, gap, how our work affects them, relevance and threat scores. Includes a **Novelty verdict** sheet. |
| `papers.csv` | Same table, readable on GitHub |
| `build_tracker.py` | Source of truth. Edit the `PAPERS` list, then run `python3 literature/build_tracker.py` |
| `pdfs/` | PDF store. `pdfs/download_pdfs.sh` fetches the 16 open-access ones |

## Getting the PDFs

The cloud session that built this could not reach the publisher hosts, so `pdfs/` holds no PDFs yet. To fill it:

```bash
literature/pdfs/download_pdfs.sh      # 16 open-access PDFs
git add literature/pdfs/*.pdf && git commit -m "Add open-access PDFs" && git push
```

Paywalled entries (marked `Paywalled` in the PDF column): download them through the VIT library or IEEE Xplore login and save them in `pdfs/` as `<ID>_<FirstAuthor>_<Year>.pdf`.

## Novelty verdict, one line each

- **Config C (two-message interleave):** dead. Helion 2010, IBM US20250070957A1, **SHARMONY (TCHES 2026), which adds a "duet" mode for two independent SHA-256 streams**, and Gueron & Krasnov 2012.
- **Config D (unroll + pipeline):** dead. McEvoy 2006, Gamgam 2023.
- **Operand reordering as a technique:** dead. Chaves 2006, **Yao et al. (Computer Journal 2025)**, and **Intel SHA256RNDS2**, which pre-adds W+K for 2 rounds.
- **Still standing:** the controlled re-test of Suhaili & Julai on Xilinx, and the *measured effect* of operand order on the unrolling verdict (0.500 vs 0.680 against a pre-registered threshold). Our search found no paper that measures this.
- **Scores:** patent 1/10 · research today 4/10 · after the four Vivado runs 6/10.

**New since the survey:** SHARMONY (P17), Yao et al. (P04), Intel SHA-NI (X04), Trident (P25). Cite P17 and P04 in the survey, or a reviewer will.
