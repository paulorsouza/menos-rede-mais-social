# -rede+social

Um exemplo de rede social pública, de código aberto e sem fins lucrativos, feito com as ferramentas e as leis do Brasil. Não pretende ser a rede social do país: a ideia é servir de ponto de partida para quem quiser fazer uma de verdade. No desenho, quem paga a estrutura é um investidor que não busca lucro, de preferência do setor público, e a rede é de quem usa. O porquê está no [manifesto](MANIFESTO.md), e o como está no [plano inicial](docs/plano-inicial.md). As regras que nenhuma decisão pode quebrar estão nas [regras pétreas](specs/regras-petreas.md).

Este repositório já tem uma demonstração completa: feed com cinco modos e o "por que estou vendo isto", textos curtos, fotos, vídeos e shorts, anúncios nacionais e regionais com rateio entre criadores, painel do criador e página de transparência. O login gov.br é simulado e os dados são fictícios.

## Rodando a demonstração

Você só precisa do Docker. Na raiz do repositório:

```bash
docker compose up --build
```

Na primeira vez demora alguns minutos. Depois, abra http://localhost:5173 e entre como uma das pessoas de exemplo. O passo a passo para apresentar está em [docs/demo.md](docs/demo.md).

Se a porta 5432 já estiver em uso na sua máquina, crie um arquivo `.env` na raiz com `DB_PORT=5433`.

Para voltar a demo ao estado inicial:

```bash
docker compose exec backend mix demo.reset
```

## Como o repositório está organizado

```
specs/regras-petreas.md  a constituição do projeto: o que nunca pode mudar
apps/web/                front em React (Vite + TypeScript)
apps/backend/            backend em Elixir (Phoenix + Ecto + PostgreSQL)
services/                serviços em Rust (workspace Cargo)
  feed-engine/           os modos de feed, determinísticos e auditáveis
  ads-engine/            exibições, faixas de pagamento e rateio dos shorts
  engine-server/         servidor HTTP dos dois motores, usado pelo backend
params/                  parâmetros públicos do feed e dos anúncios
proto/                   contratos gRPC entre o backend e os serviços em Rust
docs/plano-inicial.md    o plano: produto, dinheiro, arquitetura, governança e fases
docs/demo.md             roteiro para apresentar a demonstração
docs/rfcs/               propostas de mudança nas regras da rede
```

O backend em Elixir atende o app e a web e coordena o resto. O que precisa ser auditado (feed e anúncios) fica em Rust, e o backend só pergunta ao motor: "em que ordem mostro estes posts para esta pessoa?" e "como divido o dinheiro deste anúncio?". Os números que mexem no feed e no dinheiro de criadores estão em `params/`, num formato que qualquer pessoa consegue ler, e só mudam por RFC. A página de transparência mostra o hash do arquivo que o motor está usando.

Por enquanto o motor conversa com o backend em JSON, com os mesmos campos dos contratos em `proto/`. O gRPC entra quando os dois lados estiverem estáveis.

## O que já funciona

- **Feed** por grafo, com quatro modos (na bolha, furando a bolha, meio a meio e por data), todos calculados pelo motor em Rust. Não existe categoria nem tag: a bolha sugere o que curtem as pessoas que curtem o que você curte, e furando a bolha mostra o que ninguém perto de você tocou. Cada post mostra por que apareceu.
- **Em alta**, uma aba com a mesma lista para todo mundo: o que mais gente curtiu e salvou nas últimas horas, de todo tipo de post.
- **Contas** pelo Login Único do gov.br (OpenID Connect; sem credencial, a demo usa um gov.br simulado), com apelido e selo de verificado. O CPF não fica em texto: há uma impressão digital, que barra contas duplicadas, e uma cópia selada que só 3 de 5 guardiões abrem juntos, com ordem judicial. Conta básica, sem gov.br, não publica.
- **Ordem judicial** com os guardiões: cada um entrega a sua parte com uma prova, três abrem o CPF e os acessos uma única vez, e a abertura entra no registro público sem identificar a pessoa. O cofre está em `services/cofre`, com a linha de comando que os guardiões usam.
- **Moderação** com regras públicas e numeradas, denúncia no "?" de cada post, remoção citando a regra, aviso ao autor e recurso julgado por outra pessoa da moderação.
- **Menores de idade** com perfil privado e sem anúncio. **Seus dados**: baixar tudo e apagar a conta. **Registros de acesso** do Marco Civil, com o IP selado e apagados depois de seis meses.
- **Posts** de texto curto (140 caracteres, sem respostas), foto, vídeo e short, com curtidas, salvamentos e seguidores. É um campo só: o tipo sai do arquivo anexado (vídeo em pé vira short), e não tem tag para escolher.
- **Shorts** com um anúncio a cada 6. A receita é dividida entre os criadores do bloco, pelo tempo assistido, e a tela mostra o rateio na hora.
- **Vídeos** com anúncio só nos pontos que o criador escolheu. Quem é bronze não monetiza.
- **Anúncio regional**, mais barato, para quem é da mesma cidade do anunciante.
- **Painel do criador** com o pagamento por faixas decrescentes, calculado como no imposto de renda.
- **Transparência**: versão do motor, hash e conteúdo dos parâmetros em uso, números da rede e biblioteca pública de anúncios.

