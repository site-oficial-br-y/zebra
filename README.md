# ZEBRA

Monte seu time com quem já jogou.

O dado sorteia um time campeão da história do futebol brasileiro. Você escala
um jogador daquele elenco — e o próximo sorteio pode não ser tão generoso.
Onze escolhas para montar um time que nunca existiu, e sete jogos até a
final contra os próprios campeões da história.

**Jogue:** https://site-oficial-br-y.github.io/zebra/

## A base

46 elencos campeões, de 1962 a 2024, com 439 jogadores distintos. Todos
conferidos em fonte — cada time registra a sua no campo `fonte` do
`elencos.json`.

Cobre os grandes e também quem ganhou fora do eixo: Guarani 1978 (o único
campeão brasileiro do interior), Coritiba 1985, Sport 1987, Bahia 1988 e
Atlético-PR 2001.

Três detalhes que a base resolve:

- **Nome igual nem sempre é a mesma pessoa.** Há quatro "Danilo", quatro
  "Alex", três "Gomes" e dois "Zico" — o do Flamengo e um do Sport de 87.
  Cada jogador tem id próprio.
- **O mesmo jogador aparece em vários elencos** (Everton Ribeiro em cinco).
  Escalado uma vez, some de todos.
- **Sem escudo nem foto.** Cada clube é uma bandeira de duas cores.

## Como jogar

Escolha a formação (oito esquemas, do 4-2-4 do Brasil de 58 ao 5-4-1) e a
postura — defensiva, equilibrada ou ofensiva. Elas mexem no ataque e nos
gols sofridos, discretamente: o extremo vai de −25% a +20%.

Role o dado, escale um jogador do elenco que saiu, repita até fechar os onze.
Posição cheia aparece apagada, jogador escalado some dos outros elencos e o
mesmo time não sai duas vezes na mesma partida. Três passes por partida.

O overall só aparece no fim: fechados os onze, o campo acende com as notas.

Depois vem a campanha — três jogos de grupo (quatro pontos para classificar)
e o mata-mata até a final, com o relógio correndo, pênaltis no empate e três
velocidades. Em "Jogo a jogo", cada partida espera o seu clique.

**Ganhar a final é a conquista.** O resto é estatística do resultado.

## Os arquivos

- `index.html` — o jogo, arquivo único, abre no celular sem internet
- `elencos.json` — os elencos campeões da história
- `elencos-2026.json` — os vinte times da Série A de 2026
- `elencos-sul.json` — os sul-americanos que aparecem na Libertadores
- `casca.html` + `js.txt` — a casca e a lógica, de onde o `tmpl.html` é montado
- `teste-formacoes.js` — confere as coordenadas das formações

Para reconstruir depois de editar a base ou o molde:

```
python3 build.py
node teste-formacoes.js
```
