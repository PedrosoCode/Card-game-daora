# Cadeia de Comando

Card game 1v1 em Godot 4.3+ (Gwent + Magic + Poker), com UI 100% em `Control`.
As regras completas estão em [REGRAS.md](REGRAS.md).

## Plataformas

| | Como gerar | Saída |
|---|---|---|
| Desktop | F5 no editor | — |
| Web (Chrome etc.) | `godot --headless --path . --export-release "Web" build/web/index.html` | `build/web/` (sem threads: funciona em qualquer servidor estático) |
| Android | `godot --headless --path . --export-debug "Android" build/android/cadeia-de-comando.apk` | APK de depuração (arm64 + x86_64) |
| Hospedagem compartilhada (Hostinger) | `tools/montar_hostinger.sh` | `build/hostinger/` e `build/cadeia-hostinger.zip`: jogo web + `api.php` do modo online. Guia em [HOSTINGER.md](HOSTINGER.md) |

Requisitos de exportação:
- **Modelos de exportação do Godot 4.5.1** em `~/.local/share/godot/export_templates/4.5.1.stable/`.
- **Android**, nas Configurações do Editor (Exportar > Android):
  - SDK do Android;
  - Java SDK (JDK; o 21 funciona para o APK sem Gradle);
  - debug keystore.

Para testar a versão web localmente: `python3 -m http.server 8060 --directory build/web` e abrir `http://localhost:8060`.

Notas:
- **Fontes embutidas** (`assets/fonts/`: Noto Sans + DejaVu Sans para ♠♥♦♣⚡❄◷). O navegador e o Android não têm as fontes do sistema. A licença está em `assets/fonts/LICENSE.txt`.
- **Android**: paisagem, tela cheia. O botão "voltar" fecha a janela aberta, volta ao menu e, no menu, sai. Testado no emulador com `-gpu host`; com `swiftshader` (software) o shader 2D do Godot não compila.
- **Celular**: layout próprio, escolhido sozinho pelo tamanho físico da tela (ou em **Opções > Layout**). Tela base 720×420, cartas compactas, botões grandes e um menu ☰ com o que é menos usado. Tablet usa o layout de computador.
- **Tela cheia**: o desktop exportado abre em tela cheia. **F11** ou **Alt+Enter** alternam, e há a opção em **Opções** e no ☰ da partida. Na web, o menu tem o botão **Tela cheia**, porque o navegador exige um toque para isso. No celular em pé, a web pede para girar o aparelho.

## Rodar

1. Abra a pasta no Godot 4.3 ou superior (Importar → `project.godot`).
2. Aperte F5. Abre o **menu inicial**: escolha o seu baralho e o do oponente (ou deixe a IA montar o dela) e clique em **Iniciar partida**. **Montar baralhos** abre o montador.

**Montador de baralhos:** clique numa carta do acervo para adicionar uma cópia; botão direito remove. Filtre por tipo, naipe ou texto. As regras são **pelo menos 52 cartas e 25 unidades**; fora isso vale tudo (cópias, valores e naipes repetidos). Baralhos salvos ficam em `user://decks.json` (no Linux, `~/.local/share/godot/app_userdata/Cadeia de Comando/decks.json`) e aparecem no menu com ★.

**Controles no celular (toque):** toque numa carta da mão e depois numa fileira. **Toque longo** numa carta abre a inspeção. **Arraste** a mão ou as listas para rolar. A aba **Carta** do painel mostra o texto da última carta tocada, e a aba **Registro** mostra o registro. O **☰** reúne ordenar, animação, pilhas (cemitérios e baralho), nova partida, desistir e sair. Tudo que encerra a partida ou a rodada pede confirmação, inclusive **Passar**.

