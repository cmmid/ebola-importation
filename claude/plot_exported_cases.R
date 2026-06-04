#!/usr/bin/env Rscript
# plot_exported_cases.R
# -----------------------------------------------------------------------------
# Test that ebola_cases_long.csv is usable for analysis by producing:
#   (1) a choropleth world map  - countries coloured by number of imported cases
#   (2) a stacked bar time series - x = year, fill = country, count of cases
#
# "Exported case" here = a case treated in a European / North American country
# that was imported across a border (infected abroad, treated in the dataset's
# destination country). The destination = `country_treatment`. By default the
# map/series count ALL cases in the dataset by destination; set
# IMPORTED_ONLY <- TRUE below to restrict to genuine cross-border importations
# (country_infection != country_treatment).
#
# Usage:  Rscript plot_exported_cases.R
# Outputs: map_exported_cases.png , timeseries_exported_cases.png
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(maps)
  library(scales)
})

IMPORTED_ONLY <- FALSE   # TRUE = keep only cross-border importations

# --- locate input relative to this script -----------------------------------
this_dir <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else getwd()
}, error = function(e) getwd())
csv_path <- file.path(this_dir, "ebola_cases_long.csv")
if (!file.exists(csv_path)) csv_path <- "ebola_cases_long.csv"
message("Reading: ", csv_path)

long <- read.csv(csv_path, stringsAsFactors = FALSE)

# --- long (EAV) -> wide: one row per CaseID ----------------------------------
wide <- long %>%
  select(CaseID, Variable, Value) %>%
  distinct(CaseID, Variable, .keep_all = TRUE) %>%
  pivot_wider(names_from = Variable, values_from = Value)

# --- clean year: take the first 4-digit year mentioned -----------------------
wide <- wide %>%
  mutate(year_num = as.integer(sub(".*?((18|19|20)\\d{2}).*", "\\1", year)))

# --- destination country (where the imported case was treated) ---------------
# Recode dataset names -> names used by the `maps` world database, so the join
# to the choropleth polygons succeeds. Most already match.
map_name <- c(
  "UK"                               = "UK",
  "USA"                              = "USA",
  "Cote d'Ivoire"                    = "Ivory Coast",
  "Côte d'Ivoire"                    = "Ivory Coast",
  "Democratic Republic of the Congo" = "Democratic Republic of the Congo"
)
recode_country <- function(x) {
  x <- trimws(x)
  ifelse(x %in% names(map_name), map_name[x], x)
}

wide <- wide %>%
  mutate(dest = recode_country(country_treatment))

# --- optional: restrict to genuine cross-border importations -----------------
cases <- wide
if (IMPORTED_ONLY) {
  cases <- cases %>%
    filter(!is.na(country_infection),
           trimws(country_infection) != "None",
           recode_country(country_infection) != dest)
}

cat(sprintf("Cases in scope: %d (of %d total)\n", nrow(cases), nrow(wide)))

# =============================================================================
# (1) CHOROPLETH MAP
# =============================================================================
by_country <- cases %>%
  filter(!is.na(dest), dest != "None") %>%
  count(dest, name = "n_cases")

cat("Cases by destination country:\n")
print(by_country %>% arrange(desc(n_cases)), row.names = FALSE)

world <- map_data("world")

# sanity-check that every destination matched a map polygon
unmatched <- setdiff(by_country$dest, unique(world$region))
if (length(unmatched))
  warning("Destinations not found in map polygons: ",
          paste(unmatched, collapse = ", "))

world_counts <- world %>%
  left_join(by_country, by = c("region" = "dest"))

# Manual label anchors: a representative point inside each country. Manual
# (rather than polygon centroids) so the tight Europe cluster gets sensible
# starting points; ggrepel then nudges overlapping labels apart with leaders.
anchors <- tribble(
  ~dest,          ~lon,   ~lat,
  "USA",          -98.0,  39.0,
  "UK",            -2.0,  53.0,
  "Germany",       10.5,  51.0,
  "Spain",         -3.5,  40.0,
  "France",         2.5,  47.0,
  "Italy",         12.5,  42.5,
  "Switzerland",    8.2,  46.8,
  "Norway",         9.0,  61.0,
  "Russia",        45.0,  56.0
)
labels <- by_country %>% left_join(anchors, by = "dest")
missing_anchor <- labels %>% filter(is.na(lon))
if (nrow(missing_anchor))
  warning("No label anchor for: ", paste(missing_anchor$dest, collapse = ", "))

map_plot <- ggplot() +
  geom_polygon(data = world_counts,
               aes(long, lat, group = group, fill = n_cases),
               colour = "grey70", linewidth = 0.1) +
  geom_text(data = labels,
            aes(lon, lat, label = n_cases),
            size = 2.6, fontface = "bold", colour = "grey15") +
  coord_quickmap(xlim = c(-130, 60), ylim = c(20, 75)) +  # focus Europe + N. America
  scale_fill_viridis_c(option = "plasma", direction = -1,
                       na.value = "grey92",
                       breaks = pretty_breaks(),
                       name = "Imported\ncases") +
  labs(title = "Imported Ebola cases by country of treatment, 1976-2026",
       subtitle = sprintf("%d cases across %d countries",
                          sum(by_country$n_cases), nrow(by_country)),
       x = NULL, y = NULL) +
  theme_minimal(base_size = 12) +
  theme(panel.grid = element_blank(),
        axis.text = element_blank(),
        axis.ticks = element_blank())

ggsave(file.path(this_dir, "map_exported_cases.png"),
       map_plot, width = 11, height = 6, dpi = 150)
message("Wrote map_exported_cases.png")

# =============================================================================
# (2) STACKED-BAR TIME SERIES
# =============================================================================
ts <- cases %>%
  filter(!is.na(year_num), !is.na(country_treatment)) %>%
  mutate(country = trimws(country_treatment)) %>%
  count(year_num, country, name = "n_cases")

ts_plot <- ggplot(ts, aes(x = year_num, y = n_cases, fill = country)) +
  geom_col(width = 0.9, colour = "white", linewidth = 0.2) +
  scale_x_continuous(breaks = seq(1976, 2026, by = 2),
                     minor_breaks = seq(1976, 2026, by = 1),
                     limits = c(1975, 2027), expand = expansion(0)) +
  scale_y_continuous(breaks = pretty_breaks(), expand = expansion(c(0, 0.05))) +
  scale_fill_brewer(palette = "Set3", name = "Country of\ntreatment") +
  labs(title = "Imported Ebola cases by year and country of treatment",
       subtitle = "1976-2026, stacked by destination country",
       x = "Year", y = "Number of cases") +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(this_dir, "timeseries_exported_cases.png"),
       ts_plot, width = 11, height = 6, dpi = 150)
message("Wrote timeseries_exported_cases.png")

message("Done.")
