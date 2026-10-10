defmodule RedeSocialWeb.AccountController do
  use RedeSocialWeb, :controller

  alias RedeSocial.{Accounts, Social}
  alias RedeSocialWeb.Present

  action_fallback RedeSocialWeb.FallbackController

  def show(conn, %{"nickname" => nickname}) do
    viewer = conn.assigns.current_account

    with %{} = account <- Accounts.get_by_nickname(nickname) do
      posts = Social.list_author_posts(account, viewer)
      stats = Social.stats(posts, viewer)

      json(conn, %{
        account: Present.account(account),
        private: not Social.can_see_posts?(account, viewer),
        counts: Map.put(Social.follow_counts(account), :posts, length(posts)),
        following: Social.following?(viewer, account),
        posts: Enum.map(posts, &Present.post(&1, Map.fetch!(stats, &1.id)))
      })
    end
  end

  def follow(conn, %{"nickname" => nickname}) do
    with %{} = account <- Accounts.get_by_nickname(nickname),
         {:ok, following} <- Social.toggle_follow(conn.assigns.current_account, account) do
      json(conn, %{following: following, counts: Social.follow_counts(account)})
    end
  end
end
