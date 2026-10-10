defmodule RedeSocial.Transparency.Quarterly do
  @moduledoc """
  O relatório de transparência de cada trimestre (seção 5 do plano): remoções
  por regra, recursos, denúncias, ordens judiciais, anúncios recusados e as
  contas dos meses fechados.

  Fecha no primeiro dia depois do trimestre. O texto publicado é JSON
  canônico, e o hash dele entra no registro público: quem baixa o relatório
  confere que é o mesmo que foi publicado naquele dia. Um trimestre só é
  publicado uma vez.
  """

  import Ecto.Query

  alias RedeSocial.{Registro, Repo}
  alias RedeSocial.Ads.Campaign
  alias RedeSocial.Identification.Order
  alias RedeSocial.Moderation.{Action, Appeal, Report}
  alias RedeSocial.Payments.Month
  alias RedeSocial.Transparency.Report, as: Published

  # O trimestre é o de Brasília, como o mês dos pagamentos.
  @brasilia_offset -3 * 3600

  @doc "O trimestre de uma data, como \"2026-T3\"."
  def label(%Date{year: year, month: month}), do: "#{year}-T#{div(month - 1, 3) + 1}"

  @doc "O primeiro dia do trimestre de uma data."
  def quarter_start(%Date{year: year, month: month}),
    do: Date.new!(year, div(month - 1, 3) * 3 + 1, 1)

  @doc "O primeiro dia do trimestre de um rótulo, ou erro."
  def first_day(label) when is_binary(label) do
    with [year, "T" <> q] <- String.split(label, "-"),
         {year, ""} <- Integer.parse(year),
         {q, ""} when q in 1..4 <- Integer.parse(q) do
      {:ok, Date.new!(year, (q - 1) * 3 + 1, 1)}
    else
      _ -> {:error, :invalid_quarter}
    end
  end

  def first_day(_label), do: {:error, :invalid_quarter}

  @doc "Os números do trimestre de uma data, sem publicar."
  def build(%Date{} = date) do
    first = quarter_start(date)
    {from, to} = range(first)

    %{
      trimestre: label(first),
      de: first,
      ate: Date.add(Date.shift(first, month: 3), -1),
      moderacao: moderation(from, to),
      ordens_judiciais: orders(from, to),
      anuncios: ads(from, to),
      contas: accounts(first)
    }
  end

  @doc """
  Publica o trimestre: guarda o texto, põe o hash no registro público e
  devolve o relatório. Trimestre que ainda não acabou não fecha.
  """
  def publish(%Date{} = date, now \\ DateTime.utc_now()) do
    first = quarter_start(date)
    quarter = label(first)
    {_from, to} = range(first)

    cond do
      DateTime.compare(now, to) == :lt ->
        {:error, :quarter_not_over}

      Repo.get_by(Published, quarter: quarter) ->
        {:error, :already_published}

      true ->
        body = first |> build() |> Registro.canonical_json()
        sha = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
        now = DateTime.truncate(now, :second)

        Repo.transaction(fn ->
          report =
            Repo.insert!(%Published{quarter: quarter, body: body, sha256: sha, published_at: now})

          {:ok, entry} =
            Registro.append("relatorio", %{trimestre: quarter, sha256: sha, em: now})

          report |> Ecto.Changeset.change(registro_position: entry.position) |> Repo.update!()
        end)
    end
  end

  def list do
    Repo.all(
      from r in Published,
        order_by: [desc: r.quarter],
        select: %{
          quarter: r.quarter,
          sha256: r.sha256,
          registro_position: r.registro_position,
          published_at: r.published_at
        }
    )
  end

  def get(quarter), do: Repo.get_by(Published, quarter: quarter)

  defp range(first) do
    start = fn date ->
      date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.add(-@brasilia_offset, :second)
    end

    {start.(first), start.(Date.shift(first, month: 3))}
  end

  defp moderation(from, to) do
    actions =
      Repo.all(
        from a in Action,
          where: a.inserted_at >= ^from and a.inserted_at < ^to,
          group_by: [a.action, a.rule],
          select: {a.action, a.rule, count(a.id)}
      )

    reports =
      Repo.all(
        from r in Report,
          where: r.inserted_at >= ^from and r.inserted_at < ^to,
          group_by: r.rule,
          select: {r.rule, count(r.id)}
      )

    appeals =
      Repo.all(
        from a in Appeal,
          where: a.decided_at >= ^from and a.decided_at < ^to,
          group_by: a.outcome,
          select: {a.outcome, count(a.id)}
      )
      |> Map.new()

    %{
      denuncias_por_regra: by_rule(reports),
      remocoes_por_regra: by_rule(for {"removed", rule, n} <- actions, do: {rule, n}),
      mantidos_depois_de_denuncia: Enum.sum(for {"kept", _rule, n} <- actions, do: n),
      recursos: %{
        devolvidos: Map.get(appeals, "restore", 0),
        mantida_a_remocao: Map.get(appeals, "uphold", 0)
      }
    }
  end

  defp orders(from, to) do
    received =
      Repo.aggregate(
        from(o in Order, where: o.inserted_at >= ^from and o.inserted_at < ^to),
        :count
      )

    opened =
      Repo.all(
        from o in Order,
          where: o.opened_at >= ^from and o.opened_at < ^to,
          select: %{court: o.court, case_number: o.case_number, secret: o.secret_case}
      )

    %{
      recebidas: received,
      cumpridas: length(opened),
      em_segredo_de_justica: Enum.count(opened, & &1.secret),
      por_juizo:
        opened
        |> Enum.reject(& &1.secret)
        |> Enum.frequencies_by(& &1.court)
    }
  end

  defp ads(from, to) do
    reviewed =
      Repo.all(
        from c in Campaign,
          where: c.reviewed_at >= ^from and c.reviewed_at < ^to,
          select: {c.status, c.rejection_rule}
      )

    %{
      campanhas_analisadas: length(reviewed),
      recusadas_por_regra:
        by_rule(
          for({:rejected, rule} <- reviewed, do: rule)
          |> Enum.frequencies()
          |> Map.to_list()
        )
    }
  end

  defp accounts(first) do
    months = for n <- 0..2, do: Date.shift(first, month: n)

    Repo.all(
      from m in Month,
        where: m.month in ^months,
        order_by: [asc: m.month],
        select: %{
          mes: m.month,
          receita_centavos: m.revenue_cents,
          criadores_centavos: m.creators_cents,
          fundo_centavos: m.fund_cents,
          registro: m.registro_position
        }
    )
  end

  # Chaves de texto, para o JSON canônico.
  defp by_rule(pairs), do: Map.new(pairs, fn {rule, n} -> {Integer.to_string(rule), n} end)
end
