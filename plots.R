library(data.table)
library(readxl)

ex = read_excel("./manual/Ebola cases imported into Europe.xlsx", sheet = 1, range = "A1:AH30") |>
    as.data.table()
