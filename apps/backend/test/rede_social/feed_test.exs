defmodule RedeSocial.FeedTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Engine, Feed, Social}

  setup do
    viewer = account_fixture()
    followed = account_fixture()
    from_followed = post_fixture(followed)
    from_stranger = post_fixture(account_fixture())
    {:ok, true} = Social.toggle_follow(viewer, followed)
    {:ok, true} = Social.toggle_like(viewer, from_stranger)

    %{
      viewer: viewer,
      followed: followed,
      from_followed: from_followed,
      from_stranger: from_stranger
    }
  end

  test "manda os candidatos ao motor e devolve na ordem dele, com os motivos", context do
    test_pid = self()

    Req.Test.stub(Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:engine_request, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "items" => [
          %{
            "post_id" => context.from_stranger.id,
            "score" => 2,
            "reasons" => [%{"kind" => "similar_engaged", "value" => 3}]
          },
          %{
            "post_id" => context.from_followed.id,
            "score" => 1,
            "reasons" => [%{"kind" => "you_follow"}]
          }
        ],
        "engine_version" => "0.1.0",
        "engine_build" => "dev",
        "params_version" => 1,
        "params_sha256" => "abc123"
      })
    end)

    {:ok, feed} = Feed.build(context.viewer, "bubble", [:text])

    assert Enum.map(feed.entries, & &1.post.id) ==
             [context.from_stranger.id, context.from_followed.id]

    assert hd(feed.entries).reasons == [%{"kind" => "similar_engaged", "value" => 3}]
    assert feed.engine.status == "ok"
    assert feed.engine.params_sha256 == "abc123"

    assert_received {:engine_request, request}
    assert request["mode"] == "bubble"

    # O motor recebe o grafo (quem curtiu o quê), não categoria nenhuma.
    me = request["viewer"]["id"]

    assert Enum.any?(
             request["edges"],
             &(&1["kind"] == "like" and &1["user_id"] == me and
                 &1["post_id"] == context.from_stranger.id)
           )

    refute Enum.any?(request["candidates"], &Map.has_key?(&1, "topics"))

    # O motor recebe números no lugar dos ids de conta, e quem a pessoa segue
    # tem o mesmo número do autor do post.
    [followed_number] = request["viewer"]["follows"]
    assert request["viewer"]["id"] != followed_number
    candidate = Enum.find(request["candidates"], &(&1["post_id"] == context.from_followed.id))
    assert candidate["author_id"] == followed_number
  end

  test "sem o motor, mostra só quem a pessoa segue, por data", context do
    Req.Test.stub(Engine, &Req.Test.transport_error(&1, :econnrefused))

    {:ok, feed} = Feed.build(context.viewer, "mixed", [:text])

    assert feed.engine.status == "offline"
    assert Enum.map(feed.entries, & &1.post.id) == [context.from_followed.id]
  end
end
