defmodule RedeSocial.RemovalRequestsTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Identification, Moderation, RemovalRequests, Repo}
  alias RedeSocial.Moderation.Notice
  alias RedeSocial.Registro.Entry
  alias RedeSocial.Social.Post
  alias RedeSocial.Transparency.Quarterly

  setup do
    {:ok, officer} = Identification.grant_legal_officer(account_fixture())
    author = account_fixture()
    %{officer: officer, author: author, post: post_fixture(author)}
  end

  defp request(officer, post, attrs) do
    RemovalRequests.create(
      officer,
      post.id,
      Map.merge(
        %{"authority" => "1ª Vara Cível de Campinas", "legal_basis" => "Marco Civil, art. 19"},
        attrs
      )
    )
  end

  test "só o setor jurídico registra, sempre com quem pediu e a base legal", c do
    assert RemovalRequests.create(account_fixture(), c.post.id, %{}) ==
             {:error, :not_legal_officer}

    assert {:error, changeset} =
             RemovalRequests.create(c.officer, c.post.id, %{"kind" => "judicial"})

    assert %{authority: [_], legal_basis: [_]} = errors_on(changeset)

    assert {:ok, %{status: "recebido"}} = request(c.officer, c.post, %{"kind" => "judicial"})
  end

  test "ordem judicial tira o post citando a regra 9, avisa o autor e vai para o registro", c do
    {:ok, req} =
      request(c.officer, c.post, %{"kind" => "judicial", "case_number" => "0001234-56"})

    assert RemovalRequests.refuse(c.officer, req, "não") == {:error, :judicial_order}
    {:ok, done} = RemovalRequests.comply(c.officer, req)

    assert done.status == "cumprido"
    assert done.rule == 9
    assert %Post{removal_rule: 9, removed_at: %DateTime{}} = Repo.get!(Post, c.post.id)
    assert Repo.get_by!(Notice, post_id: c.post.id).rule == 9

    entry = Repo.get_by!(Entry, position: done.registro_position)
    assert entry.kind == "pedido-remocao"
    assert entry.data =~ "Marco Civil"
    assert entry.data =~ "0001234-56"

    assert RemovalRequests.comply(c.officer, done) == {:error, :already_decided}
  end

  test "pedido de outro órgão só tira o post se ele quebra uma regra pública", c do
    {:ok, req} = request(c.officer, c.post, %{"kind" => "outro", "authority" => "Ministério X"})

    assert RemovalRequests.comply(c.officer, req) == {:error, :invalid_rule}
    assert RemovalRequests.comply(c.officer, req, 9) == {:error, :invalid_rule}
    assert RemovalRequests.refuse(c.officer, req, " ") == {:error, :reason_required}

    {:ok, refused} = RemovalRequests.refuse(c.officer, req, "O post não quebra nenhuma regra.")
    assert refused.status == "recusado"
    assert is_nil(Repo.get!(Post, c.post.id).removed_at)

    other = post_fixture(c.author)
    {:ok, req} = request(c.officer, other, %{"kind" => "outro"})
    {:ok, done} = RemovalRequests.comply(c.officer, req, 6)
    assert Repo.get!(Post, other.id).removal_rule == 6
    assert done.rule == 6
  end

  test "processo sigiloso não mostra o número no registro nem o órgão no relatório", c do
    {:ok, req} =
      request(c.officer, c.post, %{
        "kind" => "judicial",
        "case_number" => "segredo-123",
        "secret_case" => true
      })

    {:ok, done} = RemovalRequests.comply(c.officer, req)
    entry = Repo.get_by!(Entry, position: done.registro_position)
    refute entry.data =~ "segredo-123"
    assert entry.data =~ "sigiloso"

    report = Quarterly.build(Date.utc_today())
    assert report.pedidos_de_remocao.judiciais == %{recebidos: 1, cumpridos: 1}
    assert report.pedidos_de_remocao.em_segredo_de_justica == 1
    assert report.pedidos_de_remocao.por_orgao_e_base_legal == %{}
  end

  test "post que já tinha saído conta o pedido, sem remover de novo", c do
    {:ok, _} = Moderation.remove(moderator_fixture(), c.post, 8)
    {:ok, req} = request(c.officer, c.post, %{"kind" => "judicial"})

    {:ok, done} = RemovalRequests.comply(c.officer, req)
    assert done.status == "cumprido"
    assert Repo.get!(Post, c.post.id).removal_rule == 8
  end
end