**Controles no computador:** clique numa carta da mão e depois numa fileira sua (destacada em verde), ou em **Descartar**. Para atacar ou usar um ativo, clique na sua unidade e depois em **Atacar** ou **Usar efeito**, e escolha o alvo (borda vermelha). Instantâneas (⚡) com alvo pedem o alvo; sem alvo, clique duas vezes na carta para usar. **No Registro, clique no nome de uma carta** para inspecioná-la: carta ampliada, efeitos, onde está e o histórico dela (quem a atingiu, como morreu). Os botões **Meu cemitério / Cemitério inimigo / Meu baralho** mostram essas pilhas (o baralho sai ordenado, sem revelar a ordem de compra). Botão direito ou Esc cancela. No **☰ Menu** ficam a **Animação** (normal, rápida, desligada) e o **Ordenar cartas**, que organiza a mão e o tabuleiro por naipe, valor, HP ou na ordem das jogadas (só muda a exibição). As duas escolhas ficam salvas. **Nova partida**, **Desistir** e **Sair para o menu** também ficam lá, longe dos botões de jogo e com confirmação.

## Modo online

**Jogar online** no menu: um jogador clica em **Criar sala** e passa o código de 5 letras; o outro digita o código e clica em **Entrar**. Funciona entre navegador, desktop e APK, desde que todos usem o mesmo servidor.

**Como funciona (lockstep):**
- As regras rodam inteiras no Godot, nos dois aparelhos ao mesmo tempo. Os dois montam o mesmo `Game`, com a mesma semente e os dois baralhos.
- Pela rede só passam as **jogadas** (`{"a":"play","c":uid,"r":"front","t":-1}`...). Cada aparelho aplica a jogada do outro com `game.apply_action`.
- Junto vai um **hash do estado** (`game.state_hash`). Se os dois divergirem, a partida para com aviso de dessincronia em vez de seguir errada.
- O servidor é uma **caixa de correio** em PHP (`server/api.php`, ~150 linhas). Ele guarda salas e mensagens em ordem (SQLite ou MySQL) e não sabe nada do jogo. Roda em hospedagem compartilhada, sem processo fixo nem WebSocket.
- O cliente consulta o servidor a cada ~1,2 s, e só enquanto espera o oponente.
- **Uma pessoa age por vez:** só quem tem a vez (ou a decisão pendente) manda jogadas, e a troca de mão é feita em sequência. Por isso duas mensagens nunca disputam o mesmo número de sequência.
- **Desistir** só funciona na sua vez.
- **Conexão caída:** a partida fica no servidor. **Continuar partida** refaz o jogo jogada por jogada.
- Ao entrar na sala, os dois conferem a versão do protocolo (`NET_VERSION`), o hash do `cards.json` e a validade do baralho. Versões diferentes do jogo não se misturam.

**A IA e o online:** a IA tem o próprio gerador de números aleatórios e **nunca usa `game.rng`**. Assim a IA não muda os sorteios da partida, e o replay continua idêntico. Contra a IA, nada passa pela rede.

**Servidor local para desenvolver:**
```bash
php -S 127.0.0.1:8070 -t server        # o padrão do campo "Servidor" no desktop
```

**Protocolo** (`POST api.php`, JSON):

| Ação | Envia | Recebe |
|---|---|---|
| `create` | `meta` | `code`, `token`, `seat: 0` |
| `join` | `code`, `meta` | `token`, `seat: 1`, `host_meta` |
| `send` | `code`, `token`, `seq` (= última + 1), `data` | `seq` (reenvio idêntico é aceito; outro conteúdo no mesmo `seq` dá 409) |
| `poll` | `code`, `token`, `since` | `host_meta`, `guest_meta`, `messages: [{seq, seat, data}]` |

`meta` = `{v, cards (hash do cards.json), deck: [ids], name, seed (só o host)}`. `data` = `{act, h}`, onde `h` (hash) vai na última jogada de cada lote.

## Arquitetura

