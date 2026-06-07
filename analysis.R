library(data.table)
library(readxl)
library(ggplot2)

# Load exported cases data
ex = read_excel("./manual/Ebola cases imported into Europe.xlsx", sheet = 1, range = "A1:AH30") |>
    as.data.table()

cases = ex[Include == "Yes"]


## Global exported case map

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


## Age / sex pyramid

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

ggsave("fig1.pdf", all_together, width = 12, height = 6, useDingbats = FALSE)


## Temporal evolution

# Source of data: https://data.humdata.org/dataset/ebola-cases-2014
te = fread("./ebola_data_db_format.csv")
te1 = te[Country %like% "Guinea" | Country %like% "Liberia" | Country %like% "Sierra Leone"]
te1 = te1[Indicator == "Cumulative number of confirmed Ebola cases"]
te1 = te1[order(Date, Country)]

te2 = te[Country %like% "Guinea" | Country %like% "Liberia" | Country %like% "Sierra Leone"]
te2 = te2[Indicator == "Cumulative number of confirmed, probable and suspected Ebola cases"]
te2 = te2[order(Date, Country)]

crude_plot = function(te1, country, first_span = 28)
{
    te_crude = te1[Country == country]
    te_crude[, time_span := c(first_span, diff(Date))]
    te_crude[, case_diff := diff(c(0, value))]
    te_crude[, case_rate := case_diff / time_span]
    
    ggplot(te_crude) +
        geom_line(aes(x = Date, y = case_rate))
}
crude_plot(te1, "Sierra Leone")
crude_plot(te2, "Sierra Leone")
# te2 best matches cases reported by CDC Ebola history.

# Now need to bring in earlier data from https://github.com/cmrivers/ebola
ex_gn = fread("./guinea.csv")
ex_gn = ex_gn[`Case definition` == "Confirmed and probable case total" & `Ebola data source` == "Patient database", 
    .(epiweek = lubridate::dmy(`Epi week`), value = Numeric)][order(epiweek)]

ex_lb = fread("./liberia.csv")
ex_lb = ex_lb[`Case definition` == "Confirmed and probable case total" & `Ebola data source` == "Patient database", 
    .(epiweek = lubridate::dmy(`Epi week`), value = Numeric)][order(epiweek)]

ex_sl = fread("./sierraleone.csv")
ex_sl = ex_sl[`Case definition` == "Confirmed and probable case total" & `Ebola data source` == "Patient database", 
    .(epiweek = lubridate::dmy(`Epi week`), value = Numeric)][order(epiweek)]

# Compare incidence at ends
te2[, min(Date)] # 2014-08-29
te2[Date == min(Date),] # Guinea 648, Liberia 1378, SL 1026
ex_gn[epiweek < "2014-08-24" & !is.na(value), cumsum(value)] # 553
ex_lb[epiweek < "2014-08-24" & !is.na(value), cumsum(value)] # 905
ex_sl[epiweek < "2014-08-24" & !is.na(value), cumsum(value)] # 1030 -- close enough...
ex_gn[is.na(value), value := 0]
ex_lb[is.na(value), value := 0]
ex_sl[is.na(value), value := 0]

te2[, Indicator := NULL]
te2 = rbind(
    te2[Date >= "2014-08-24"],
    ex_gn[epiweek < "2014-08-24", .(Country = "Guinea", Date = epiweek, value = cumsum(value))],
    ex_lb[epiweek < "2014-08-24", .(Country = "Liberia", Date = epiweek, value = cumsum(value))],
    ex_sl[epiweek < "2014-08-24", .(Country = "Sierra Leone", Date = epiweek, value = cumsum(value))]
)
te2 = te2[order(Date, Country)]

# Get crude daily incidence
crude_incidence = function(te1, country, first_span = 28)
{
    te_crude = te1[Country == country]
    te_crude[, time_span := c(first_span, diff(Date))]
    te_crude[, case_diff := diff(c(0, value))]
    te_crude[, case_rate := case_diff / time_span]
    
    te_crude[1, Date := Date - first_span]
    te_crude[-1, Date := Date - time_span]
    af = approxfun(as.numeric(te_crude$Date), te_crude$case_rate, method = "constant")
    new_dates = seq(te_crude[1, as.numeric(Date)], te_crude[.N, as.numeric(Date)], 1)
    new_incidence = data.table(country = country, date = as.Date(new_dates), cases = af(new_dates))
    
    new_incidence = rbind(
        data.table(country = country, 
            date = as.Date((new_dates[1] - first_span):(new_dates[1] - 1)),
            cases = 0),
        new_incidence
    )
    
    return (new_incidence)
}

