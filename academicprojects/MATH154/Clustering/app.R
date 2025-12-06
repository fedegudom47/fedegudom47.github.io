#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    https://shiny.posit.co/
#

library(shiny)
library(bslib) # Modern UI styling
library(dplyr)
library(ggplot2)
library(bsicons) # Icons for the UI

ui <- navbarPage(
  "University Analytics",
  theme = bslib::bs_theme(bg = "#101010",
                           fg = "#FFF",
                           primary = "#E69F00",
                           secondary = "#0072B2",
                           success = "#009E73",
                           base_font = font_google("Inter"),
                           code_font = font_google("JetBrains Mono"), 
                           bootswatch = "lux"),
  tabPanel("About",
           h2("Welcome to our 154 Project"),
           p("This is the content for the Home tab.")
  ),
  tabPanel("Data",
           h2("Learn more about our Data here!"),
           # ... UI elements for data display
  ),
  tabPanel("Cluster Characterisation",
           h2("What splits educational institutions apart?"),
           # ... UI elements for plotting
  )
)

# Define server logic required to draw a histogram
server <- function(input, output) {

    output$distPlot <- renderPlot({
        # generate bins based on input$bins from ui.R
        x    <- faithful[, 2]
        bins <- seq(min(x), max(x), length.out = input$bins + 1)

        # draw the histogram with the specified number of bins
        hist(x, breaks = bins, col = 'darkgray', border = 'white',
             xlab = 'Waiting time to next eruption (in mins)',
             main = 'Histogram of waiting times')
    })
}

# Run the application 
shinyApp(ui = ui, server = server)
