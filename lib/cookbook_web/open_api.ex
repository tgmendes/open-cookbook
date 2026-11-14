defmodule CookbookWeb.OpenAPI do
  @moduledoc "Source of truth for the cookbook's OpenAPI contract and hosted MCP tools."

  def spec(server \\ CookbookWeb.Endpoint.url()) do
    %{
      openapi: "3.0.3",
      info: %{
        title: "Open Cookbook",
        version: "1.0.0",
        description:
          "Private recipe storage and weekly meal planning. Every cookbook operation requires the owner's API token."
      },
      servers: [%{url: server}],
      security: [%{cookbookToken: []}],
      paths: %{
        "/api/v1/profile" => %{
          get:
            operation(
              "get_cookbook_profile",
              "Read the owner's unit preference before composing recipes.",
              object(
                %{
                  unit_system: %{type: "string", enum: ["metric", "imperial"]},
                  ingredient_units: array(%{type: "string"})
                },
                [:unit_system, :ingredient_units]
              )
            )
        },
        "/api/v1/recipes" => %{
          get:
            operation(
              "list_recipes",
              "Search stored recipes by title/ingredient and tag. Follow pagination until has_more is false.",
              array(ref("RecipeSummary"))
            )
            |> Map.put(:parameters, [
              query("search", %{type: "string"}),
              query("tag", %{type: "string"}),
              query("limit", %{type: "integer", minimum: 1, maximum: 100, default: 50}),
              query("offset", %{type: "integer", minimum: 0, default: 0})
            ])
            |> put_in(
              [:responses, "200", :content, "application/json", :schema],
              object(
                %{
                  data: array(ref("RecipeSummary")),
                  meta:
                    object(
                      %{
                        limit: %{type: "integer"},
                        offset: %{type: "integer"},
                        has_more: %{type: "boolean"}
                      },
                      [:limit, :offset, :has_more]
                    )
                },
                [:data, :meta]
              )
            ),
          post:
            operation(
              "create_recipe",
              "Save a complete recipe. Generate a fresh Idempotency-Key for each intentional creation and reuse it for retries of the same body. The original response is replayed for 24 hours, even if the recipe is subsequently edited or deleted. Reusing a key for a different body returns 409.",
              ref("Recipe"),
              "201"
            )
            |> Map.put(:parameters, [
              %{
                name: "Idempotency-Key",
                in: "header",
                required: true,
                schema: %{type: "string", minLength: 1, maxLength: 128}
              }
            ])
            |> Map.put(:requestBody, body(ref("RecipeCreate")))
            |> put_in(
              [:responses, "409"],
              error("The same key was already used for a different recipe.")
            )
        },
        "/api/v1/recipes/{id}" => %{
          get:
            operation(
              "get_recipe",
              "Read a stored recipe with ingredients and steps in cooking order.",
              ref("Recipe")
            )
            |> Map.put(:parameters, [path("id", %{type: "string", format: "uuid"})]),
          patch:
            operation(
              "update_recipe",
              "Update selected fields. Omitted ingredients/steps remain unchanged; a supplied array replaces that entire collection. Empty arrays remove that collection. Read the latest recipe before replacing nested content.",
              ref("Recipe")
            )
            |> Map.put(:parameters, [path("id", %{type: "string", format: "uuid"})])
            |> Map.put(:requestBody, body(ref("RecipeUpdate"))),
          delete: %{
            operationId: "delete_recipe",
            description:
              "Permanently delete a recipe and remove ALL its references from weekly meal plans. Ask the owner before doing this.",
            parameters: [path("id", %{type: "string", format: "uuid"})],
            responses:
              Map.merge(errors(), %{
                "204" => %{description: "Recipe and meal-plan references removed."}
              })
          }
        },
        "/api/v1/meal-plans/{week}" => %{
          get:
            operation(
              "get_meal_plan",
              "Read a week, normalized to Monday. Missing plans return empty entries without creating records.",
              ref("MealPlan")
            )
            |> Map.put(:parameters, [week()])
        },
        "/api/v1/meal-plans/{week}/slots/{day}/{meal}" => %{
          put:
            operation(
              "replace_meal_slot",
              "Replace ONLY this day's lunch or dinner with the ordered recipe_ids. Existing recipes in this slot are removed; other slots are untouched. An empty array clears the slot. Read the plan first when appending. Retrying the same request does not duplicate entries.",
              ref("MealPlan")
            )
            |> Map.put(:parameters, [
              week(),
              path("day", %{
                type: "integer",
                minimum: 1,
                maximum: 7,
                description: "Monday=1, Sunday=7"
              }),
              path("meal", %{type: "string", enum: ["lunch", "dinner"]})
            ])
            |> Map.put(
              :requestBody,
              body(
                object(
                  %{
                    recipe_ids: %{
                      type: "array",
                      maxItems: 50,
                      items: %{type: "string", format: "uuid"}
                    }
                  },
                  [:recipe_ids]
                )
              )
            )
        },
        "/api/v1/shopping-lists/{week}" => %{
          get:
            operation(
              "get_shopping_list",
              "Read aggregated ingredients from the week's planned recipes. Quantities are per recipe occurrence, not adjusted to diners. Shopping checkmarks are local to the browser and are not part of this API.",
              object(
                %{
                  week_start: %{type: "string", format: "date"},
                  items:
                    array(
                      object(%{name: %{type: "string"}, quantity: string(), unit: string()}, [
                        :name,
                        :quantity,
                        :unit
                      ])
                    )
                },
                [:week_start, :items]
              )
            )
            |> Map.put(:parameters, [week()])
        }
      },
      components: %{
        securitySchemes: %{
          cookbookToken: %{
            type: "http",
            scheme: "bearer",
            description:
              "Create a revocable token in the cookbook's Connections page. Store it only in Speakeasy's secure credential settings, never in tool arguments or chat."
          }
        },
        schemas: schemas()
      }
    }
  end

  defp schemas do
    ingredient =
      object(
        %{
          name: %{type: "string", minLength: 1, maxLength: 20_000},
          quantity:
            Map.put(
              string(),
              :description,
              "Text quantity, including fractions such as 1/2 or phrases such as to taste."
            ),
          unit: string(),
          group_name: string()
        },
        [:name]
      )

    step =
      object(
        %{
          instruction: %{type: "string", minLength: 1, maxLength: 20_000},
          duration_minutes: integer(0)
        },
        [:instruction]
      )

    scalar = %{
      title: %{type: "string", minLength: 1, maxLength: 255},
      description: string(),
      servings: integer(1),
      prep_time_minutes: integer(0),
      cook_time_minutes: integer(0),
      source_url: string(),
      source_type: %{type: "string", enum: ["manual", "scraped", "generated"], default: "manual"},
      tags: %{type: "array", maxItems: 100, items: %{type: "string"}},
      image_url: string(),
      notes: string()
    }

    input =
      Map.merge(scalar, %{
        ingredients: %{type: "array", maxItems: 200, items: ref("IngredientInput")},
        steps: %{type: "array", maxItems: 200, items: ref("StepInput")}
      })

    summary =
      Map.merge(scalar, %{
        id: %{type: "string", format: "uuid"},
        total_time_minutes: integer(0),
        inserted_at: %{type: "string", format: "date-time"},
        updated_at: %{type: "string", format: "date-time"}
      })

    recipe =
      Map.merge(summary, %{ingredients: array(ref("Ingredient")), steps: array(ref("Step"))})

    %{
      "IngredientInput" => ingredient,
      "StepInput" => step,
      "Ingredient" =>
        ingredient
        |> Map.update!(:properties, &Map.put(&1, :position, %{type: "integer", minimum: 0})),
      "Step" =>
        step |> Map.update!(:properties, &Map.put(&1, :position, %{type: "integer", minimum: 0})),
      "RecipeCreate" => object(input, [:title]),
      "RecipeUpdate" => object(input),
      "RecipeSummary" => object(summary, Map.keys(summary)),
      "Recipe" => object(recipe, Map.keys(recipe)),
      "MealPlan" =>
        object(
          %{
            week_start: %{type: "string", format: "date"},
            entries:
              array(
                object(
                  %{
                    id: %{type: "string", format: "uuid"},
                    day_of_week: %{type: "integer", minimum: 1, maximum: 7},
                    meal_type: %{type: "string", enum: ["lunch", "dinner"]},
                    position: %{type: "integer", minimum: 0},
                    recipe_id: %{type: "string", format: "uuid"},
                    recipe_title: %{type: "string"}
                  },
                  [:id, :day_of_week, :meal_type, :position, :recipe_id, :recipe_title]
                )
              )
          },
          [:week_start, :entries]
        ),
      "Error" =>
        object(
          %{
            error: %{
              type: "object",
              required: [:code],
              properties: %{
                code: %{
                  type: "string",
                  enum: ["unauthorized", "not_found", "validation_error", "conflict"]
                },
                details: %{type: "object", additionalProperties: true}
              }
            }
          },
          [:error]
        )
    }
  end

  defp operation(id, description, schema, status \\ "200") do
    %{
      operationId: id,
      description: description,
      responses:
        Map.merge(errors(), %{
          status => %{
            description: "Success",
            content: %{"application/json" => %{schema: object(%{data: schema}, [:data])}}
          }
        })
    }
  end

  defp errors,
    do: %{
      "401" => error("Missing, invalid, expired, or revoked token."),
      "404" => error("Resource not found in the owner's cookbook."),
      "422" => error("Invalid input.")
    }

  defp error(description),
    do: %{description: description, content: %{"application/json" => %{schema: ref("Error")}}}

  defp object(properties, required \\ []),
    do: %{type: "object", properties: properties, required: required, additionalProperties: false}

  defp array(items), do: %{type: "array", items: items}
  defp string, do: %{type: "string", nullable: true, maxLength: 20_000}
  defp integer(minimum), do: %{type: "integer", nullable: true, minimum: minimum}
  defp ref(name), do: %{"$ref" => "#/components/schemas/#{name}"}
  defp body(schema), do: %{required: true, content: %{"application/json" => %{schema: schema}}}
  defp path(name, schema), do: %{name: name, in: "path", required: true, schema: schema}
  defp query(name, schema), do: %{name: name, in: "query", required: false, schema: schema}

  defp week,
    do:
      path("week", %{
        type: "string",
        format: "date",
        description: "Any ISO date in the requested week; normalized to Monday."
      })
end
