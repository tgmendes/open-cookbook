defmodule Cookbook.ShoppingSectionsTest do
  use ExUnit.Case, async: true
  alias Cookbook.Planner.ShoppingSections

  test "classifies whole ingredient words with a cupboard fallback" do
    assert ShoppingSections.section("Fresh carrots") == "Fruit & veg"
    assert ShoppingSections.section("Salmon fillets") == "Fish & meat"
    assert ShoppingSections.section("Greek yoghurt") == "Dairy & eggs"
    assert ShoppingSections.section("Crusty loaf") == "Bakery"
    assert ShoppingSections.section("Eggplant") == "Fruit & veg"
    assert ShoppingSections.section("Coconut milk") == "Cupboard"
    assert ShoppingSections.section("Mystery seasoning") == "Cupboard"
  end
end
