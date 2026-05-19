# Manual Test Matrix

Cross-axis verification before tagging a stable release. Beta releases can
ship covering just the bold row.

| # | Mac chip       | macOS    | Displays  | SIP | Notes               |
|---|----------------|----------|-----------|-----|---------------------|
| 1 | **Apple M1**   | 26.4     | Built-in  | On  | **Reference target** |
| 2 | Apple M1       | 26.4     | + 4K ext. | On  | Multi-display (V53) |
| 3 | Apple M1       | 26.5+    | Built-in  | On  | Forward compat      |
| 4 | Apple M2/M3/M4 | 26.4     | Built-in  | On  | Newer VT silicon    |
| 5 | Intel + T2     | 26.4     | Built-in  | On  | VT software path    |
| 6 | Apple M1       | 26.4     | Built-in  | Off | SIP-disabled        |

Run `docs/INTEGRATION-TEST.md` start to finish on each row. Record pass/fail per step.

## Result table (fill in for each release)

| # | T18.1 First-run | T18.2 Import | T18.3 Apply | T18.4 Lock/unlock | T18.5 Re-pull | T18.6 Remove | T18.7 Uninstall |
|---|-----------------|--------------|-------------|-------------------|---------------|--------------|-----------------|
| 1 |                 |              |             |                   |               |              |                 |
| 2 |                 |              |             |                   |               |              |                 |
| 3 |                 |              |             |                   |               |              |                 |
| 4 |                 |              |             |                   |               |              |                 |
| 5 |                 |              |             |                   |               |              |                 |
| 6 |                 |              |             |                   |               |              |                 |
