# Existing MELD aggregate results

`meld_eval.json` is an unchanged copy of the existing aggregate benchmark output
from the demo engine's `probe_cache/service/meld_eval.json`. It contains metrics,
not raw recordings or participant journals. This packaging task did not rerun
the model evaluation. The file must not be presented as app-user study results.

Source methods were inspected in the external dataset workspace:

- `scripts/modeling/train_prod.py`: production training on train/validation rows;
  the MELD test was excluded.
- `scripts/modeling/eval_meld.py`: official MELD test, paired available-modality
  comparisons and dialogue-cluster bootstrap.
- `docs/PREREG_meld_run.md`: frozen-test evaluation plan.

Under `ref_mosei`, the fixed reference normalization used by the demo yields
seven-class macro-F1 T=0.265785, TV=0.283435 and ATV=0.269395. The reported paired
interval for ATV minus T includes zero; do not claim an established multimodal
advantage. Under `own_stats`, normalization statistics are estimated from the
MELD test inputs themselves. This is transductive analysis, not a deployed
unseen-user calibration result. Keep these conditions separate.

Before publication, archive the full evaluation code and dependency/data-access
instructions, verify model/split lineage, reproduce these aggregates and report
limitations. Public benchmarks do not establish self-care benefit or dependable
crisis detection. Do not tune on this spent test and relabel it as untouched.
