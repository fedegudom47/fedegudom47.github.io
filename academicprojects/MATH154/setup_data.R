# setup_data.R
library(tidyverse)

# loading data
grants           <- read_csv("grants_trimmed.csv")
inst_info        <- read_csv("inst_info_trimmed.csv")
tuition          <- read_csv("tuition_trimmed.csv")
admin_enrollment <- read_csv("admin_enrollment_trimmed.csv")

# peforming the cleaning/merging 
admin_enrollment_clean <- admin_enrollment |> filter(sex == 99)

college <- admin_enrollment_clean |>
  left_join(inst_info, by = c("unitid", "year")) |>
  left_join(tuition,   by = c("unitid", "year")) |>
  left_join(grants,    by = c("unitid", "year")) |>
  distinct(unitid, year, .keep_all = TRUE) |>
  mutate(
    yield      = number_enrolled_total / number_admitted,
    admit_rate = number_admitted / number_applied
  ) |>
  filter(!is.na(yield), admit_rate > 0, yield <= 1) |>
  mutate(fips = as.factor(fips.y)) |>
  select(-fips.x, -fips.y, -fips.x.x, -fips.y.y) |>
  rename(
    level_of_study = level_of_study.x,
    tuition_type   = tuition_type.x
  ) |>
  select(-level_of_study.y, -tuition_type.y)

# saving clean file
saveRDS(college, "college_clean.rds")