crude_plot(te2, "Sierra Leone")
crude_plot(te2, "Guinea")
crude_plot(te2, "Liberia")

# Smooth out case incidence "per day"
inc_sl = crude_incidence(te2, "Sierra Leone")
inc_gn = crude_incidence(te2, "Guinea")
inc_lb = crude_incidence(te2, "Liberia")

# Apply rolling-mean smoothing
inc_sl[, cases_smoothed := frollmean(cases, 28)]
inc_gn[, cases_smoothed := frollmean(cases, 28)]
inc_lb[, cases_smoothed := frollmean(cases, 28)]

inc = rbind(inc_sl, inc_lb, inc_gn) # by size...
inc[, country := factor(country, unique(country))]

# Get imported cases
cases2 = cases[`Exposure country` %in% c("Sierra Leone", "Liberia", "Guinea")]
cases2[, date := lubridate::dmy(`Confirmation date`)]
cases2[is.na(date), date := lubridate::dmy(`Arrival date`)]
cases2 = cases2[, .(country = `Exposure country`, date, medevac = factor(Medevac))]
cases2[, country := factor(country, c("Sierra Leone", "Liberia", "Guinea"))]

# Try plotting incidence
ggplot(inc) +
    geom_area(aes(x = date, y = cases_smoothed, fill = country), position = position_stack())
# better, but too noisy still. Try by epiweek.

# Amalgamate by epiweek
inc[, epiweek := lubridate::floor_date(date, "week", week_start = 1)] # monday start
inc_wk = inc[, .(cases = sum(cases_smoothed, na.rm = T)), by = .(country, epiweek)]

# Add incidence to case data for positioning
cases2[, epiweek := lubridate::floor_date(date, "week", week_start = 1)] # monday start
cases2 = merge(cases2, inc_wk[country == "Sierra Leone", .(cases_sl = cases, epiweek)], by = "epiweek", all.x = TRUE)
cases2 = merge(cases2, inc_wk[country == "Liberia", .(cases_lb = cases, epiweek)], by = "epiweek", all.x = TRUE)
cases2 = merge(cases2, inc_wk[country == "Guinea", .(cases_gn = cases, epiweek)], by = "epiweek", all.x = TRUE)

# Do positioning (watch for double cases)
cases2[is.na(cases_sl), cases_sl := 0]
cases2[is.na(cases_lb), cases_lb := 0]
cases2[is.na(cases_gn), cases_gn := 0]
cases2[country == "Guinea", y := cases_gn / 2]
cases2[country == "Liberia", y := cases_gn + cases_lb / 2]
cases2[country == "Sierra Leone", y := cases_gn + cases_lb + cases_sl / 2]

# Manually nudge double cases
nudge_y = 50
cases2[, y := pmax(nudge_y, y)]
for (r in 1:(nrow(cases2) - 1)) {
    ew = cases2[r, epiweek]
    yy = cases2[r, y]
    
    overlap = cases2[, which(epiweek == ew & abs(y - yy) < nudge_y)]
    if (length(overlap) > 2) {
        stop("More than 2 overlapping")
    } else if (length(overlap) == 2) {
        cases2[overlap[1], y := y + nudge_y / 2]
        cases2[overlap[2], y := y - nudge_y / 2]
    }
}

# Start in January 2014 (very small case density before Jan)
inc_wk = inc_wk[epiweek >= "2014-01-01"]

# Plot
timeline = ggplot(inc_wk) +
    geom_col(aes(x = epiweek, y = cases, fill = country), 
        colour = "black", linewidth = 0.1, position = position_stack(), width = 7) +
    geom_point(data = cases2, aes(x = epiweek, y = y, shape = medevac), size = 2.5) +
    geom_point(data = cases2, aes(x = epiweek, y = y, colour = country, shape = medevac)) +
    guides(colour = guide_none()) +
    theme_classic() +
    theme(legend.position = c(0.75, 0.75), axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)) +
    scale_x_date(date_breaks = "months", date_labels = "%b %Y", expand = expansion(c(0.01, 0))) +
    scale_y_continuous(expand = expansion(c(0, 0.02)), breaks = (1:8) * 200) +
    labs(x = NULL, y = "Confirmed, probable, and suspected cases by week", fill = "Country", colour = NULL, shape = "Medevac")

ggsave("fig2.pdf", timeline, width = 12, height = 5, useDingbats = FALSE)

## Poisson regression

