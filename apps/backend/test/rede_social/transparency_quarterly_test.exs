defmodule RedeSocial.TransparencyQuarterlyTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Identification, Moderation, Repo}
  alias RedeSocial.Identification.Order
  alias RedeSocial.Registro.Entry
  alias RedeSocial.Transparency.Quarterly

  defp quarter_start, do: Quarterly.quarter_start(Date.utc_today())

  # Um instante depois de o trimestre de hoje acabar em Brasília.
  defp after_quarter do
    quarter_start()
    |> Date.shift(month: 3)
    |> DateTime.new!(~T[04:00:00], "Etc/UTC")
  end

  test "o rótulo do trimestre vai e volta" do
    assert Quarterly.label(~D[2026-08-15]) == "2026-T3"
    assert Quarterly.quarter_start(~D[2026-08-15]) == ~D[2026-07-01]
    assert Quarterly.first_day("2026-T3") == {:ok, ~D[2026-07-01]}
    assert Quarterly.first_day("2026-T5") == {:error, :invalid_quarter}
    assert Quarterly.first_day("x") == {:error, :invalid_quarter}
  end

  test "conta remoções por regra, recursos e ordens, sem expor processo em segredo" do
    moderator = moderator_fixture()
    author = account_fixture()
    {:ok, removed} = Moderation.remove(moderator, post_fixture(author), 8)
    {:ok, _} = Moderation.remove(moderator, post_fixture(author), 8)
    {:ok, appeal} = Moderation.appeal(author, removed, "")
    {:ok, _} = Moderation.decide(moderator_fixture(), appeal, "restore")

    {:ok, officer} = Identification.grant_legal_officer(account_fixture())
    for secret <- [true, false], do: open_order(officer, secret)

    report = Quarterly.build(quarter_start())

    assert report.moderacao.remocoes_por_regra == %{"8" => 2}
    assert report.moderacao.recursos == %{devolvidos: 1, mantida_a_remocao: 0}
    assert report.ordens_judiciais.recebidas == 2
    assert report.ordens_judiciais.cumpridas == 2
    assert report.ordens_judiciais.em_segredo_de_justica == 1
    assert report.ordens_judiciais.por_juizo == %{"Vara pública" => 1}
  end

  test "publica uma vez, depois do fim, com o hash do texto no registro público" do
    assert Quarterly.publish(quarter_start()) == {:error, :quarter_not_over}

    {:ok, report} = Quarterly.publish(quarter_start(), after_quarter())

    assert report.sha256 ==
             :crypto.hash(:sha256, report.body) |> Base.encode16(case: :lower)

    entry = Repo.get_by!(Entry, position: report.registro_position)
    assert entry.kind == "relatorio"
    assert entry.data =~ report.sha256

    assert Quarterly.publish(quarter_start(), after_quarter()) == {:error, :already_published}
    assert [%{quarter: quarter}] = Quarterly.list()
    assert quarter == Quarterly.label(quarter_start())
  end

  defp open_order(officer, secret) do
    court = if secret, do: "Vara em segredo", else: "Vara pública"

    %Order{
      account_id: account_fixture().id,
      requested_by_id: officer.id,
      court: court,
      secret_case: secret,
      status: "opened",
      opened_at: DateTime.truncate(DateTime.utc_now(), :second)
    }
    |> Repo.insert!()
  end
end
