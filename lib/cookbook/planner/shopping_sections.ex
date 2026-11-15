defmodule Cookbook.Planner.ShoppingSections do
  @moduledoc "Keyword-based supermarket sections. Unknown ingredients go in Cupboard."
  @sections [
    {"Cupboard",
     ~r/\b(coconut milk|almond milk|oat milk|soy milk|milk powder|peanut butter|cocoa butter)\b/i},
    {"Fruit & veg",
     ~r/\b(carrots?|onions?|garlic|ginger|potatoes?|tomatoes?|peppers?|pak choi|bok choy|broccoli|spinach|kale|lettuce|cabbage|leeks?|mushrooms?|courgettes?|zucchini|aubergines?|eggplants?|celery|cucumbers?|lemons?|limes?|oranges?|apples?|bananas?|berries|avocados?|coriander|cilantro|parsley|basil|mint|thyme|rosemary|chill?i(?:es)?|sweetcorn|peas|greens)\b/i},
    {"Fish & meat",
     ~r/\b(salmon|tuna|cod|haddock|fish|prawns?|shrimp|chicken|beef|pork|lamb|turkey|bacon|sausages?|ham|mince|steak)\b/i},
    {"Dairy & eggs",
     ~r/\b(milk|cream|butter|cheese|feta|parmesan|mozzarella|ricotta|yogh?urt|eggs?)\b/i},
    {"Bakery", ~r/\b(bread|loaf|rolls?|baguette|pitta|pita|tortillas?|buns?|naan)\b/i}
  ]

  def section(name) do
    Enum.find_value(@sections, "Cupboard", fn {section, pattern} ->
      if Regex.match?(pattern, name), do: section
    end)
  end

  def order, do: ["Fruit & veg", "Fish & meat", "Dairy & eggs", "Bakery", "Cupboard"]
  def tone("Fruit & veg"), do: "bg-sage text-sage-ink"
  def tone("Fish & meat"), do: "bg-blush text-blush-ink"
  def tone("Dairy & eggs"), do: "bg-butter text-butter-ink"
  def tone("Bakery"), do: "bg-lavender text-lavender-ink"
  def tone(_), do: "bg-peach text-peach-ink"
end