```
core/                 regras puras, sem nenhum Node
  card.gd             estado mutável de uma carta (HP, armadura, veneno, fileira...)
  card_db.gd          carrega data/cards.json (pool_ids, is_token)
  deck_store.gd       baralhos do jogador em user://decks.json + regra de montagem (MIN_UNITS)
  ai_deck_builder.gd  a IA monta o próprio baralho (naipe principal + secundário + instantâneas)
  player_state.gd     mão, baralho, cemitério, fileiras
  game.gd             motor: ações, turnos, rodadas, dano, interpretador de efeitos, eventos
  hand_evaluator.gd   avaliador de mãos de poker (0 a 5 cartas)
  ai.gd               IA heurística (planeja a melhor mão de poker com a mão atual; rng próprio)
net/
  online_client.gd    cliente HTTP da caixa de correio (create/join/send/poll, sessão para retomar, PUBLIC_URL)
server/
  api.php             caixa de correio genérica (salas + mensagens em ordem); config.php escolhe SQLite/MySQL
  htaccess-site.txt   .htaccess do pacote da hospedagem (wasm, compressão, bloqueios)
tools/
  montar_hostinger.sh exporta a web e monta build/hostinger/ + build/cadeia-hostinger.zip
data/cards.json       172 cartas (104 unidades, 66 instantâneas, 2 fichas) + baralhos prontos
ui/
  app.gd / app.tscn   tela raiz (cena principal): menu inicial e troca de telas
  main.gd / main.tscn tela de jogo, montada em código, + fila de animação
  deck_builder.gd     montador de baralhos
  card_view.gd        desenho de uma carta (face completa ou compacta, toque/arrasto/toque longo) + CardView.describe
  ui_profile.gd       perfil de tela (celular x computador), tema de toque, tela cheia e preferências
  modal.gd            janela de confirmação simples
tests/
  sim.gd              avaliador, baralho, temporizador + 150 partidas no padrão + 100 com baralhos da IA
  cards_test.gd       exercita cada uma das 170 cartas do acervo (jogar, ativar, atacar, passar, turnos)
  ablation.gd         mede o peso da habilidade de cada carta
  ui_smoke.gd         joga uma partida inteira pela UI, com animações, e tira screenshots
  menu_smoke.gd       menu + montador (salva/valida baralho) + partida com ele
  net_test.gd         duas partidas online inteiras (IA x IA) por HTTP de verdade
  net_player.gd       jogador online automático usado pelos testes
  net_bot.gd          bot online em processo separado (role=host|guest)
  online_ui_smoke.gd  a tela joga online contra o net_bot (role=host: tela é o jogador 0; guest: jogador 1)
  layout_smoke.gd     abre todas as telas e janelas e confere que cabem na tela (layout=compact|wide)
```

A regra de ouro é que **a UI nunca altera estado**. Ela chama `game.play_card / discard / attack / activate / end_turn / pass_round` e redesenha quando recebe o sinal `changed`. Por isso a IA, os testes headless e o modo online usam exatamente o mesmo motor. A tela é desenhada do ponto de vista de `me` (0 ou 1): o seu lado fica sempre embaixo.

**Animações:** o `Game` emite `event(ev)` para cada coisa que acontece dentro de uma ação (`play`, `cast`, `attack`, `damage`, `buff`, `destroy`, `discard`, `revive`, `summon`, `move`, `bounce`, `mill`, `round_end`...), com uma foto (`snap`) do estado da carta naquele instante. A UI enfileira os eventos e os anima sobre o tabuleiro antigo, e só redesenha com o estado final quando a fila acaba. Uma operação nova deve emitir um evento (`_ev` ou `_buff`) para aparecer na tela.

## Criando cartas (sem programar)

Toda carta é um objeto em `data/cards.json`:

```json
{"id": "canhao", "name": "Canhão a Vapor", "kind": "unit", "suit": "espadas",
 "value": 10, "hp": 4, "atk": 0, "armor": 0, "keywords": [],
 "on_play":  { ... },          // ao entrar
 "active":   { "rows": ["back"], "target": {...}, "effects": [...] },   // 1x por turno
 "passives": [ { "trigger": "...", "rows": [...], "effects": [...] } ],
 "text": "Texto mostrado ao jogador."}
```

Naipes: `espadas`, `copas`, `ouros`, `paus`. Valores: 2 a 14 (11 = J, 12 = Q, 13 = K, 14 = A). O baralho `padrao` precisa ter exatamente uma carta para cada valor e naipe, e o `sim.gd` verifica isso.

