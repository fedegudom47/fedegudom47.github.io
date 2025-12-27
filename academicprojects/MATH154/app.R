library(shiny)
library(tidyverse)
library(bslib)
library(bsicons)
library(maps)
library(wesanderson)
library(scales)
library(plotly)
library(xgboost)
library(mapproj)

pred_df      <- readRDS("pred_df.rds")
year_choices <- readRDS("year_choices.rds")
inst_choices <- readRDS("inst_choices.rds")
brand_colors <- readRDS("colors.rds")
college <- readRDS("college_clean.rds")

# --- PREP DATA FOR "NICE PICTURES" TAB ----------------------------
inst_lookup <- read_csv("inst_lookup_base.csv") |> select(unitid, inst_name) |> distinct()

# --- For clustering work ---
clustered_set <- read_csv("./Clustering/df_clustered_set.csv")
pairwise_tables <- read_csv("./Clustering/pairwisetables.csv")
neighbor_stats <- read_csv("./Clustering/neighbor_stats.csv")
cluster_inst_choices <- sort(unique(clustered_set$inst_name))
var_metadata <- read_csv("./Clustering/variable_metadata.csv")


# aggregate by state/year
state_year <- college |>
  group_by(fips, year) |>
  summarise(
    mean_yield           = mean(yield, na.rm = TRUE),
    total_applications   = sum(number_applied, na.rm = TRUE),
    n_institutions       = n(),
    apps_per_institution = total_applications / n_institutions,
    mean_admit_rate      = mean(admit_rate, na.rm = TRUE),
    .groups = "drop"
  )

# FIPS <-> state names
state_fips <- tibble(
  state_name = tolower(state.name),
  fips = factor(c(
    1,  2,  4,  5,  6,  8,  9, 10, 12, 13,
    15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
    25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
    35, 36, 37, 38, 39, 40, 41, 42, 44, 45,
    46, 47, 48, 49, 50, 51, 53, 54, 55, 56
  ))
)

state_year_named <- state_year |>
  inner_join(state_fips, by = "fips")

states_map <- map_data("state")

# global ranges for slider & legends
map_year_min <- min(state_year_named$year, na.rm = TRUE)
map_year_max <- max(state_year_named$year, na.rm = TRUE)

yield_min  <- min(state_year_named$mean_yield, na.rm = TRUE)
yield_max  <- max(state_year_named$mean_yield, na.rm = TRUE)

apps_min   <- min(state_year_named$apps_per_institution, na.rm = TRUE)
apps_max   <- max(state_year_named$apps_per_institution, na.rm = TRUE)

admit_min  <- min(state_year_named$mean_admit_rate, na.rm = TRUE)
admit_max  <- max(state_year_named$mean_admit_rate, na.rm = TRUE)

# ----- Prep data for map
map_data_prepared <- clustered_set |>
  left_join(neighbor_stats, by = "inst_name") |>
  filter(!is.na(latitude), !is.na(longitude)) |>
  mutate(
    .pred_cluster = as.factor(.pred_cluster),
    #hover
    hover_text = paste0(
      "<b>", inst_name, "</b><br>",
      "Cluster: ", .pred_cluster, "<br>",
      "Admit Rate: ", percent(admit_rate, accuracy = 0.1), "<br>",
      "Tuition: ", dollar(tuition_ft)
    )
  )

# map settings
g_map_settings <- list(
  scope = 'usa',
  projection = list(type = 'albers usa'),
  showlakes = TRUE,
  lakecolor = "#F5F5F5",
  paper_bgcolor = "aliceblue",
  plot_bgcolor = "aliceblue",
  bgcolor = '#F5F5F5'
)

