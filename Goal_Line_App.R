## NOTE: Due to amount of memory required to run MCMC sampling for Bayesian
## models, this Shiny app cannot be deployed to a Shiny server using a free (1GB)
## subscription.

library(tidyverse)
library(shiny)
library(nflfastR)
library(rstanarm)
library(reactable)

## 2022 NFL play-by-play data
pbp_raw <- load_pbp(2022)

## Data frame for goal-to-go data
## Removed 4th down since primary focus is predicting offensive play calls
## Will create new binary variable, 'pass', where a 1 = pass; 0 = run
goal_offense <- pbp_raw %>% 
        filter(!is.na(goal_to_go),
               !is.na(yardline_100),
               !is.na(play_type),
               goal_to_go > 0,
               down < 4,
               play_type %in% c("pass", "run")) %>% 
        mutate(down = as.factor(down),
               pass = as.factor(ifelse(play_type == "pass", 1, 0))) %>% 
        select(posteam,
               week,
               pass,
               goal_to_go,
               yardline_100,
               down,
               play_type,
               defteam,
               week)


## For this scenario, I am pretending we have only completed 17 weeks of the 2022
## season.
goal_offense_wk_17 <- goal_offense %>% 
        filter(week <= 17)

## Total run EPA after Week 17
total_run_epa <- pbp_raw %>%
        filter(play_type %in% c("run"),
               !is.na(epa),
               week <= 17) %>% 
        group_by(posteam) %>%
        summarize(szn_epa = sum(epa)) %>% arrange((szn_epa))

## Join total run EPA to main data frame
goal_offense_wk_17 <- goal_offense_wk_17 %>% 
        left_join(x = ., y = total_run_epa, by = "posteam")

## Multilevel logistic regression model
grp_lvl_variable <- stan_glmer(
        pass ~ yardline_100 + down + yardline_100:down + szn_epa + (1|posteam),
        data = goal_offense_wk_17,
        family = binomial(link = "logit"),
        iter = 5000
)

ui <- fluidPage(
        sidebarLayout(
                sidebarPanel(
                        htmlOutput("logo"),
                        selectInput(inputId = "team_input",
                                    label = "Team",
                                    choices = sort(unique(goal_offense_wk_17$posteam))),
                        radioButtons(inputId = "down_input",
                                    label = "Down:",
                                    choices = c("1", "2", "3")),
                        sliderInput(inputId = "los_input",
                                    label = "Line of scrimmage:",
                                    min = 1,
                                    max = 15,
                                    value = 10),
                        downloadButton(outputId = "report",
                                       label = "Generate Report")
                ),
                mainPanel(plotOutput("pd_histogram"),
                          reactableOutput("play_prob_table"))
        )
)


server <- function(input, output) {
        
        ## Reactive data frame for predictions
        pred_data <- reactive({
                
                req(input$team_input)
                
                run_epa <- goal_offense_wk_17 %>% 
                        filter(posteam == input$team_input) %>% 
                        pull(szn_epa) %>% 
                        unique()
                
                new_data <- data.frame(
                        posteam = input$team_input,
                        down = input$down_input,
                        yardline_100 = input$los_input,
                        szn_epa = run_epa)
                
                pd <- posterior_epred(grp_lvl_variable,
                                        newdata = new_data)
                
                pd <- tibble(prob = pd[,1]*100)
                
                pd
        })
        
        ## Logo
        output$logo <- renderText({
                
                logo <- teams_colors_logos %>% 
                        filter(team_abbr == input$team_input) %>% 
                        pull(team_logo_wikipedia)
                
                c('<img src="',logo,'">')
                
                
        })
        
        ## PD histogram
        output$pd_histogram <- renderPlot({
                
                median_prob <- median(pred_data()$prob)
                hdi_prob <- HDInterval::hdi(pred_data()$prob)
                
               plot <- pred_data() %>% 
                       ggplot(aes(x = prob)) +
                       geom_histogram(color = "black",
                                      fill = "skyblue") + 
                       geom_vline(xintercept = c(median_prob,
                                                 hdi_prob[1],
                                                 hdi_prob[2]),
                                  color = c("red3", "black", "black"),
                                  linetype = "dashed",
                                  linewidth = 1.5) +
                       labs(title = "Pass Probability Predictive Distribution",
                            x = "Pass Probability (%)",
                            y = "Count") +
                       theme_minimal()
               
               plot
                
        })
        
        ## PD summary table
        output$play_prob_table <- renderReactable({
                
                df <- tibble(
                        pass_prob = round(median(pred_data()$prob),1),
                        pass_hdi_95 = paste0("[",
                                       round(HDInterval::hdi(pred_data()$prob)[1],1),
                                       ", ",
                                       round(HDInterval::hdi(pred_data()$prob)[2],1),
                                       "]"),
                        run_prob = round(median(100 - pred_data()$prob),1),
                        run_hdi_95 = paste0("[",
                                             round(HDInterval::hdi(100-pred_data()$prob)[1],1),
                                             ", ",
                                             round(HDInterval::hdi(100-pred_data()$prob)[2],1),
                                             "]"),
                        se_prob = round(mad(pred_data()$prob),1)
                )
                
                tab <- reactable(df,
                                 columns = list(
                                         pass_prob = colDef(name = "Probability"),
                                         pass_hdi_95 = colDef(name = "95% HDI"),
                                         run_prob = colDef(name = "Probability"),
                                         run_hdi_95 = colDef(name = "95% HDI"),
                                         se_prob = colDef(name = "SE")
                                 ),
                                 columnGroups = list(
                                         colGroup(name = "Pass", columns = c("pass_prob", "pass_hdi_95")),
                                         colGroup(name = "Run", columns = c("run_prob", "run_hdi_95"))
                                 ))
                
                tab
                
        })
        
        
        ## Output for RMarkdown HTML report
        output$report <- downloadHandler(
                filename = paste0(input$team_input, "_Goal_Line_Report_", Sys.Date(), ".html"),
                content = function(file) {
                        # Set up parameters to pass to Rmd document
                        params <- list(team = input$team_input)
                        
                        # Knit the document, passing in the `params` list, and eval it in a
                        # child of the global environment (this isolates the code in the document
                        # from the code in this app).
                        rmarkdown::render("Goal_Line_Prob_Report.Rmd", output_file = file,
                                          params = params,
                                          envir = new.env(parent = globalenv())
                        )
                        
                }
        )
        
}

shinyApp(ui, server)