# Analyse time-varying risk.
# Number of cases by epiweek and country
occurrence = cases2[, .N, by = .(epiweek, country)]
odata = merge(inc_wk, occurrence, by = c("country", "epiweek"), all.x = TRUE)
odata[is.na(N), N := 0]
odata = odata[order(epiweek, country)]

# Add properly scaled predictors
odata[, log_cases := log(pmax(0, cases))]
odata[, epiweek_n := as.numeric(epiweek - lubridate::ymd("2014-01-06")) / 7]

# Drop weeks with 0 or fewer cases (needed for offset to be meaningful)
odata[, sum(N)]
odata = odata[cases > 0]
odata[, sum(N)]

# Post peak indicator
odata[, post_peak := epiweek >= "2014-10-27"]


# Thoughts: could include a country level difference, but there are so
# few data points it doesn't seem worth doing.
fit = glm(N ~ offset(log_cases) + log_cases + 
        epiweek_n, family = quasipoisson, data = odata)
# plot(fit)
summary(fit)

# Call:
# glm(formula = N ~ offset(log_cases) + log_cases + epiweek_n, 
#     family = quasipoisson, data = odata)
# 
# Coefficients:
#             Estimate Std. Error t value Pr(>|t|)    
# (Intercept) -4.88342    1.03276  -4.729 3.81e-06 ***
# log_cases   -0.02122    0.19366  -0.110  0.91284    
# epiweek_n   -0.04666    0.01791  -2.606  0.00973 ** 
# ---
# Signif. codes:  0 ‘***’ 0.001 ‘**’ 0.01 ‘*’ 0.05 ‘.’ 0.1 ‘ ’ 1
# 
# (Dispersion parameter for quasipoisson family taken to be 0.9063167)
# 
#     Null deviance: 92.815  on 248  degrees of freedom
# Residual deviance: 84.912  on 246  degrees of freedom
# AIC: NA
# 
# Number of Fisher Scoring iterations: 7

# Test: pre peak, post peak
fit = glm(N ~ offset(log_cases) + log_cases + 
        post_peak, family = quasipoisson, data = odata)
# plot(fit)
summary(fit)

# Call:
# glm(formula = N ~ offset(log_cases) + log_cases + post_peak, 
#     family = quasipoisson, data = odata)
# 
# Coefficients:
#                Estimate Std. Error t value Pr(>|t|)    
# (Intercept)   -6.367120   1.048386  -6.073 4.73e-09 ***
# log_cases     -0.002279   0.191997  -0.012 0.990540    
# post_peakTRUE -1.314123   0.380190  -3.456 0.000645 ***
# ---
# Signif. codes:  0 ‘***’ 0.001 ‘**’ 0.01 ‘*’ 0.05 ‘.’ 0.1 ‘ ’ 1
# 
# (Dispersion parameter for quasipoisson family taken to be 0.8086236)
# 
#     Null deviance: 92.815  on 248  degrees of freedom
# Residual deviance: 82.702  on 246  degrees of freedom
# AIC: NA
# 
# Number of Fisher Scoring iterations: 6

# Before/after comparison
odata[post_peak == FALSE, .(N = sum(N), cases = sum(cases))]
15/8842.349 * 1000
qgamma(c(0.025, 0.5, 0.975), shape = 15, rate = 8842.349) * 1000

odata[post_peak == TRUE, .(N = sum(N), cases = sum(cases))]
9/19750.64 * 1000
qgamma(c(0.025, 0.5, 0.975), shape = 9, rate = 19750.64) * 1000

# Fractional reduction
1 - 0.4556814/1.696382

# Autocorrelation tests to check for any AC related problems in estimators
library(sandwich)
library(lmtest)

fit = glm(N ~ offset(log_cases) + log_cases + epiweek_n,
          family = quasipoisson, data = odata)

odata[, pres := residuals(fit, type = "pearson")]

# ACF of residuals within each country (sorted by week)
par(mfrow = c(1, 3))
for (cc in levels(droplevels(odata$country))) {
    acf(odata[country == cc][order(epiweek), pres], main = cc)
}
# No clear clustering of exportation events.
# Residual autocorrelation was negligible by analysis of within-country ACF.

coeftest(fit, vcov = vcovPL(fit,
    cluster = ~country, order.by = ~epiweek_n, lag = 2))
coeftest(fit, vcov = vcovPL(fit,
    cluster = ~country, order.by = ~epiweek_n, lag = 4))
coeftest(fit, vcov = vcovPL(fit,
    cluster = ~country, order.by = ~epiweek_n, lag = 6))

# Time-trend inference was robust to Driscoll–Kraay panel-HAC 
# (heteroskedasticity- and autocorrelation-consistent) standard errors across 
# 2-6-week bandwidths.