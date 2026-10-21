# Submission checklist

## Final checks

- Confirm the author and date in `index.qmd`.
- Run `python3 code/analysis.py` to rebuild the PSID estimates and figures.
- Run `quarto render index.qmd` and inspect the webpage on both desktop and mobile widths.
- Confirm that both figures, the results table, folded code, and mathematical notation display correctly.

## Publish with the main website

This post already lives at `blog/posts/post6/` inside the Jennifer Xu website repository. From the website root, run:

```bash
quarto render
```

Then push the repository to GitHub. The blog listing automatically includes `posts/**/index.qmd`, so Blog 6 should appear without editing `blog/index.qmd`.

Submit both the published Blog 6 URL and the GitHub repository URL.

## Rubric cross-check

- The opening states the intergenerational-mobility question and why measurement matters.
- The tutorial explains the workflow for a reader with basic Python and SQL knowledge.
- Results are interpreted, limitations are explicit, and the article ends with a clear takeaway.
- The PSID data source, sample construction, limitations, and analysis date are documented.
- The repository separates code, data, figures, results, and publication files.
- One analysis script parses the official PSID files and regenerates all derived results.
- SQL inside Python matches records using individual and family identifiers.
- `SELECT`, `JOIN`, `GROUP BY`, conditional aggregation, and their purposes are explained.
- Parent and child income are constructed for single-year and multi-year specifications, and both IGEs are reported.
- The age-profile figure demonstrates life-cycle bias and the text explains why multi-year averages better represent long-run status.
