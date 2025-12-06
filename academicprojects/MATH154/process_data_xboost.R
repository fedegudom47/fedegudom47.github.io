library(tidyverse)
library(educationdata)
library(xgboost)

# --- 1. FILE LOADING ---
admin_enrollment <- read_csv("admin_enrollment_trimmed.csv")
inst_info <- read_csv("inst_info_trimmed.csv")
tuition <- read_csv("tuition_trimmed.csv")
grants <- read_csv("grants_trimmed.csv")
brand_colors <- read_csv("inst_lookup_with_brand_colors.csv") # <-- MUST BE ADDED

# a lookup table to go between unitid and institution name
inst_lookup <- get_education_data(
  level  = "college-university",
  source = "ipeds",
  topic  = "directory",
  filters = list(year = 2021)) |>
  select(unitid, inst_name) |>
  distinct()

# --- 2. DATA CLEANING & FEATURE ENGINEERING ---
admin_enrollment_clean <- admin_enrollment |>
  filter(sex == 99) # only sex total

# merge data sets
college <- admin_enrollment_clean |>
  left_join(inst_info, by = c("unitid", "year")) |>
  left_join(tuition, by = c("unitid", "year")) |>
  left_join(grants, by = c("unitid", "year"))

# remove duplicate rows and create key variables
college <- college |>
  distinct(unitid, year, .keep_all = TRUE) |>
  mutate(yield = number_enrolled_total / number_admitted,
         admit_rate = number_admitted / number_applied) |>
  filter(!is.na(yield), admit_rate > 0, yield <= 1)

# clean fips and other duplicates/names
college <- college |>
  mutate(fips = fips.y) |>
  select(-fips.x, -fips.y, -fips.x.x, -fips.y.y) |>
  mutate(fips = as.factor(fips)) |>
  rename(level_of_study = level_of_study.x,
         tuition_type = tuition_type.x) |>
  select(-level_of_study.y, -tuition_type.y)

# create the training data frame
boost_model <- college |>
  select(
    yield, admit_rate, number_applied, number_admitted,
    number_enrolled_total, tuition_ft, fees_ft, net_price,
    fips, sector = primary_public_control, calendar_system,
    masters_offered, religious_affiliation, member_ncaa,
    member_conf_football, member_conf_basketball
  ) %>%
  mutate(
    across(where(is.character), as.factor),
    across(where(is.logical), as.factor),
    across(where(is.factor), as.factor)
  ) |>
  drop_na()

# --- 3. MODEL TRAINING & PREP ---

# convert all features to numeric matrix, dummy encode factors
X <- model.matrix(yield ~ . - 1, data = boost_model)
y <- boost_model$yield

# split train/test (only training data is needed for final model fit)
set.seed(123)
train_idx <- sample(seq_len(nrow(X)), 0.8 * nrow(X))
dtrain <- xgb.DMatrix(data = X[train_idx, ], label = y[train_idx])

# train final model (using hardcoded best params)
final_model <- xgb.train(
  params = list(
    objective = "reg:squarederror",
    eta = 0.05,
    max_depth = 6,
    subsample = 0.8,
    colsample_bytree = 0.8
  ),
  data = dtrain,
  nrounds = 1000,
  verbose = 0 # Silent training
)

# --- 4. PREDICT ALL DATA AND SAVE ---

# You must redefine boost_model_with_ids and X_all to predict ALL rows

# 4a. Create boost_model_with_ids dataframe (needed for inst_name lookup)
boost_model_with_ids <- college |>
  left_join(inst_lookup, by = "unitid") |>
  select(
    unitid, inst_name, year, yield, admit_rate, number_applied, number_admitted,
    number_enrolled_total, tuition_ft, fees_ft, net_price,
    fips, sector = primary_public_control, calendar_system,
    masters_offered, religious_affiliation, member_ncaa,
    member_conf_football, member_conf_basketball
  ) |>
  mutate(
    across(where(is.character), as.factor),
    across(where(is.logical), as.factor),
    across(where(is.factor), as.factor)
  ) |>
  drop_na()

# 4b. Create full prediction matrix (X_all)
new_pred_data <- boost_model_with_ids |> select(-unitid, -inst_name, -year)
tmp_bind <- bind_rows(boost_model, new_pred_data)
X_bind <- model.matrix(yield ~ . - 1, data = tmp_bind)
n_train <- nrow(boost_model)
X_all <- X_bind[(n_train + 1):nrow(X_bind), , drop = FALSE]

# 4c. Run prediction on ALL rows
dall <- xgb.DMatrix(data = X_all)
pred_all <- as.numeric(predict(final_model, dall))

# 4d. Combine predictions and save
pred_df <- boost_model_with_ids |>
  mutate(pred_yield = pred_all)

# FINAL SAVE STEPS
saveRDS(pred_df, "app_data.rds")        # The full data with predictions
saveRDS(brand_colors, "colors.rds")     # The colors lookup table
