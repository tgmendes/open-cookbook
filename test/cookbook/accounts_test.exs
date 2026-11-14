defmodule Cookbook.AccountsTest do
  use Cookbook.DataCase, async: true

  alias Cookbook.Accounts
  alias Cookbook.Accounts.User

  @allowed_email "test@example.com"

  describe "get_or_create_user_by_email/1" do
    test "creates a new user for the allowed email" do
      assert {:ok, %User{email: @allowed_email}} =
               Accounts.get_or_create_user_by_email(@allowed_email)
    end

    test "returns existing user if already created" do
      {:ok, user1} = Accounts.get_or_create_user_by_email(@allowed_email)
      {:ok, user2} = Accounts.get_or_create_user_by_email(@allowed_email)
      assert user1.id == user2.id
    end

    test "trims and downcases email" do
      {:ok, user} = Accounts.get_or_create_user_by_email("  TEST@EXAMPLE.COM  ")
      assert user.email == @allowed_email
    end

    test "rejects unauthorized email" do
      assert {:error, :unauthorized} =
               Accounts.get_or_create_user_by_email("hacker@evil.com")
    end
  end

  describe "create_login_token/1" do
    test "creates a token for a user" do
      {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)
      assert {:ok, raw_token} = Accounts.create_login_token(user)
      assert is_binary(raw_token)
      assert String.length(raw_token) > 20
    end
  end

  describe "request_login_token/1" do
    test "limits delivery requests to one per minute" do
      assert {:ok, user, _raw} = Accounts.request_login_token(@allowed_email)
      assert {:error, :rate_limited} = Accounts.request_login_token(@allowed_email)

      from(token in Accounts.LoginToken, where: token.user_id == ^user.id)
      |> Repo.update_all(
        set: [
          expires_at:
            DateTime.utc_now() |> DateTime.add(8 * 60, :second) |> DateTime.truncate(:second)
        ]
      )

      assert {:ok, _, _} = Accounts.request_login_token(@allowed_email)
    end

    test "malformed and unauthorized addresses are rejected" do
      for email <- [nil, %{}, "", "other@example.com"] do
        assert {:error, :unauthorized} = Accounts.request_login_token(email)
      end
    end
  end

  describe "verify_login_token/1" do
    test "rejects malformed tokens without raising" do
      for token <- [nil, %{}, [], 12, ""] do
        assert {:error, :invalid_token} = Accounts.verify_login_token(token)
      end
    end

    test "rejects a token when its owner is no longer allowed" do
      {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)
      {:ok, token} = Accounts.create_login_token(user)
      user |> Ecto.Changeset.change(email: "removed@example.com") |> Repo.update!()
      assert {:error, :invalid_token} = Accounts.verify_login_token(token)
    end

    test "only one concurrent consumer can claim a token" do
      {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)
      {:ok, token} = Accounts.create_login_token(user)
      supervisor = start_supervised!(Task.Supervisor)

      results =
        1..2
        |> Enum.map(fn _ ->
          Task.Supervisor.async_nolink(supervisor, fn -> Accounts.verify_login_token(token) end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    end

    test "verifies a valid token and returns the user" do
      {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)
      {:ok, raw_token} = Accounts.create_login_token(user)

      assert {:ok, verified_user} = Accounts.verify_login_token(raw_token)
      assert verified_user.id == user.id
    end

    test "rejects an already-used token" do
      {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)
      {:ok, raw_token} = Accounts.create_login_token(user)

      assert {:ok, _user} = Accounts.verify_login_token(raw_token)
      assert {:error, :invalid_token} = Accounts.verify_login_token(raw_token)
    end

    test "rejects an invalid token" do
      assert {:error, :invalid_token} = Accounts.verify_login_token("bogus-token")
    end

    test "rejects an expired token" do
      {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)
      {:ok, raw_token} = Accounts.create_login_token(user)

      # Manually expire the token
      hashed = :crypto.hash(:sha256, raw_token) |> Base.encode64()
      token = Repo.get_by!(Cookbook.Accounts.LoginToken, token: hashed)

      token
      |> Ecto.Changeset.change(expires_at: ~U[2020-01-01 00:00:00Z])
      |> Repo.update!()

      assert {:error, :invalid_token} = Accounts.verify_login_token(raw_token)
    end
  end
end
