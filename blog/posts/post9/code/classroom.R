# Run from blog/posts/post9 (or the extracted replication project root).
# Read only numeric portfolio columns; preserve the source workbook unchanged.
suppressPackageStartupMessages({library(readxl);library(dplyr);library(readr);library(stringr)})
d <- read_excel('data/raw/classroom_results.xlsx') |>
  transmute(portfolio1=as.numeric(portfolio1),portfolio2=as.numeric(portfolio2))
x <- d |> filter(is.finite(portfolio1),is.finite(portfolio2))
stopifnot(nrow(x)>1)
stats <- tibble(teams=nrow(x),mean_without=mean(x$portfolio1),mean_with=mean(x$portfolio2),mean_difference=mean(x$portfolio2-x$portfolio1),analysis_ahead=sum(x$portfolio2>x$portfolio1),correlation=cor(x$portfolio1,x$portfolio2))
write_csv(x,'data/processed/classroom_pairs.csv')
write_csv(stats,'results/classroom_summary.csv')
money <- function(v) formatC(v,format='f',digits=2,big.mark=',')
paragraph <- sprintf('The newly supplied class results broaden that lesson. Across **%d teams**, the mean final value was **$%s** without analysis and **$%s** with analysis. Analysis finished ahead for **%d of %d teams**; its mean advantage was **$%s**. Our group therefore underperformed the broader classroom pattern. These descriptive comparisons do not isolate the effect of gradient boosting: the result sheet does not identify each team’s method or establish randomized portfolio assignment.',stats$teams,money(stats$mean_without),money(stats$mean_with),stats$analysis_ahead,stats$teams,money(stats$mean_difference))
writeLines(paragraph,'results/classroom_summary.txt')
if(file.exists('index.qmd')) {
 q <- read_file('index.qmd')
 q <- str_replace(q,regex('<!-- classroom-summary:start -->.*?<!-- classroom-summary:end -->',dotall=TRUE),function(m) paste0('<!-- classroom-summary:start -->\n',paragraph,'\n<!-- classroom-summary:end -->'))
 write_file(q,'index.qmd')
}
print(stats)
