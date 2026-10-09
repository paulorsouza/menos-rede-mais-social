# Dados de demonstração. Só rodam com o modo de demonstração ligado (dev).
#
#     mix run priv/repo/seeds.exs
#
# Para começar a demo do zero: mix ecto.reset
if RedeSocial.Demo.enabled?() do
  RedeSocial.Demo.Seeds.run()
end
