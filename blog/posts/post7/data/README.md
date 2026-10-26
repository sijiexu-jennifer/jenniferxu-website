# Data directory

`code/analysis.py` creates both subdirectories:

- `raw/` contains exact CSV responses downloaded from the three FRED series endpoints.
- `derived/us_macro_monthly.csv` contains the date, CPI, unemployment rate, federal funds rate, calculated 12-month inflation rate, and period label used in the figure.

No data are entered or edited manually. FRED observations can be revised, so rerunning the script later may produce slightly different endpoint values.