# --- General UI ---
ui <- navbarPage(
  "University Analytics",
  header = tags$head(withMathJax()),
  theme = bslib::bs_theme(
    bg = "#F5F5F5",
    fg = "#333333",
    primary = "#0072B2",
    secondary = "#E69F00",
    success = "#009E73",
    base_font = font_google("Inter"),
    code_font = font_google("JetBrains Mono"),
    bootswatch = "lux"
  ),
  
  tabPanel(
    "About",
    div(
      style = "padding: 20px; max-width: 800px; margin: auto; font-size: 16px;",
      
      
      HTML("
      <h1>Project Overview</h1>
      <p> Our University Analytics project uses machine learning to try to uncover patterns within U.S. higher education. Our
      project attempts to predict yield rate patterns for different universities and identify similar college groups, while identifying
      the differences between them. We have created a highly interactive applet where you can play with these questions. </p>

       <h4> Core Objectives & Questions Answered </h2>
       <p> This shiny application is structured around answering three main analytical questions:</p>
      <ul>
        <li> <em> Yield Rate Prediction & Patterns: </em> What is the predicted future enrollment rate (yield) for a specific institution in a
        given year, and how does this compare to its historical performance?</li>
        <li> <em> Institutional Segmentation: </em> Which universities are quantitatively similar based on resources, costs and other
        meaningful characteristics, how are these groups geographically distributed?</li>
        <li> <em> Cluster Characterization: </em> Which features - such as tuition, endowment, or study abroad opportunities - are
        the most significant drivers of difference between two selected university clusters?</li>
      </ul>

      <h4> Modeling Frameworks and Libraries </h4>

      <table>
    <thead>
        <tr>
            <th>Model</th>
            <th>Application</th>
            <th>Libraries</th>
            <th>For?</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td><b>Gradient Boosting</b></td>
            <td>Yield Prediction</td>
            <td><code>xgboost</code></td>
            <td>Forecasts future yield rate by sequentially learning from the errors of previous weak learners.</td>
        </tr>
        <tr>
            <td><b>K-Means Clustering</b></td>
            <td>Segmentation</td>
            <td><code>tidymodels</code></td>
            <td>Grouped institutions based on feature similarity to identify similar university groups.</td>
        </tr>
        <tr>
            <td><b>Random Forest</b></td>
            <td>Cluster Characterisation</td>
            <td><code>tidymodels</code>, <code>vip</code></td>
            <td>Used for <b>supervised characterisation</b> by predicting cluster assignment to rank the variable importance between any two groups.</td>
        </tr>
    </tbody>
</table>

      <hr>

      <h2> Gradient Boosting Model </h2>
      <h4> Overview </h4>
      <p>
      Gradient Boosting works similarly to Random Forests in that it combines many decision trees to create a powerful predictive model.
      The key difference is that Gradient Boosting builds many small trees sequentially, with each tree learning from
      the errors of the previous one.
      </p>

      <p>
      First, a shallow tree is fit to the data and a loss function is computed. Rather than building the next tree from scratch,
      Gradient Boosting computes the negative gradient of the loss function with respect to the model’s current predictions (\\( \\hat{y} \\)).
      The negative gradient represents the direction of steepest error reduction, so the next tree is trained to approximate this quantity:
      </p>

      $$
      \\text{Next Tree} = T_m(x) \\approx -\\,\\frac{\\partial \\; \\text{Loss Function}}{\\partial \\; \\hat{y}}
      $$

      <p>
      Each new tree is added to the model with a small scaling factor (the learning rate) so that the model improves gradually:
      </p>

      $$
      F_{m}(x) = F_{m-1}(x) + \\eta T_m(x)
      $$

      <p>
      where \\(F_m(x)\\) is the current full model (with m trees), and \\(\\eta\\) is the learning rate. When we cross validatd to find the
      value of \\(\\eta\\), we ended up with a value of \\(\\eta = 0.05\\). If the learning rate is too small, the model will take too long to
      converge to the best solution, and if it is too large, it may miss the best solution entirely.
      </p>

      <p>
      By iteratively fitting these simple trees using the gradients of the loss function, Gradient Boosting produces a flexible model
      capable of capturing nonlinearities and interactions. In this project, boosting is particularly effective for modeling yield rates because
      of its ability to incorporate complex relationships between tuition, admissions patterns, institutional characteristics, and geographic variation.
      </p>

      <h4> Looking at Strong Predictors </h4>

     <div style='text-align: center; margin: 20px 0;'>
         <img src='Images/PredictorsRF2.jpeg' style='max-width: 100%; height: auto; border: 1px solid #ccc;'>
           <p style='color: #666; font-style: italic; margin-top: 5px;'>Random Forest Predictors</p>
          </div>

     <p>First we see that <code>Number admitted</code> is the most important predictors in determining yield rate. This makes sense given that,&nbsp;</p>
<p>$$\\text{yield rate} = \\frac{\\text{number students enrolled}}{\\text{number students admitted}}$$</p>
<p>so <code> Number admitted </code> gives us direct information about the yield rate. It might seem like cheating
to include the number of admitted students in the model, however
we feel that this model could be implemented by a college admissions officer trying to determine yield rate,
and being able to play with this value to understand how the number of admitted students affect these predictions.

<p> The next most important feature is <code> Full-time tuition</code>. Expense plays a huge part in students' choice of college and so it makes sense that the price tag would be an important predictor of yield. </p>

<code>Number applied</code>, and <code>Admission rate</code> tell us a similar stories. Elite institutions, (like the Ivy League schools for example), are highly selective, i.e. they will have many applications, and low admission rates.
Students accepted to these kinds of schools are likely to enroll because of their prestige, leading to high yield rates.
However, there are also likely instances of big state schools having a large number of applicants, but a lower yield which may be why <code>Admission rate</code> is not as strong a predictor as say, <code>Full-time tuition</code>.</p>

<p> <code>Fees</code> and <code>Net price</code> are also both important features, for the same reason as <code>Full-time tuition</code>.

<p><code>Basketball Conference Member</code> is likely a good predictor because it increases institutions visibility, as well as perceptions of student experience. These factors make universities with active sports programs more desirable to applicants,
and thus makes them more likely to enroll leading to higher yield rates. Small and under-resourced institutions are much less likely to have official basketball teams (among other sports),
and so this variable also helps differentiate between institution types.</p>
<p><code>Fees</code> and <code>Net price</code> are also both important features, for the same reason <code>Full-time tuition</code> is.</p>
<p>What about <code>fips 72</code>? Federal Information Processing System (FIPS) codes are numbers which uniquely identify geographic areas. The FIPS codes in this dataset correspond to states, so which state has code 72? It&apos;s actually Puerto Rico.
Puerto Rico&rsquo;s inclusion as a distinct predictor is because of its unique tuition structures, student mobility patterns, and institutional characteristics within IPEDS.
These factors allow the model to treat Puerto Rican institutions as an isolated enrollment ecosystem, which is why they have such strong predictive power relative to the other states.</p>
<p>The states with the next highest predictive power on yield rate are New York (<code>fips 36</code>) and California (<code>fips 6</code>).</p>
      <hr>

      <h2> Clustering & Characterisation </h2>

      <p>The primary goal of K-Means clustering is to segment universities into distinct, homogeneous groups (clusters) based on the input variables. </p>


      <h5 style='margin-top: 20px;'>Finding Optimal K: The Elbow Method</h5>
      <p>We defined the optimal number of groups (k=5) by observing the 'Total Within-Cluster Sum of Squares' (WSS) using the Elbow Method. The WSS measures the compactness of the clustering; lower WSS means data points are closer to their cluster center. We analysed the WSS curve over a number of cluster counts (k=1 to k=15). The 'elbow' point, where the marginal reduction in WSS
      sharply decreases, suggested that <em>k=5</em> provided the best trade-off between maximising inter-cluster distance and minimising intra-cluster variance.</p>

        <div style='text-align: center; margin: 20px 0;'>
         <img src='Images/elbow.jpeg' style='max-width: 100%; height: auto; border: 1px solid #ccc;'>
           <p style='color: #666; font-style: italic; margin-top: 5px;'>Total Within-Cluster Sum of Squares</p>
          </div>


      <h5 style='margin-top: 20px;'>Running K-means</h5>
      <p> After running K-means clustering, we decided to present the output to the viewer in the form of an interactive visualisation. This visualisation displays the distribution
      of schools in different clusters (encoded via colour) on a map of the United States. This plot is completely interactive, allowing the user to: </p>
      <ul style='list-style-type: none; padding-left: 0;'>
        <li> Select which cluster groups they want to see on the map (the ability to filter through these).</li>
        <li> An interactive tooltip upon hovering, displaying the school's admission rate and its tuition.</li>
        <li> The ability to zoom and pan in order to properly analyse schools that may overdraw on top of each other (if they are in similar geographic locations, as is the case of the 5Cs).</li>
        <li> Query a specific school. The user can search a school - it's dot will become larger and highlight (regardless of whether its cluster is selected). For said school, multiple details
        will be displayed, including common 'Stats', its 'Closest Peer within the Cluster', 'Furthest Peer within the Cluster', and its 'Closest Outsider'.
      </ul>

      <h5> What do we mean by 'Closest Peer within the Cluster', 'Furthest Peer within the Cluster', and 'Closest Outsider'?</h5>

      <p>The 'Closest Peer', 'Furthest Peer' and 'Closest Outsider' metrics available in the sidebar are derived from the <b>Euclidean Distance</b> between schools in the normalised, multi-dimensional feature space seen by the K-Means
      algorithm.
      They help contextualise the school within their own cluster and others:</p>
      <p>
      </p>
      <ul style='list-style-type: none; padding-left: 0;'>
        <li><b>Closest Peer:</b> The school in the same cluster that is mathematically most similar (shortest Euclidean distance).</li>
        <li><b>Closest Peer:</b> The school in the same cluster that is mathematically most dissimilar (shortest Euclidean distance).</li>
        <li><b>Closest Outsider:</b> The school in any other cluster that is mathematically most similar (shortest Euclidean distance across cluster boundaries).</li>
      </ul>

      <h5 style='margin-top: 20px;'>Cluster Characterisation (Random Forest)</h5>
      <p>To understand the features that most strongly drive the separation between clusters, we employed a secondary Supervised Learning technique: Random Forest Classification.
      Instead of predicting yield, this RF model was trained to predict the cluster assignment generated by our K-Means clustering.</p>
      <p>The resulting Variable Importance Plot (displayed below) ranks the features by their ability to accurately predict cluster membership for the five clusters we extracted
      from the k-means clustering. Our clustering characterisation tab, runs a RF model for pairwise clusters, helping the user understand the best 5 discriminators between
      any two groups. The user can select any two schools and look at the discriminators between their corresponding groups. The outputs (and plots) returned by this model are supplemented,
      with the actual (non-normalised) values for these categories, helping the user identify the true differences (and magnitudes of these) that might explain why two schools are not classified
      together. </p>

            <div style='text-align: center; margin: 20px 0;'>
         <img src='Images/clusterdrivers.png' style='max-width: 100%; height: auto; border: 1px solid #ccc;'>
           <p style='color: #666; font-style: italic; margin-top: 5px;'>Cluster Drivers</p>
          </div>

      <hr>

      <h2> About Us </h2>

      <h5> Sam Butler </h5>
      <p> Hi! My name is Sam. I am a senior at Pomona and a stats major. I’m from Philadelphia and in the process of applying to grad school right now.
      I get so excited about data visualization and this project was an awesome challenge in that department. I hope that in grad school and the years after
      I’ll be able to continue working on awesome projects like this one. </p>

      <h5> Federica Domecq </h5>
      <p> Hola! My name is Federica and I am a senior at Pomona College, double majoring in Statistics & Computer Science.
      Originally from Madrid, Spain 🇪🇸, I moved to the U.S. to pursue new opportunities, and I am also, in the process of applying to grad schools. I love
      building things that help me show my work, and I was excited to get creative with this project. Enjoy!</p>

    ")
    )
  ),
  tabPanel(
    "Admissions over Time",
    icon = bs_icon("map"),
    fluidPage( style = "background-color: #F5F5F5; margin: 0; padding: 0;",
               titlePanel("Yield, Applications, and Admission Rate by State"),
               
               tags$head(
                 tags$style(HTML("
          #year_slider_container {
            display: flex;
            justify-content: center;
            margin-top: 20px;
            margin-bottom: 10px;
          }
          #map_year {
            width: 600px !important;
          }

          #map_year .irs-bar,
          #map_year .irs-bar-edge {
            background-color: #4C72B0;
            border-color: #4C72B0;
          }
          #map_year .irs-line {
            background-color: #ddd;
          }
          #map_year .irs-handle {
            border-color: #4C72B0;
          }
        "))
               ),
               
               # slider above maps
               div(
                 id = "year_slider_container",
                 sliderInput(
                   inputId = "map_year",      # NOTE: different ID than 'year'
                   label   = "Select Year:",
                   min     = map_year_min,
                   max     = map_year_max,
                   value   = map_year_min,
                   step    = 1,
                   sep     = "",
                   animate = TRUE
                 )
               ),
               
               fluidRow(
                 column(4, plotOutput("yieldMap", height = "300px")),
                 column(4, plotOutput("appsMap",  height = "300px")),
                 column(4, plotOutput("admitMap", height = "300px"))
               ),
               
               br(),
               
               fluidRow(
                 column(4,
                        h4("Yield Rate"),
                        p("Yield rate has steadily decreased since the early 2000's. NACAC (The National Association for College Admission Counseling) noted a 15% decrease in yield rate nationally from 2007 to 2017. This is likely because of the rise in popularity of applying to many schools, (like 15 instead of 5). Then a cycle begins where universities are incentivized to admit more students, since it is less likely for any given student to commit to their school. This actively drives down yield rate.")
                 ),
                 column(4,
                        h4("Applications per Institution"),
                        p("This plot shows the same trend. The number of applications per institution has steadily risen across the country, illuminating the trend of students applying to more and more schools on average. The UC system amplifies this trend because of how students can apply to many universities through one application. The norm might have been closer to 2-4 in the early 2000's, but by the late 2010's perhaps closer to 5-7.")
                 ),
                 column(4,
                        h4("Admission Rate"),
                        p("We don't see a lot of change in admission rates because the number of applications and number of admitted students have been rising for the reasons described above.")
                 )
               ))
  ),
  tabPanel("Yield Prediction",
           icon = bs_icon("graph-up"),
           titlePanel("Predicted Yield Rate by Institution and Year"),
           sidebarLayout(
             sidebarPanel(
               selectInput(
                 "year", "Select year:",
                 choices  = year_choices,
                 selected = max(year_choices)
               ),
               selectizeInput(
                 "inst_name", "Choose an institution:",
                 choices = inst_choices,
                 options = list(placeholder = "Search (e.g. Pomona..)")
               ),
               actionButton("go", "Predict Yield", class = "btn-primary")
             ),
             mainPanel(
               card(
                 card_header(class = "bg-dark", h3(textOutput("pred_title"))),
                 
                 # minimalist metric layout
                 div(
                   style = "display:flex; gap:60px; align-items:flex-start; margin-top:15px;",
                   
                   div(
                     h5("Estimated Yield", style = "margin:0; color:#555;"),
                     h2(textOutput("pred_value"), style = "margin:0; font-weight:700;")
                   ),
                   
                   div(
                     h5("Actual Yield", style = "margin:0; color:#555;"),
                     h2(textOutput("actual_value"), style = "margin:0; font-weight:700;")
                   )
                 ),
                 
                 p("Note: Predictions based on gradient boosting model.")
               ),
               br(),
               plotOutput("yield_history_plot", height = "350px")
             )
           )
  ),
  tabPanel("Clustering",
           icon = bs_icon("collection"),
           titlePanel("University Clusters (US Map)"),
           sidebarLayout(
             sidebarPanel(
               width = 3,
               h5("Filters"),
               
               checkboxGroupInput(
                 inputId = "selected_clusters",
                 label = "Show Clusters:",
                 choices = levels(map_data_prepared$.pred_cluster),
                 # DEFAULT: ALL SELECTED
                 selected = levels(map_data_prepared$.pred_cluster),
                 inline = TRUE
               ),
               
               hr(),
               
               selectizeInput(
                 inputId = "highlight_school",
                 label = "Find a University:",
                 choices = NULL, # Filled server-side
                 selected = NULL,
                 options = list(placeholder = 'Type to search (e.g. Pomona...)')
               ),
               
               # Stats appear here
               uiOutput("school_stats_simple"),
               
               hr(),
               p("Hover for details. Zoom with your mouse wheel.")
             ),
             
             mainPanel(
               card(
                 full_screen = TRUE,
                 card_header(class = "bg-dark", "Geographic Distribution of Clusters"),
                 plotlyOutput("map_plot", height = "600px")
               )
             )
           )
  ),
  tabPanel("Cluster Characterisation",
           icon = bs_icon("signpost"),
           titlePanel("Cluster Feature Importance"),
           sidebarLayout(
             sidebarPanel(
               h4("Compare Institutions"),
               p("Select two schools to see which variables best distinguish their clusters."),
               
               # Input for first school
               selectizeInput("char_school1", "Select School A:",
                              choices = cluster_inst_choices,
                              selected = cluster_inst_choices[1],
                              options = list(placeholder = "Type to search (e.g. Pomona...)", maxOptions = 10)),
               
               # Input for School B
               selectizeInput("char_school2", "Select School B:",
                              choices = cluster_inst_choices,
                              selected = cluster_inst_choices[2],
                              options = list(placeholder = "Type to search(e.g. Pitzer ...)", maxOptions = 10)),
               
               hr(),
               
               # Dynamic text output describing the comparison
               uiOutput("cluster_comparison_text"),
               br(),
               h5("Key Differences (Top 5)"),
               uiOutput("top_5_metrics")
             ),
             mainPanel(
               card(
                 card_header(class = "bg-dark", "Variable Importance Plot"),
                 plotOutput("cluster_diff_plot", height = "550px")
               )
             )
           )
  ),
  tabPanel("Data & References",
           icon = bs_icon("database"),
           div(
             style = "padding: 20px; max-width: 800px; margin: auto; font-size: 16px;",
             h1("Data Used in Models"),
             
             # ------------------------------------
             h2("Yield Prediction (XGBoost) Data"),
             p("Though the original dataset has many variables, only a handful were selected so as to limit unnecessary noise in the model. Variables like 'library hours' are very unlikely to add any predictive value to the model."),
             
             HTML("
        <ul style='list-style-type: none; padding-left: 0;'>
          <li style='margin-bottom: 5px;'><b><code>admit_rate</code></b> - admission rate</li>
          <li style='margin-bottom: 5px;'><b><code>number_applied</code></b> - number of students who applied</li>
          <li style='margin-bottom: 5px;'><b><code>number_admitted</code></b> - number of students admitted</li>
          <li style='margin-bottom: 5px;'><b><code>number_enrolled_total</code></b> - number of students who enrolled</li>
          <li style='margin-bottom: 5px;'><b><code>tuition_ft</code></b> - tuition for full-time students</li>
          <li style='margin-bottom: 5px;'><b><code>fees_ft</code></b> - additional fees for full-time students</li>
          <li style='margin-bottom: 5px;'><b><code>net_price</code></b> - price after aid</li>
          <li style='margin-bottom: 5px;'><b><code>fips</code></b> - geographic ID (state/county)</li>
          <li style='margin-bottom: 5px;'><b><code>sector</code></b> - public/private institution</li>
          <li style='margin-bottom: 5px;'><b><code>calendar_system</code></b> - quarters/trimesters</li>
          <li style='margin-bottom: 5px;'><b><code>masters_offered</code></b> - masters degree or not</li>
          <li style='margin-bottom: 5px;'><b><code>religious_affiliation</code></b> - religious affiliation</li>
          <li style='margin-bottom: 5px;'><b><code>member_ncaa</code></b> - NCAA member</li>
          <li style='margin-bottom: 5px;'><b><code>member_conf_football</code></b> - Football team in official conference</li>
          <li style='margin-bottom: 5px;'><b><code>member_conf_basketball</code></b> - Basketball team in official conference</li>
        </ul>
      "),
             #--------
             h2("Clustering Model Variables (K-Means)"),
             p("Our K-Means clustering model used a standardised set of institutional features designed to measure resources, selectivity, and mission coming from multiple IPEDs datasets.
               The were appropriately standardised, and cleaned."),
             
             HTML("
        <ul style='list-style-type: none; padding-left: 0;'>
          <p> Financial Resources </p>
          <li style='margin-bottom: 5px;'><b><code>tuition_revenue_per_student</code></b> - Total tuition revenue divided by full-time equivalent student count. </li>
          <li style='margin-bottom: 5px;'><b><code>instruction_spend_per_student</code></b> - Instructional expenditure per full-time student. </li>
          <li style='margin-bottom: 5px;'><b><code>research_spend_per_student</code></b> - Research expenditure per full-time student. </li>
          <li style='margin-bottom: 5px;'><b><code>student_services_spend_per_student</code></b> - Student services expenditure per full-time student. </li>
          <li style='margin-bottom: 5px;'><b><code>endowment_per_student</code></b> - Institutional endowment value divided by full-time student count. </li>
          <li style='margin-bottom: 5px;'><b><code>is_private</code></b> - Binary indicator for private institutional control. </li>
          <p> Cost & Aid </p>
          <li style='margin-bottom: 5px;'><b><code>tuition_ft</code></b> - Published tuition and fees for full-time attendance. </li>
          <li style='margin-bottom: 5px;'><b><code>room_board</code></b> - Published cost of room and board. </li>
          <li style='margin-bottom: 5px;'><b><code>average_grant</code></b> - Average amount of grant aid received by full-time undergraduate students. </li>
          <li style='margin-bottom: 5px;'><b><code>percent_receiving_grant_aid</code></b> - Percentage of undergraduate students receiving grant or scholarship aid. </li>
          <p> Selectivity </p>
          <li style='margin-bottom: 5px;'><b><code>admit_rate</code></b> - Admission rate (admitted divided by applied). </li>
          <li style='margin-bottom: 5px;'><b><code>yield_rate</code></b> - Yield rate (enrolled divided by admitted).</li>
          <p> Student Satisfaction </p>
          <li style='margin-bottom: 5px;'><b><code>retention_rate</code></b> - First-year undergraduate retention rate. </li>
          <p> Institution Characteristics </p>
          <li style='margin-bottom: 5px;'><b><code>calendar_system</code></b> - Categorical variable for the academic calendar (e.g., semester, quarter). </li>
          <li style='margin-bottom: 5px;'><b><code>oncampus_required</code></b> - Binary indicator for whether on-campus living is required. </li>
          <li style='margin-bottom: 5px;'><b><code>is_religious</code></b> - Binary indicator for religious affiliation. </li>
          <li style='margin-bottom: 5px;'><b><code>offers_phd</code></b> - Binary indicator for whether the institution offers Doctoral (Ph.D.) degrees. </li>
          <li style='margin-bottom: 5px;'><b><code>has_study_abroad</code></b> - Binary indicator for institutions offering study abroad programs.</li>
        </ul>
      "),
             
             # ------------------------------------
             h2("General Data Preparation/Wrangling"),
             p("All modeling data was processed using R and the tidymodels library. We pulled the most recently available data for all the categories (2021). Unfortunately,
               the financial data we wanted to access was discontinued in 2018, hence we pulled the data from the year 2017. We deemed this admissible, because this
               was done for all institutions and the fact that it is unlikely for the overall wealth of a university (relative to others) to change drastically in
               a 4-year span."),
             
             HTML("
        <ul>
          <li><b>Imputation:</b> Missing numeric values (NA) were handled using <em> k-Nearest Neighbors (KNN) imputation </em>, which estimates missing values based on the most similar complete rows in the dataset.</li>
          <li><b>Normalisation:</b> All continuous numeric predictors (e.g., spending, endowment) were normalised (centered and scaled) using <code>step_normalize()</code>. This ensures that variables with large ranges, like <code> endowment_per_student` </code>, do not unduly influence the K-Means distance calculation.</li>
          <li><b>Exclusion:</b> Identifier variables (<code>unitid</code>, <code>inst_name</code>) and visual coordinates (<code>latitude</code>, <code>longitude</code>) were assigned an <code>'id'</code> role or explicitly removed so they did not participate in the core clustering algorithm.</li>
        </ul>
      "),
             
             br(),
             
             
             
             
             
             # ------------------------------------
             h2("General Data Preparation/Wrangling"),
             HTML("<p>All data for this project originates from the <a href='https://nces.ed.gov/ipeds' target='_blank'><b>Integrated Postsecondary Education Data System (IPEDS)</b></a> database, the primary source for US college and university statistics. While we initially faced significant data cleaning challenges, we streamlined the process by leveraging the R <code>educationdata</code> package, which provides direct API access to the cleaned IPEDS database. Our dataset concentrates on institutional data from the last 25 years, restricted to 2022 as that is the most recently available data in the API.</p>"),
             br()
           ))
)

# --- SERVER ---
server <- function(input, output, session) {
  
  # ---- Yield prediction tab logic ----
  pred_result <- reactive({
    req(input$year, input$inst_name)
  
    row <- pred_df |>
      filter(year == input$year,
             inst_name == input$inst_name)
    
    if (nrow(row) == 0) {
      return(list(
        name         = input$inst_name,
        year         = input$year,
        pred_yield   = NA_real_,
        actual_yield = NA_real_
      ))
    }
    
    list(
      name         = input$inst_name,
      year         = input$year,
      pred_yield   = as.numeric(row$pred_yield[1]),
      actual_yield = as.numeric(row$yield[1])
    )
  })
  
  output$pred_title <- renderText({
    res <- pred_result()
    if (is.na(res$pred_yield) || length(res$pred_yield) == 0) {
      return(paste("No prediction available for", res$name, "in", res$year))
    }
    paste("Predicted yield for", res$name, "in", res$year)
  })
  
  output$pred_value <- renderText({
    res <- pred_result()
    if (is.na(res$pred_yield) || length(res$pred_yield) == 0) return("")
    sprintf("Estimated yield: %.1f%%", 100 * res$pred_yield)
  })
  
  output$actual_value <- renderText({
    res <- pred_result()
    if (is.na(res$actual_yield)) return("")
    sprintf("Actual yield (%s): %.1f%%", res$year, 100 * res$actual_yield)
  })
  
  # time series of yields for the selected institution across all years
  inst_series <- reactive({
    req(input$inst_name)
    
    pred_df |>
      filter(inst_name == input$inst_name) |>
      arrange(year)
  })
  
  output$yield_history_plot <- renderPlot({
    res <- pred_result()
    dat <- inst_series()
    req(nrow(dat) > 0)
    
    # brand color for predicted line
    line_color <- brand_colors |>
      filter(inst_name == res$name) |>
      pull(color)
    if (length(line_color) == 0 || is.na(line_color)) line_color <- "steelblue"
    
    dat$year_num <- as.numeric(as.character(dat$year))
    sel_year     <- as.numeric(as.character(res$year))
    
    # training part for solid line
    dat_train <- dat |> filter(year < 2021)
    
    ggplot(dat, aes(x = year_num)) +
      # vertical cutoff at 2020.1
      geom_vline(
        xintercept = 2020.1,
        color      = "red",
        linetype   = "dashed",
        linewidth  = 0.8
      ) +
      
      # ACTUAL: solid black line + points (all years)
      geom_line(aes(y = 100 * yield, color = "Actual"), linewidth = 0.8) +
      geom_point(aes(y = 100 * yield, color = "Actual"), size = 2) +
      
      # PREDICTED: dashed line over all years (continuous)
      geom_line(
        aes(y = 100 * pred_yield, color = "Predicted"),
        linetype  = "dashed",
        linewidth = 0.9
      ) +
      geom_point(
        aes(y = 100 * pred_yield, color = "Predicted"),
        size = 2
      ) +
      
      # PREDICTED (TRAIN ONLY): solid overlay before 2021
      geom_line(
        data = dat_train,
        aes(y = 100 * pred_yield, color = "Predicted"),
        linetype  = "solid",
        linewidth = 0.9
      ) +
      
      # highlight selected year
      geom_point(
        data = subset(dat, year_num == sel_year),
        aes(y = 100 * yield, color = "Actual"),
        size = 4, stroke = 1
      ) +
      geom_point(
        data = subset(dat, year_num == sel_year),
        aes(y = 100 * pred_yield, color = "Predicted"),
        size = 4, stroke = 1
      ) +
      
      scale_color_manual(
        values = c(
          "Actual"    = "black",
          "Predicted" = line_color
        ),
        name = ""
      ) +
      labs(
        title = paste("Actual vs Predicted Yield for", res$name),
        x     = "Year",
        y     = "Yield (%)"
      ) +
      theme_minimal() +
      theme(
        legend.position  = "bottom",
        plot.background  = element_rect(fill = "#F5F5F5", colour = NA),
        panel.background = element_rect(fill = "#F5F5F5", colour = NA),
        panel.grid.major = element_line(colour = "grey80"),
        panel.grid.minor = element_line(colour = "grey90")
      )
  })
  
  
  
  # ---- Nice pictures tab logic (maps) ----
  
  year_data <- reactive({
    state_year_named |>
      filter(year == input$map_year)   # uses map_year
  })
  
  # Map 1 yield
  output$yieldMap <- renderPlot({
    map_df <- states_map |>
      left_join(year_data(), by = c("region" = "state_name"))
    
    ggplot(map_df, aes(long, lat, group = group)) +
      geom_polygon(aes(fill = mean_yield), color = "white", linewidth = 0.2) +
      coord_map() +
      scale_fill_gradientn(
        colors  = wesanderson::wes_palette("Zissou1", type = "continuous"),
        name    = "Average yield rate",
        limits  = c(yield_min, yield_max),
        na.value = "grey90"
      ) +
      labs(
        title = paste("Average Yield Rate by State,", input$map_year),
        x = NULL, y = NULL
      ) +
      theme_minimal() +
      theme(
        axis.text  = element_blank(),
        axis.ticks = element_blank(),
        panel.grid = element_blank(),
        plot.background  = element_rect(fill = "#F5F5F5", color = NA)
      )
  },  bg = "transparent")
  
  #  map 2 applications per institution
  output$appsMap <- renderPlot({
    map_df <- states_map |>
      left_join(year_data(), by = c("region" = "state_name"))
    
    ggplot(map_df, aes(long, lat, group = group)) +
      geom_polygon(aes(fill = apps_per_institution), color = "white", linewidth = 0.2) +
      coord_map() +
      scale_fill_gradientn(
        colors  = wesanderson::wes_palette("Zissou1", type = "continuous"),
        name    = "Apps per institution",
        limits  = c(apps_min, apps_max),
        na.value = "grey90"
      ) +
      labs(
        title = paste("Applications per Institution by State,", input$map_year),
        x = NULL, y = NULL
      ) +
      theme_minimal() +
      theme(
        axis.text  = element_blank(),
        axis.ticks = element_blank(),
        panel.grid = element_blank(),
        plot.background  = element_rect(fill = "#F5F5F5", color = NA)
      )
  }, bg = "transparent")
  
  # Map 3: admission rate
  output$admitMap <- renderPlot({
    map_df <- states_map |>
      left_join(year_data(), by = c("region" = "state_name"))
    
    ggplot(map_df, aes(long, lat, group = group)) +
      geom_polygon(aes(fill = mean_admit_rate), color = "white", linewidth = 0.2) +
      coord_map() +
      scale_fill_gradientn(
        colors  = wesanderson::wes_palette("Zissou1", type = "continuous"),
        name    = "Mean admission rate",
        limits  = c(admit_min, admit_max),
        na.value = "grey90"
      ) +
      labs(
        title = paste("Average Admission Rate by State,", input$map_year),
        x = NULL, y = NULL
      ) +
      theme_minimal() +
      theme(
        axis.text  = element_blank(),
        axis.ticks = element_blank(),
        panel.grid = element_blank(),
        plot.background  = element_rect(fill = "#F5F5F5", color = NA)
      )
  }, bg = "transparent")
  
  # ---- LOGIC FOR CLUSTER MAP
  #  search bar
  observe({
    updateSelectizeInput(session, "highlight_school",
                         choices = sort(unique(map_data_prepared$inst_name)),
                         server = TRUE)
  })
  
  output$map_plot <- renderPlotly({
    
    # filter Data (Checkboxes)
    # default selected
    plot_df <- map_data_prepared |>
      filter(.pred_cluster %in% input$selected_clusters)
    
    # highlighting logic
    if (!is.null(input$highlight_school) && input$highlight_school != "") {
      plot_df <- plot_df |>
        mutate(
          # opacity 1 if highlighted, 0.4 if not
          opacity_val = ifelse(inst_name == input$highlight_school, 1, 0.9),
          size_val    = ifelse(inst_name == input$highlight_school, 20, 3),
          # Highlighted school goes to the top (layer 2)
          sort_order  = ifelse(inst_name == input$highlight_school, 2, 1)
        ) |>
        arrange(sort_order)
    } else {
      # default
      plot_df <- plot_df |>
        mutate(opacity_val = 1.0, size_val = 4)
    }
    
    #  Plotly Map
    validate(need(nrow(plot_df) > 0, "No clusters selected."))
    
    zissou_colors <- wesanderson::wes_palette("Zissou1", type = "discrete")
    zissou_colors_clean <- as.character(zissou_colors)
    
    plot_geo(plot_df, locationmode = 'USA-states') |>
      add_markers(
        x = ~longitude,
        y = ~latitude,
        text = ~hover_text,
        color = ~.pred_cluster,
        colors = zissou_colors_clean,
        opacity = ~opacity_val,
        size = ~size_val,
        hoverinfo = "text"
      ) |>
      layout(
        title = list(text = "University Clusters across the USA", y = 0.95),
        geo = g_map_settings,
        paper_bgcolor = "#F5F5F5",
        plot_bgcolor = "#F5F5F5",
        
        # Optional: tighter margins to blend even better
        margin = list(l = 0, r = 0, t = 50, b = 0)
      )
  })
  
  # --- SIMPLE STATS RENDERER ---
  output$school_stats_simple <- renderUI({
    
    # Wait for selection
    req(input$highlight_school)
    
    # Find school in our prepared data
    sch <- map_data_prepared |> filter(inst_name == input$highlight_school)
    if(nrow(sch) == 0) return(NULL)
    
    # Formatters
    p_fmt <- function(x) if(is.numeric(x)) percent(x, accuracy=0.1) else "N/A"
    d_fmt <- function(x) if(is.numeric(x)) dollar(x) else "N/A"
    # Just in case checker
    check_nb <- function(x) if(is.na(x) || x == "") "None" else x
    
    HTML(paste0(
      "<h4 style='color: #0072B2; margin-bottom:5px;'>Stats</h4>",
      "<mark><b>Cluster:</mark> ", sch$.pred_cluster, "<br>",
      "<mark>Admit Rate:</mark> ", p_fmt(sch$admit_rate), "<br>",
      "<mark>Yield Rate:</mark> ", p_fmt(sch$yield_rate), "<br>",
      "<mark>Tuition:</mark> ", d_fmt(sch$tuition_ft), "<br>",
      "<mark>Avg Grant:</mark> ", d_fmt(sch$average_grant), "<br>",
      "<mark>Endowment:</mark> ", d_fmt(sch$endowment_per_student),
      "<hr style='margin: 10px 0; border-top: 1px solid #ccc;'>",
      "<h4 style='color: #0072B2; margin-bottom:5px;'>Cluster Context</h4>",
      
      "<mark>Most Similar (Same Cluster):</mark><br>",
      "<strong>", check_nb(sch$closest_peer), "</strong><br>",
      
      "<div style='margin-top:5px;'></div>", # spacer
      
      "<mark>Most Different (Same Cluster):</mark><br>",
      "<strong>", check_nb(sch$furthest_peer), "</strong><br>",
      
      "<div style='margin-top:5px;'></div>", # spacer
      
      "<mark>Closest Outsider (Diff Cluster):</mark><br>",
      "<strong>", check_nb(sch$closest_outsider), "</strong>"
    ))
  })
  
  # Logic for Pairwise
  # ---- Cluster Characterisation Logic ----
  
  # Get cluster assignments for the two selected schools
  selected_pair_info <- reactive({
    req(input$char_school1, input$char_school2)
    
    # Get cluster for School 1
    c1_row <- clustered_set |> filter(inst_name == input$char_school1)
    c1 <- if(nrow(c1_row) > 0) as.character(c1_row$.pred_cluster[1]) else NA
    
    # Get Cluster for School 2
    c2_row <- clustered_set |> filter(inst_name == input$char_school2)
    c2 <- if(nrow(c2_row) > 0) as.character(c2_row$.pred_cluster[1]) else NA
    
    list(c1 = c1, c2 = c2)
  })
  
  # descriptive Text
  output$cluster_comparison_text <- renderUI({
    info <- selected_pair_info()
    if(is.na(info$c1) || is.na(info$c2)) return(p("School not found in cluster data."))
    
    tagList(
      p(strong(input$char_school1), " is in ", strong(paste("Cluster", info$c1))),
      p(strong(input$char_school2), " is in ", strong(paste("Cluster", info$c2))),
      if(info$c1 == info$c2) {
        div(class = "alert alert-info", "These schools are in the same cluster!")
      } else {
        div(class = "alert alert-warning",
            paste("Comparing differences between Cluster", info$c1, "and Cluster", info$c2))
      }
    )
  })
  
  #comparison values
  output$top_5_metrics <- renderUI({
    
    # get schools
    s1_name <- input$char_school1
    s2_name <- input$char_school2
    info <- selected_pair_info()
    
    req(s1_name, s2_name, info$c1, info$c2)
    
    # id the top 5 variables for this pair (repeated logic as before)
    n1 <- readr::parse_number(as.character(info$c1))
    n2 <- readr::parse_number(as.character(info$c2))
    sorted_nums <- sort(c(n1, n2))
    pair_id <- paste0("Cluster_", sorted_nums[1], "_vs_Cluster_", sorted_nums[2])
    
    # top 5
    top_vars_df <- pairwise_tables |>
      filter(cluster_pair == pair_id) |>
      arrange(desc(Importance)) |>
      head(5) |>
      # join with clean data
      inner_join(var_metadata, by = c("Variable" = "clean_name"))
    
    if(nrow(top_vars_df) == 0) return(p("No data for this comparison."))
    
    #get data for two schools
    target_cols <- top_vars_df$col_name
    
    schools_data <- clustered_set |>
      filter(inst_name %in% c(s1_name, s2_name)) |>
      select(inst_name, all_of(target_cols))
    
    s1_dat <- schools_data |> filter(inst_name == s1_name)
    s2_dat <- schools_data |> filter(inst_name == s2_name)
    
    # HTML List (gemini)
    rows_html <- lapply(1:nrow(top_vars_df), function(i) {
      
      row_info <- top_vars_df[i, ]
      
      clean_name <- row_info$Variable
      col_code   <- row_info$col_name
      fmt_type   <- row_info$format_type
      
      val1 <- s1_dat[[col_code]]
      val2 <- s2_dat[[col_code]]
      
      # formatting logic
      formatter <- function(v, type) {
        if(is.na(v)) return("N/A")
        
        # Money
        if(type == "money")   return(dollar(v))
        
        # Percentages
        if(type == "percent") return(percent(v, accuracy = 0.1))
        
        # Text / Boolean
        if(type == "text") {
          if(v == 1 || v == "1" || v == TRUE) return("Yes")
          if(v == 0 || v == "0" || v == FALSE) return("No")
          return(as.character(v))
        }
        
        # Default numeric fallback
        if(is.numeric(v))     return(round(v, 2))
        return(v)
      }
      
      # HTML FOR ONE ROW
      tagList(
        div(style="font-size:12px; color:#666; margin-top:8px;", paste0(i, ". ", clean_name)),
        div(style="display:flex; justify-content:space-between; font-weight:bold; font-size:14px;",
            span(formatter(val1, fmt_type)),
            span(formatter(val2, fmt_type))
        ),
        div(style="background-color:#ddd; height:1px; margin-top:4px;")
      )
    })
    
    # HTML FOR OTHER ROW
    tagList(
      div(style="display:flex; justify-content:space-between; font-weight:bold; color:#0072B2; margin-bottom:5px; border-bottom: 2px solid #0072B2;",
          span(style="width:45%; word-wrap:break-word; font-size:12px;", s1_name),
          span(style="width:45%; word-wrap:break-word; text-align:right; font-size:12px;", s2_name)
      ),
      rows_html
    )
  })
  
  
  # output: the plot
  output$cluster_diff_plot <- renderPlot({
    info <- selected_pair_info()
    
    # check
    req(info$c1, info$c2)
    
    #  Convert cluster numbers, and sort
    n1 <- readr::parse_number(as.character(info$c1))
    n2 <- readr::parse_number(as.character(info$c2))
    sorted_nums <- sort(c(n1, n2))
    
    # same cluster handling
    if(info$c1 == info$c2) {
      return(
        ggplot() +
          annotate("text", x = 1, y = 1, size = 6, color = "red",
                   label = "Schools are in the same cluster.\nSelect a different school.") +
          theme_void()
      )
    }
    
    # constructing cluster id so that it matches csv output
    #     "Cluster_1_vs_Cluster_2" to match
    pair_id <- paste0("Cluster_", sorted_nums[1], "_vs_Cluster_", sorted_nums[2])
    
    # filter the data
    plot_data <- pairwise_tables |>
      filter(cluster_pair == pair_id) |>
      arrange(desc(Importance)) |>
      mutate(rank_label = row_number())
    
    # validate
    validate(
      need(nrow(plot_data) > 0,
           paste("No data found for ID:", pair_id))
    )
    
    # plot
    plot_data |>
      ggplot(aes(x = Importance, y = reorder(Variable, Importance))) +
      geom_col(aes(fill = Importance), width = 0.7) +
      geom_text(
        aes(label = rank_label),
        hjust = 1.5,    # inside the bar
        color = "white",
        fontface = "bold",
        size = 10
      ) +
      scale_fill_gradientn(
        colors = wes_palette("Zissou1", 100, type = "continuous")
      ) +
      labs(
        title = paste("Differences: Cluster", sorted_nums[1], "vs Cluster", sorted_nums[2]),
        subtitle = "Variables with high importance distinguish these two groups",
        x = "Variable Importance",
        y = NULL
      ) +
      theme_minimal(base_size = 16) +
      theme(
        panel.grid.major.y = element_blank(),
        plot.title = element_text(face = "bold"),
        axis.text.y = element_text(color = "#333333"),
        legend.position = "none",
        plot.background  = element_rect(fill = "#F5F5F5", color = NA),
      )
  })
}

shinyApp(ui = ui, server = server)