Campos extras de unidade: `"shield": N` (Escudo inicial), `"token": true` (ficha: só nasce por `summon`, não entra em baralhos).

**Instantânea** (`"kind": "effect"`): sem valor nem HP; o `suit` é só o tema (cor e filtros). O `on_play` resolve e a carta vai direto para o cemitério:

```json
{"id": "bola_fogo", "name": "Bola de Fogo", "kind": "effect", "suit": "espadas",
 "on_play": {"target": {"side": "enemy"}, "effects": [{"op": "damage", "amount": 4}]},
 "text": "Causa 4 de dano a uma carta inimiga."}
```

**Palavras-chave** (`keywords`): `guardiao`, `investida`, `alcance`, `furtivo` (não pode ser atacado até atacar), `furia` (2 ataques por turno), `roubo_vida` (cura o dano que causa atacando).

**Temporizador** (genérico): qualquer `active` ou passiva com gatilho aceita `"cooldown": N`. O temporizador começa em N quando a carta entra, desce 1 no início de cada turno do dono e, em 0, o efeito pode acontecer; ao acontecer, volta para N. Ex.: `{"trigger": "turn_start", "cooldown": 3, "effects": [...]}` dispara a cada 3 turnos. A carta mostra `⏱N` e a UI anima o disparo.

**Alvo escolhido pelo jogador** (`target` dentro de `on_play` ou `active`), também usado como `filter`:
`{"side": "enemy|ally|any", "rows": ["front","back","command"], "suit": "...", "hp_le": 3, "value_le": 6, "value_ge": 11, "kw": "guardiao", "status": "poison|bleed|dot", "exclude_self": true}`

Se uma unidade tem alvo de entrada e existe alvo possível, o alvo é **obrigatório**.

**Efeito**: `{"op": "...", "amount": N, "target": "chosen|self|context|all|random", "filter": {...}, "per": "...", "max": N, "cost": true}`

`per` multiplica `amount`: `own_graveyard`, `enemy_graveyard`, `last_count`, `self_atk`, `half_damage_taken` (mín. 1), `damage_dealt`, `allied_units`, `enemy_units`, `own_command`, `hand_size`. `"cost": true` marca um efeito que prejudica a própria carta de propósito (a IA trata como custo, não como erro).

| op | faz |
|---|---|
| `damage` (`pierce`) | dano (com `pierce: true` ignora armadura) |
| `heal`, `max_hp`, `armor` | cura (sem teto), aumenta HP, dá armadura |
| `poison`, `bleed`, `cleanse` | aplica veneno, aplica sangramento (cada um: 1 de dano por turno durante N turnos), limpa os dois |
| `value`, `atk` | modifica o valor de poker ou o ataque |
| `set_suit` | muda o naipe (`"suit": "ouros"` ou `"majority_own_command"`) |
| `copy_value` | a carta copia o valor do alvo |
| `destroy` | destrói o alvo |
| `shield` | Escudo N: anula por completo as próximas N instâncias de dano (DoT passa) |
| `freeze` | Congela por N turnos do dono (não ataca nem ativa, nem com Investida) |
| `silence` | Silencia: perde passivas, ativo, auras e palavras-chave |
| `strip` | remove toda a armadura e os escudos |
| `ready` | a unidade pode atacar de novo neste turno |
| `grant_kw` (`kw`) | concede uma palavra-chave |
| `set_value` (`value`) | fixa o valor (`2`..`14` ou `"max_own_command"`) |
| `move` (`row`) | move para `front`, `back`, `command` ou `other_line` (troca Frente/Retaguarda) do próprio dono |
| `bounce` | devolve a unidade para a mão do dono, zerada |
| `draw` | compra cartas |
| `discard_own` | você descarta cartas aleatórias |
| `mill` | o oponente perde cartas do topo do baralho (vão para o cemitério) |
| `summon` (`card`, `row`, `side`) | invoca `amount` fichas (ex.: `"card": "recruta"`) |
| `recall` | põe uma carta de um cemitério na sua mão |
| `revive` (`row`, `hp`) | põe uma unidade de um cemitério na sua fileira `row` (sem `hp` = HP cheio) |
| `exile_grave` | exila cartas do cemitério inimigo (grava `last_count`) |
| `discard_enemy` | o oponente descarta cartas aleatórias |

