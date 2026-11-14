defmodule Cookbook.ApiTokensTest do
  use Cookbook.DataCase, async: true
  alias Cookbook.Accounts

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")
    %{user: user}
  end

  test "issues an owner-bound token and stores only its hash", %{user: user} do
    assert {:ok, record, raw} = Accounts.create_api_token(user, "Claude")
    assert {:ok, authenticated} = Accounts.authenticate_api_token(raw)
    assert authenticated.id == user.id
    assert DateTime.compare(record.expires_at, DateTime.utc_now()) == :gt

    assert %{rows: [[hash]]} =
             Repo.query!("SELECT token_hash FROM api_tokens WHERE id = $1", [
               Ecto.UUID.dump!(record.id)
             ])

    refute hash == raw
    assert byte_size(hash) == 32
    assert [%{name: "Claude"} = metadata] = Accounts.list_api_tokens(user)
    refute Map.has_key?(metadata, :token_hash)
    refute Map.has_key?(metadata, :raw_token)
  end

  test "revocation immediately denies authentication", %{user: user} do
    {:ok, record, raw} = Accounts.create_api_token(user, "Claude")
    assert :ok = Accounts.revoke_api_token(user, record.id)
    assert {:error, :unauthorized} = Accounts.authenticate_api_token(raw)
    assert :ok = Accounts.revoke_api_token(user, record.id)
  end

  test "expired tokens are rejected", %{user: user} do
    {:ok, record, raw} = Accounts.create_api_token(user, "Claude")

    Repo.query!("UPDATE api_tokens SET expires_at = $1 WHERE id = $2", [
      ~U[2020-01-01 00:00:00Z],
      Ecto.UUID.dump!(record.id)
    ])

    assert {:error, :unauthorized} = Accounts.authenticate_api_token(raw)
  end

  test "tokens stop working when the owner email changes", %{user: user} do
    {:ok, _record, raw} = Accounts.create_api_token(user, "Claude")
    user |> Ecto.Changeset.change(email: "removed@example.com") |> Repo.update!()
    assert {:error, :unauthorized} = Accounts.authenticate_api_token(raw)
    assert {:error, :unauthorized} = Accounts.create_api_token(user, "stale identity")
  end

  test "token operations are owner scoped", %{user: user} do
    {:ok, record, _raw} = Accounts.create_api_token(user, "Claude")

    other =
      %Accounts.User{} |> Accounts.User.changeset(%{email: "other@example.com"}) |> Repo.insert!()

    assert [] == Accounts.list_api_tokens(other)
    assert {:error, :not_found} = Accounts.revoke_api_token(other, record.id)
    assert {:error, :not_found} = Accounts.revoke_api_token(user, "bad-id")
  end

  test "invalid names are rejected", %{user: user} do
    for name <- ["", "  ", nil, %{}, String.duplicate("x", 101)] do
      assert {:error, _} = Accounts.create_api_token(user, name)
    end
  end

  test "magic links and API credentials are not interchangeable", %{user: user} do
    {:ok, magic} = Accounts.create_login_token(user)
    {:ok, _record, raw} = Accounts.create_api_token(user, "Claude")
    assert {:error, :unauthorized} = Accounts.authenticate_api_token(magic)
    assert {:error, :invalid_token} = Accounts.verify_login_token(raw)

    for invalid <- [nil, "", %{}, [], "bogus"] do
      assert {:error, :unauthorized} = Accounts.authenticate_api_token(invalid)
    end
  end
end
