defmodule RedeSocial.ModerationTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Moderation, Social}

  setup do
    author = account_fixture()
    %{author: author, post: post_fixture(author), moderator: moderator_fixture()}
  end

  describe "report/3" do
    test "cita uma regra que quem denuncia pode usar", %{post: post} do
      reporter = account_fixture()

      assert Moderation.report(reporter, post, 6) == :ok
      # A regra 9 (ordem judicial) é só da moderação.
      assert Moderation.report(reporter, post, 9) == {:error, :invalid_rule}
      assert Moderation.report(reporter, post, 42) == {:error, :invalid_rule}
    end

    test "ninguém denuncia o próprio post", %{author: author, post: post} do
      assert Moderation.report(author, post, 6) == {:error, :own_post}
    end

    test "cada pessoa conta uma vez por post", %{post: post} do
      reporter = account_fixture()
      :ok = Moderation.report(reporter, post, 6)
      :ok = Moderation.report(reporter, post, 2)

      assert [%{total: 1, reports: [%{rule: 6, count: 1}]}] = Moderation.queue()
    end
  end

  describe "queue/0" do
    test "junta as denúncias por regra e põe os mais denunciados primeiro", %{post: post} do
      other = post_fixture(account_fixture())
      for _ <- 1..2, do: :ok = Moderation.report(account_fixture(), post, 6)
      :ok = Moderation.report(account_fixture(), post, 8)
      :ok = Moderation.report(account_fixture(), other, 2)

      assert [first, second] = Moderation.queue()
      assert first.post.id == post.id
      assert first.total == 3
      assert first.reports == [%{rule: 6, count: 2}, %{rule: 8, count: 1}]
      assert second.post.id == other.id
    end
  end

  describe "remove/3 e keep/2" do
    test "só a moderação remove, sempre citando uma regra", %{post: post, moderator: moderator} do
      assert Moderation.remove(account_fixture(), post, 6) == {:error, :not_moderator}
      assert Moderation.remove(moderator, post, nil) == {:error, :invalid_rule}
    end

    test "remover tira o post do ar, fecha as denúncias e avisa o autor", context do
      %{author: author, post: post, moderator: moderator} = context
      :ok = Moderation.report(account_fixture(), post, 6)

      assert {:ok, removed} = Moderation.remove(moderator, post, 6)
      assert removed.removal_rule == 6
      assert Social.get_post(post.id) == nil
      assert Moderation.queue() == []

      assert [%{kind: "removed", rule: 6}] = Moderation.notices(author)
      assert Moderation.unread_count(author) == 1
      assert Moderation.public_stats().removals_by_rule == %{6 => 1}
    end

    test "manter deixa o post no ar e tira da fila", %{post: post, moderator: moderator} do
      :ok = Moderation.report(account_fixture(), post, 3)

      assert {:ok, _action} = Moderation.keep(moderator, post)
      assert Social.get_post(post.id)
      assert Moderation.queue() == []
      assert Moderation.public_stats().kept == 1
    end
  end

  describe "appeal/3 e decide/3" do
    setup %{post: post, moderator: moderator} do
      {:ok, removed} = Moderation.remove(moderator, post, 8)
      %{removed: removed}
    end

    test "só o autor recorre, e uma vez por remoção", %{author: author, removed: removed} do
      assert Moderation.appeal(account_fixture(), removed, "não é spam") == {:error, :not_found}
      assert {:ok, _appeal} = Moderation.appeal(author, removed, "não é spam")
      assert Moderation.appeal(author, removed, "de novo") == {:error, :already_appealed}
      assert Moderation.appeal_status(removed) == "pending"
    end

    test "quem removeu não julga o recurso", context do
      %{author: author, removed: removed, moderator: moderator} = context
      {:ok, appeal} = Moderation.appeal(author, removed, "")

      assert Moderation.decide(moderator, appeal, "restore") == {:error, :same_moderator}
    end

    test "quem recorreu não julga o próprio recurso, mesmo sendo da moderação", context do
      %{author: author, removed: removed} = context
      {:ok, author} = Moderation.grant_moderator(author)
      {:ok, appeal} = Moderation.appeal(author, removed, "")

      assert Moderation.decide(author, appeal, "restore") == {:error, :same_moderator}
    end

    test "outra pessoa da moderação pode devolver o post", %{author: author, removed: removed} do
      {:ok, appeal} = Moderation.appeal(author, removed, "Era um aviso, não spam.")
      other_moderator = moderator_fixture()

      assert {:ok, _appeal} = Moderation.decide(other_moderator, appeal, "restore")
      assert Social.get_post(removed.id)
      assert [%{kind: "restored"}, %{kind: "removed"}] = Moderation.notices(author)

      assert %{restored: 1, upheld: 0, pending: 0} = Moderation.public_stats().appeals
      assert Moderation.decide(other_moderator, appeal, "uphold") == {:error, :already_decided}
    end

    test "ou manter a remoção", %{author: author, removed: removed} do
      {:ok, appeal} = Moderation.appeal(author, removed, "")

      assert {:ok, _appeal} = Moderation.decide(moderator_fixture(), appeal, "uphold")
      assert Social.get_post(removed.id) == nil
      assert Moderation.appeal_status(Social.get_post_any(removed.id)) == "uphold"
    end
  end
end
