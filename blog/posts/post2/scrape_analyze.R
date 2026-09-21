library(rvest)
library(dplyr)
library(purrr)
library(stringr)
library(readr)
library(tibble)
library(ggplot2)
library(scales)

base_url <- "https://books.toscrape.com/"
dir.create("data", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)

rating_key <- c(
  One = 1L, Two = 2L, Three = 3L, Four = 4L, Five = 5L
)

read_html_safely <- function(url, attempts = 3L) {
  for (attempt in seq_len(attempts)) {
    page <- tryCatch(read_html(url), error = identity)
    if (!inherits(page, "error")) return(page)
    if (attempt < attempts) Sys.sleep(2 * attempt)
  }
  stop("Could not read ", url, " after ", attempts, " attempts: ", page$message)
}

scrape_listing_page <- function(url, category) {
  page <- read_html_safely(url)
  cards <- html_elements(page, "article.product_pod")

  books <- tibble(
    title = html_attr(html_element(cards, "h3 a"), "title"),
    price_gbp = parse_number(html_text2(html_element(cards, ".price_color"))),
    rating_word = str_remove(
      html_attr(html_element(cards, "p.star-rating"), "class"),
      "star-rating\\s+"
    ),
    in_stock = str_detect(
      html_text2(html_element(cards, ".availability")),
      regex("in stock", ignore_case = TRUE)
    ),
    product_url = url_absolute(
      html_attr(html_element(cards, "h3 a"), "href"),
      url
    ),
    category = category
  ) |>
    mutate(rating = unname(rating_key[rating_word])) |>
    select(title, category, price_gbp, rating, in_stock, product_url)

  next_href <- html_attr(html_element(page, "li.next a"), "href")
  next_url <- if (is.na(next_href)) NA_character_ else url_absolute(next_href, url)

  list(books = books, next_url = next_url)
}

scrape_category <- function(category, first_url, delay = 0.35) {
  pages <- list()
  current_url <- first_url
  page_number <- 1L

  while (!is.na(current_url)) {
    message("Scraping ", category, ", page ", page_number)
    result <- scrape_listing_page(current_url, category)
    pages[[page_number]] <- result$books
    current_url <- result$next_url
    page_number <- page_number + 1L
    Sys.sleep(delay)
  }

  bind_rows(pages)
}

home <- read_html_safely(base_url)
category_nodes <- html_elements(home, ".side_categories ul li ul li a")
categories <- tibble(
  category = html_text2(category_nodes),
  category_url = url_absolute(html_attr(category_nodes, "href"), base_url)
)

books <- map2_dfr(categories$category, categories$category_url, scrape_category) |>
  distinct(product_url, .keep_all = TRUE) |>
  mutate(
    budget_quality = rating >= 4 & price_gbp <= 20,
    value_score = rating / price_gbp
  )

stopifnot(nrow(books) == 1000, !anyNA(books$price_gbp), !anyNA(books$rating))
write_csv(books, "data/books.csv")

category_summary <- books |>
  group_by(category) |>
  summarise(
    books = n(),
    median_price_gbp = median(price_gbp),
    average_rating = mean(rating),
    budget_quality_books = sum(budget_quality),
    budget_quality_share = mean(budget_quality),
    .groups = "drop"
  ) |>
  filter(books >= 10) |>
  arrange(desc(budget_quality_share), median_price_gbp)

write_csv(category_summary, "data/category_summary.csv")

top_categories <- category_summary |>
  slice_max(budget_quality_share, n = 10, with_ties = FALSE) |>
  mutate(category = reorder(category, budget_quality_share))

value_plot <- ggplot(
  top_categories,
  aes(x = budget_quality_share, y = category)
) +
  geom_col(fill = "#2A6F97", width = 0.7) +
  geom_text(
    aes(label = percent(budget_quality_share, accuracy = 1)),
    hjust = -0.12,
    size = 3.5
  ) +
  scale_x_continuous(
    labels = percent,
    limits = c(0, max(top_categories$budget_quality_share) * 1.18),
    expand = expansion(mult = c(0, 0.02))
  ) +
  labs(
    title = "Where a £20 budget buys the most highly rated choices",
    subtitle = "Categories with at least 10 books; highly rated means 4–5 stars",
    x = "Share of category priced at £20 or less and rated 4–5 stars",
    y = NULL,
    caption = "Source: Books to Scrape (fictional catalog)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.major.y = element_blank(),
    plot.title = element_text(face = "bold"),
    plot.caption = element_text(colour = "grey40")
  )

ggsave("figures/category_value.png", value_plot, width = 8, height = 5.5, dpi = 300)

recommendations <- books |>
  filter(in_stock, rating >= 4, price_gbp <= 20) |>
  arrange(desc(rating), price_gbp, title) |>
  select(title, category, price_gbp, rating, product_url) |>
  slice_head(n = 10)

write_csv(recommendations, "data/recommendations.csv")

print(category_summary, n = 15)
print(recommendations, n = 10)