**Fileira de entrada** (`revive`, `summon`): `"rows": ["front", "back"]` é o padrão, e o dono escolhe entre elas numa janela. Para permitir a Cadeia de Comando, liste `"command"` explicitamente. `"row"` vira só a preferência quando o motor decide sozinho. Carta revivida reaplica o próprio `on_play`.

**Cemitério com escolha** (`recall`/`revive`): `"pick": "random" | "highest" | "choose"`, `"from": "own" | "enemy" | "both"`, `"kind": "unit" | "effect" | "any"` (só `recall`). Com `"pick": "choose", "choices": X` o jogo sorteia X cartas e o jogador escolhe 1 numa janela (a IA escolhe sozinha). Com X = 1, ou só 1 opção, é aleatório e sem janela. Carta tirada do cemitério do oponente passa a ser sua. Ex.: `{"op": "revive", "row": "back", "pick": "choose", "choices": 3, "from": "both"}`.

**Decisões pendentes** (`game.pending`): enquanto um jogador decide (escolha de carta, fileira ou alvo, ou troca de mão), nenhuma outra ação é aceita. `game.waiting_for()` diz quem decide; resolva com `game.resolve_choice(pid, opção)` (opção = carta ou nome da fileira) ou, na troca de mão, `game.mulligan_swap(pid, carta)` quantas vezes quiser e `game.mulligan_done(pid)`. A UI mostra uma janela para o jogador humano; o `AIPlayer.step()` resolve as da IA. Em laços de teste, quem age é `waiting_for()` se ≥ 0, senão `current`.

**Gatilhos de passiva** (`trigger`): `turn_start`, `on_attack` (o alvo vira `context`; `damage_dealt` disponível), `on_attacked` (quem atacou vira `context`; é assim que se faz revide), `on_damaged`, `on_death`, `on_ally_destroyed`, `on_enemy_destroyed`, `on_ally_played` (outra aliada entrou; ela é o `context`), `on_cast` (você usou uma instantânea), `on_pass` (você passou a rodada).

Revide (metade do dano sofrido, mínimo 1): `{"trigger": "on_attacked", "effects": [{"op": "damage", "amount": 1, "per": "half_damage_taken", "target": "context"}]}`.
**Aura** (passiva contínua): `{"aura": "value|atk", "amount": 1, "rows": [onde a fonte precisa estar], "filter": {...}}`.

Para uma operação nova, adicione um `case` em `Game._apply_effect` (ou em `_apply_player_op`, se ela não tiver alvo).

## Testes e balanceamento

```bash
godot --headless --path . --import                 # primeira vez (gera o cache de classes)
godot --headless --path . -s res://tests/sim.gd         # ~1 min
godot --headless --path . -s res://tests/cards_test.gd  # toda carta nova passa por aqui
godot --headless --path . -s res://tests/ablation.gd
php -S 127.0.0.1:8070 -t server &                      # para os testes online
godot --headless --path . -s res://tests/net_test.gd    # 2 partidas online por HTTP (IA x IA)
godot --path . -s res://tests/online_ui_smoke.gd -- role=host   # a tela contra um bot (também role=guest)
```

`sim.gd` também testa o **lockstep**: refaz cada partida aplicando as jogadas via JSON e compara o hash do estado a cada passo.

`sim.gd` imprime a taxa de vitória de cada lado, a vantagem de quem começa, a duração média, a distribuição de mãos no showdown e, com baralhos montados pela IA, quantas cartas diferentes entraram em jogo e a vitória por naipe principal. Rode depois de cada mudança em cartas. `cards_test.gd` não pode imprimir nenhum `SCRIPT ERROR`.

**Exportar:** inclua `*.json` no filtro de recursos do preset de exportação, senão o `cards.json` fica de fora do build.
