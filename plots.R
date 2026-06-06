library(data.table)
library(readxl)

ex = read_excel("./manual/Ebola cases imported into Europe.xlsx", sheet = 1, range = "A1:AH30") |>
    as.data.table()


cases = ex[Include == "Yes"]

## ---- Global choropleth: cases by country of treatment -----------------------

# Case counts by destination; recode names to match maps::map_data("world")
counts = cases[!is.na(`Imported to`), .(N = .N), by = .(region = `Imported to`)]
counts[region == "US", region := "USA"]

world = as.data.table(map_data("world"))
world = merge(world, counts, by = "region", all.x = TRUE)
setorder(world, order)   # restore polygon point order after the merge

map_plot = ggplot(world, aes(long, lat, group = group, fill = N)) +
    geom_polygon(colour = "grey70", linewidth = 0.1) +
    scale_fill_viridis_c(name = "Cases", na.value = "grey92") +
    coord_quickmap(xlim = c(-120, 32), ylim = c(25, 72)) +
    labs(title = "Imported Ebola cases by country of treatment") +
    theme_void()

ggsave("map_cases.png", map_plot, width = 11, height = 6, dpi = 150)

## ---- Age / sex pyramid ------------------------------------------------------

pyr_dat = cases[Sex %in% c("Male", "Female") & Age != "Unclear" & !is.na(Age)]
pyr_dat[, age_num := as.numeric(Age)]
pyr_dat = pyr_dat[!is.na(age_num)]
pyr_dat[, age_grp := cut(age_num, breaks = seq(20, 80, by = 10), right = FALSE,
                         labels = c("20-29", "30-39", "40-49", "50-59", "60-69", "70-79"))]

pyr = pyr_dat[, .(N = .N), by = .(age_grp, Sex)]
pyr[Sex == "Male", N := -N]   # males drawn to the left

pyramid_plot = ggplot(pyr, aes(age_grp, N, fill = Sex)) +
    geom_col(width = 0.9) +
    coord_flip() +
    scale_y_continuous(labels = function(x) abs(x), limits = c(-9, 9), breaks = seq(-6, 6, 2)) +
    labs(x = "Age group", y = "Cases",
         title = "Age and sex distribution") +
    theme_minimal()

ggsave("pyramid_age_sex.png", pyramid_plot, width = 7, height = 5, dpi = 150)

all_together = cowplot::plot_grid(map_plot, pyramid_plot, rel_widths = c(2, 1), nows = 1, labels = c("a", "b"))

ggsave("fig1.pdf", all_together, width = 12, height = 6, dpi = 150)
