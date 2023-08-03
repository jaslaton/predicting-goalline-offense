# Predicting goal line offense in the NFL
This repository is designed to showcase how someone may attempt to predict offensive play call probabilities in a goal-to-go scenario, and how these predictions can be intuitively presented to stakeholders.
## Guide to model building
Using the nflfastR package, a step-by-step guide is provided for building the predictive models. This guide goes through exploratory data analysis, model building, and model use.
## Web app
Using the prediction model, an R Shiny web app is built. The web app allows users to input a goal-to-go scenario, subsequently returning the predictive probability of the play call being a run or pass. Additionally, an interactive report can be generated from the web app, allowing stakeholders to have a succinct "cheat sheet" for play call probability prediction of the opposing offense.
