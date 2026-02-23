# Recipe Rotation Idea

## Concept

An app (can be responsive website) that allows for recipes to be created and added to a weekly rotation for easy meal planning.

Main features:
1. A recipe can be created in many ways:
    a. Manually
    b. By pasting a website (an LLM will scrape it and create the recipe)
    c. By requesting an LLM to generate a recipe 
2. To plan a week a user may:
    a. Manually choose recipes 
    b. Ask LLM to automatically come up with a plan
    c. Intersting feature: easily parallelizable recipes (a recipe that takes long to cook while at the same time working on another recipe)
    d. Also interesting to be able to connect to cookidoo if possible for thermomix plan


## Data Model

* A recipe has ingredients and steps. 
* A weekly plan has multiple recipes

## Constraints

* Programming language: Elixir
* Very secure access only to be used by myself
* Nice UI (needs design)


