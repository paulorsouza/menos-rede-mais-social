defmodule RedeSocial.PrivacyTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Accounts, Moderation, Privacy, Repo, Social}
  alias RedeSocial.Moderation.Action

  test "o arquivo traz tudo o que a rede guarda, menos o CPF, que ela não tem" do
    account = account_fixture()
    friend = account_fixture()
    post_fixture(account, body: "Meu primeiro post")
    {:ok, true} = Social.toggle_like(account, post_fixture(friend))
    {:ok, true} = Social.toggle_follow(account, friend)
    {:ok, true} = Social.toggle_follow(friend, account)

    export = Privacy.export(account)

    assert export.account.nickname == account.nickname
    assert [%{body: "Meu primeiro post"}] = export.posts
    assert [%{post_id: _}] = export.likes
    assert [%{nickname: nickname}] = export.following
    assert nickname == friend.nickname
    assert [%{nickname: ^nickname}] = export.followers

    json = Jason.encode!(export)
    refute json =~ "cpf_fingerprint"
    refute json =~ "cpf_ciphertext"
  end

  test "apagar pede o apelido e leva tudo junto" do
    account = account_fixture()
    friend = account_fixture()
    post = post_fixture(account)
    {:ok, true} = Social.toggle_like(friend, post)
    {:ok, true} = Social.toggle_follow(friend, account)

    assert Privacy.delete_account(account, "outro.apelido") == {:error, :confirmation}
    assert Privacy.delete_account(account, " #{String.upcase(account.nickname)} ") == :ok

    assert Accounts.get_account(account.id) == nil
    assert Social.get_post(post.id) == nil
    assert Social.follow_counts(friend).following == 0
  end

  test "a decisão da moderação fica no registro público, sem o vínculo" do
    account = account_fixture()
    post = post_fixture(account)
    {:ok, _post} = Moderation.remove(moderator_fixture(), post, 8)

    :ok = Privacy.delete_account(account, account.nickname)

    assert [%Action{action: "removed", rule: 8, post_id: nil}] = Repo.all(Action)
    assert Moderation.public_stats().removals_by_rule == %{8 => 1}
  end
end