O que ainda é simulado ou não existe está listado no fim do [roteiro da demonstração](docs/demo.md#o-que-é-real-e-o-que-é-simulado).

## Desenvolvendo

Para trabalhar fora do Docker você vai precisar de Node 20.19 ou mais novo e Rust 1.85 ou mais novo. Elixir é opcional, porque o backend também roda no Docker. Quem usa Nix pode entrar no ambiente com `nix develop`.

Motor em Rust (testes e servidor na porta 7070):

```bash
cd services
cargo test
cargo run -p engine-server
```

Front fora do Docker, falando com o backend em :4000:

```bash
cd apps/web
npm install
npm run dev
```

Mais detalhes do backend, inclusive como rodar os testes, estão em [apps/backend/README.md](apps/backend/README.md).

## Conferir sem confiar na rede

A rede foi feita para ser conferida por quem não confia nela. Três coisas dá para conferir hoje, do seu computador.

**O binário do motor sai do código publicado.** Com Nix, compile duas vezes; a segunda recompila do zero e para com erro se um único byte mudar. O hash do binário é o mesmo para qualquer pessoa, e a CI assina os binários da `main` com o Sigstore.

```bash
nix build .#engine-server
nix build .#engine-server --rebuild
sha256sum result/bin/engine-server
```

**O seu feed seguiu as regras publicadas.** No app, toque no chip do motor e em "Baixar a conta deste feed". O verificador refaz a conta com o mesmo código, confere o recibo assinado pelo motor e confere que cada curtida, view e seguidor usado estava no retrato do grafo publicado.

```bash
cd services
cargo run -p verificador -- feed conta-do-feed.json --parametros ../params/feed.toml --registro entradas.json
```

**O registro público não foi reescrito.** Baixe o cabeçalho e as entradas na página de transparência (ou em `/api/registro` e `/api/registro/entradas`). Guarde o cabeçalho; da próxima vez, a prova de consistência mostra que nada do que estava nele foi trocado ou apagado.

```bash
cargo run -p verificador -- registro registro.json entradas.json
cargo run -p verificador -- registro registro.json entradas.json --anterior registro-antigo.json --consistencia prova.json
```

## Próximos passos

- Atestação de hardware no motor (AMD SEV-SNP ou Intel TDX), para provar qual binário está rodando agora.
- Cerimônia distribuída dos guardiões do CPF, e a chave do registro num cofre de hardware.
- Escala: vizinhos pré-calculados, tabelas particionadas e réplicas de leitura.
- Servidores gRPC em Rust a partir dos contratos em `proto/`.
- Fixar as actions do CI por hash de commit.

## Contribuindo

Leia o [CONTRIBUTING.md](CONTRIBUTING.md). Se você achou uma falha de segurança, não abra issue pública: siga o [SECURITY.md](SECURITY.md).

## Licença

[AGPL-3.0](LICENSE). Qualquer pessoa pode usar, estudar, modificar e redistribuir o código. Quem rodar uma versão modificada da rede como serviço, mesmo sem distribuir o programa, é obrigado a publicar o código dessa versão. É isso que impede alguém de pegar a rede, fechar e operar por conta própria.
