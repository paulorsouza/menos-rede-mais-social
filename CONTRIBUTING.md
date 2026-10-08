# Como contribuir

Obrigado por querer ajudar. Este projeto só faz sentido se for construído às claras, então as regras abaixo existem para que qualquer pessoa consiga entender e conferir cada mudança.

## Antes de começar

- Leia as [regras pétreas](specs/regras-petreas.md). Um pull request ou uma RFC que enfraqueça qualquer uma delas é recusado, por melhor que seja a intenção.
- Mudanças pequenas (correção de bug, texto, teste) podem ir direto num pull request.
- Mudanças nas regras da rede precisam de uma RFC aprovada antes do código. Isso inclui qualquer coisa em `params/`, a lógica do feed, a divisão do dinheiro dos anúncios, a moderação e os dados que guardamos sobre as pessoas. O processo está em [docs/rfcs](docs/rfcs/README.md).

## Idioma

Documentação, comentários e mensagens de commit são escritos em português. Nomes no código (funções, variáveis, módulos) ficam em inglês, que é o padrão das bibliotecas e ferramentas que usamos. Textos que aparecem para quem usa a rede são sempre em português.

## Revisão

Todo pull request precisa da aprovação de duas pessoas mantenedoras antes de entrar. Ninguém aprova o próprio código. Enquanto o projeto tiver só uma pessoa mantenedora, a regra vale assim que entrar a segunda.

## Regras para o código

- **Feed e anúncios precisam ser reprodutíveis.** Nada de número de ponto flutuante, de aleatoriedade ou de relógio dentro dos motores. O horário entra como parâmetro, e empates são decididos por id. Se alguém rodar o mesmo cálculo com os mesmos dados, o resultado tem que bater.
- **Dinheiro em centavos inteiros.** Toda divisão diz para onde vai a sobra.
- **Nenhum segredo no repositório.** Senhas, chaves e tokens ficam em variáveis de ambiente ou no cofre. O CI procura segredos em cada commit.
- **Dados pessoais no mínimo.** Antes de guardar um dado novo sobre alguém, pergunte se a rede precisa mesmo dele. Se precisar, isso entra numa RFC.

## Antes de abrir o pull request

Rode o que o CI vai rodar:

```bash
cd services && cargo fmt --all && cargo clippy --all-targets -- -D warnings && cargo test
cd apps/web && npm run build
cd apps/backend && mix format && mix test
```

## Convivência

Discorde de ideias, não de pessoas. Discussões técnicas ficam nas issues e nos pull requests, que são públicos, para que qualquer pessoa entenda por que uma decisão foi tomada.
