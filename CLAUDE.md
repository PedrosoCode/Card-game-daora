# CLAUDE.md: Cadeia de Comando

Card game 1v1 em **Godot 4.3+ (GDScript)**, com UI 100% em `Control` (não há sprites nem cena 2D de jogo). A ideia é misturar três jogos:
- **Gwent:** melhor de 3 rodadas, economia de cartas e passar a vez (fechar a mão).
- **Magic:** unidades, efeitos instantâneos, ativos, passivos e palavras-chave.
- **Poker:** quem tem a melhor mão vence a rodada.

Naipes de baralho comum (♠ ♥ ♦ ♣). Acervo de **104 unidades** (dois conjuntos de 2 a A por naipe) e **66 instantâneas**. Baralhos montados pelo jogador (mín. 25 unidades) ou pela IA. Os nomes das cartas misturam fantasia medieval, cyberpunk, steampunk e arcano.

Status: **protótipo v0.9 jogável** (desktop, web e Android) contra a IA e **online 1x1** (lockstep + caixa de correio PHP em hospedagem compartilhada), com **layout próprio para celular** (toque) e para computador: menu inicial, montador de baralhos, animações e testes passando.

---

## Comandos

```bash
godot --headless --path . --import                   # 1ª vez / após criar class_name novo (gera cache de classes)
godot --headless --path . -s res://tests/sim.gd      # avaliador, baralho, temporizador + 150 partidas padrão + 100 com baralhos da IA (~1 min)
godot --headless --path . -s res://tests/cards_test.gd  # exercita cada carta do acervo; não pode sair nenhum SCRIPT ERROR
godot --headless --path . -s res://tests/ablation.gd # peso da habilidade de cada carta (tira a habilidade de uma carta por vez)
godot --path . --disable-vsync --resolution 1600x900 -s res://tests/ui_smoke.gd   # joga pela UI COM animações (3x) + screenshots em user://
# Args depois de "--": speed=0|1|3, sort=0..3, decks=legiao,conspiracao (padrão do teste), layout=compact|wide
godot --path . --disable-vsync --resolution 1600x900 -s res://tests/menu_smoke.gd  # menu + montador + partida com baralho salvo (usa user://test_decks.json)
godot --path . --disable-vsync --resolution 1200x540 -s res://tests/layout_smoke.gd -- layout=compact  # todas as telas/janelas cabem na tela (e layout=wide em 1600x900)
php -S 127.0.0.1:8070 -t server                      # servidor online local (rodar em segundo plano antes dos testes abaixo)
godot --headless --path . -s res://tests/net_test.gd # 2 partidas online IA x IA por HTTP; precisa terminar com ONLINE: OK
godot --path . --disable-vsync -s res://tests/online_ui_smoke.gd -- role=host   # a TELA joga online contra tests/net_bot.gd (role=guest testa me = 1); ~2 min
```
- **Testes com janela: sempre `--disable-vsync`.** Com a janela do teste encoberta, o compositor do GNOME/Wayland segura o vsync em ~1 fps e o teste "trava" (anda 1 quadro por segundo). Não há Xvfb nesta máquina; `--headless` serve para tudo menos screenshots.
- `layout=compact` força o layout de celular (use `--resolution 1200x540`, proporção de celular); `layout=wide` força o de computador.

**Sempre rode `tests/sim.gd` depois de mexer em regras ou cartas.** Ele precisa terminar com `RESULTADO: OK` (sem travas, todas as partidas acabam) e mostra a vantagem de quem começa e as mãos no showdown.
**Carta nova ou operação nova: rode `cards_test.gd`.**
**Mexeu em `Game` (estado, sorteio, ação nova)? `sim.gd` tem o teste de lockstep; mexeu na rede ou em `main.gd`? rode `net_test.gd` e `online_ui_smoke.gd` (host e guest).**
**Mexeu em layout/telas? rode `layout_smoke.gd` nos dois modos (compact 1200x540 e wide 1600x900): ele falha se alguma janela sair da tela.**
**Depois de mexer na UI ou em eventos, rode `ui_smoke.gd` e `menu_smoke.gd`** e olhe as screenshots (`ui_*_attack/cast/summon/bounce/...png`, `menu_*.png`) em `~/.local/share/godot/app_userdata/Cadeia de Comando/`. As `ui_*` são tiradas no meio das animações.

O binário do Godot nesta máquina é `~/Documentos/Godot_v4.5.1-stable_linux.x86_64` (não está no PATH).

Exportar (presets em `export_presets.cfg`; modelos 4.5.1 instalados em `~/.local/share/godot/export_templates/4.5.1.stable/`):
```bash
godot --headless --path . --export-release "Web" build/web/index.html                     # web sem threads
godot --headless --path . --export-debug "Android" build/android/cadeia-de-comando.apk    # APK de depuração
python3 -m http.server 8060 --directory build/web                                          # testar a web (também em .claude/launch.json)
tools/montar_hostinger.sh                                                                  # web + api.php -> build/hostinger/ e build/cadeia-hostinger.zip (guia: HOSTINGER.md)
~/Android/Sdk/emulator/emulator -avd Medium_Phone_API_36.0 -no-window -gpu host            # testar o APK (adb install / screencap)
```
- Android precisa de `export/android/java_sdk_path` nas Configurações do Editor (`~/.config/godot/editor_settings-4.5.tres`): JDK do sdkman, `~/.sdkman/candidates/java/21.0.5-tem`. **Às vezes um processo do Godot regrava esse arquivo com o caminho vazio** ("A valid Java SDK path is required"): confira com `grep java_sdk_path` e recoloque.
- O export de **release** falha sem keystore de release: use `--export-debug`.
- O emulador precisa de `-gpu host`: com `swiftshader` o CanvasShaderGLES3 estoura `GL_MAX_FRAGMENT_UNIFORM_VECTORS` e a tela fica cinza.
- `include_filter="*.json"` nos presets (senão o `cards.json` fica fora). `tests/*` é excluído.

---

## Arquitetura

```
core/                 REGRAS PURAS, sem Node
  card.gd             Card: estado mutável (HP, armadura, veneno, sangramento, fileira, exaustão). `def` = dados do JSON
  card_db.gd          CardDB: carrega data/cards.json (static vars); pool_ids(), is_token()
  deck_store.gd       DeckStore: baralhos do jogador em user://decks.json (registrados como "user:<nome>"); validate() = regra MIN_UNITS 25
  ai_deck_builder.gd  AIDeckBuilder.build(rng): a IA monta o próprio baralho (naipe principal inteiro + 12 do secundário + 12 instantâneas)
  player_state.gd     PlayerState: deck, hand, graveyard, rows{front,back,command}, gems, passed, played_card
  game.gd             Game: motor de regras + interpretador de efeitos + sinais + eventos de animação
  hand_evaluator.gd   HandEvaluator: avalia 0–5 cartas → chave comparável [rank, desempates...]
  ai.gd               AIPlayer: IA heurística, uma ação por step()
data/cards.json       172 cartas (104 unidades, 66 instantâneas, 2 fichas) + baralhos prontos padrao/legiao/conspiracao
ui/app.gd + .tscn     CENA PRINCIPAL: menu inicial; troca de telas (_swap chama shutdown() da partida antes de liberar)
ui/main.gd + .tscn    tela de partida montada em código; traduz cliques em ações; fila de animação.
                      Recebe deck_ids/ai_auto da App; sinal menu_requested. Roda sozinha (testes) com padrao x padrao.
ui/deck_builder.gd    DeckBuilder: acervo filtrável + lista do baralho + salvar/abrir/excluir
ui/card_view.gd       CardView: desenho de uma carta (só lê estado; apply_snapshot mostra estado intermediário);
                      CardView.describe(card, game) = texto completo usado na partida e no montador.
                      Face completa (FULL_SIZE 92×112) ou compacta (celular). Toque: clique ao SOLTAR, arrastar rola
                      o ScrollContainer de cima, toque longo (0,5 s) = right_clicked
ui/ui_profile.gd      UiProfile (estático): perfil compacto (celular) x amplo; tela base 720×420 x 1600×1000; tema de toque;
                      tela cheia (F11, Opções, ☰); preferências em user://settings.cfg (layout, fullscreen, anim_speed, sort)
ui/modal.gd           Modal.confirm(parent, pergunta, botão, ação): confirmação fora da partida (montador)
net/online_client.gd  OnlineClient (Node, filho persistente da App): HTTP da caixa de correio, sessão em user://online_session.json,
                      URL em user://online.cfg; default_url() (web: api.php ao lado do index.html; senão PUBLIC_URL ou 127.0.0.1:8070)
server/api.php        caixa de correio GENÉRICA (não conhece o jogo): create/join/send/poll; config.php (SQLite padrão / MySQL)
tools/montar_hostinger.sh  pacote para hospedagem compartilhada
tests/                sim.gd, cards_test.gd, ablation.gd, ui_smoke.gd, menu_smoke.gd, net_test.gd, net_player.gd, net_bot.gd,
                      online_ui_smoke.gd (SceneTree scripts)
REGRAS.md             regras para jogador; README.md = guia + esquema do JSON + protocolo online; HOSTINGER.md = publicar
```

### Princípios (não quebrar)

1. **A UI nunca altera o estado do jogo.** Ela chama só as ações públicas do `Game` e redesenha tudo no sinal `changed` (adiado enquanto há animação).
   - Ações: `play_card(pid, card, row, target)`, `discard(pid, card)`, `attack(pid, atk, tgt)`, `activate(pid, card, tgt)`, `end_turn(pid)`, `pass_round(pid)`.
   - Cada ação retorna `bool`. Em caso de falha, o motivo fica em `game.last_error`.
2. **Consultas e validação ficam no `Game`.**
   - Validação: `can_play`, `can_discard`, `can_attack`, `can_activate`, `can_end_turn`, `is_done`, `can_hit_command`.
   - Fileiras e alvos: `playable_rows`, `valid_targets(spec, owner, source)`, `attack_targets`.
   - Valores calculados: `effective_value`, `effective_atk` (incluem auras), `hand_key` / `hand_name`.
   - A UI e a IA usam essas mesmas funções, então a regra existe em um lugar só.
3. **Cartas são dados.** Uma carta nova normalmente é só JSON. Uma operação nova entra como `case` em `Game._apply_effect` (com alvo) ou `_apply_player_op` (sem alvo). Depois, documente no README.
4. **Determinismo (o online depende disso).** Todo sorteio do jogo usa `game.rng` (seedável via `setup(..., seed)`). Não use `randi()` global nem `Array.shuffle()` no core.
   - **A IA tem `rng` próprio e NUNCA usa `game.rng`.** Se usar, o replay online diverge.
   - Toda ação pública validada chama `_record(pid, act)` → `game.action_log`. Ação nova = registrar + `case` em `apply_action` + campo novo em `state_hash` se for estado novo. Rode o `_test_lockstep` do `sim.gd`.
   - Cartas na rede vão por `uid` (`cards_by_uid`); números do JSON chegam como float (`int(...)`).
5. **Decisões pendentes** (`game.pending`, sessão 7): escolha no cemitério (`kind: choice`) e troca de mão (`kind: mulligan`).
   - Enquanto existe uma, `is_turn` é falso para todos.
   - `waiting_for()` diz quem decide. Resolva com `resolve_choice(pid, opção)` ou `mulligan_swap(pid, card)` + `mulligan_done(pid)` (`mulligan(pid, cards)` é atalho).
   - Escolha genérica: `_ask(pid, prompt, options, option_kind ("card"|"row"|"target"), apply: Callable, preview)`. Só dá para perguntar com `_can_ask()` (`_depth == 1`: bloco de topo da ação, ou dentro de um `apply`, onde `resolve_choice` põe `_depth = 1`). Um `apply` pode pedir outra decisão (carta → fileira → alvo); `resolve_choice` copia a continuação (`block`, `block_source`, `index`, `chosen`, `ctx`, `finish`).
   - A UI mostra a janela pelo estado (`_sync_decision` no fim de `_redraw`).
   - A IA resolve no início de `step()`.
   - **Todo laço que dirige a IA usa `ais[waiting_for() if >= 0 else current]`.**
6. **A IA joga uma ação por `step()`.** Isso deixa a UI animar entre as ações. A IA guarda `_tried` por turno para não entrar em loop numa ação que falha.
7. **Uma pessoa age por vez** (regra do online): só `waiting_for()` (se >= 0) ou `current` mandam ações; a troca de mão é sequencial (`waiting_for()` = menor pid pendente); `resign` só na própria vez (`_my_action_time()` na UI). Não crie ação que os dois possam disparar ao mesmo tempo.
8. **A UI é parametrizada por `me`** (0 ou 1). Use `game.players[me]`, `_opp()`, `_side(pid)` (0 = embaixo, 1 = em cima; as chaves de layout `"%d_%s"` são LADOS da tela, não pids). Nada de 0/1 fixo em `main.gd`.
9. **Dois layouts, um código** (`UiProfile.compact`, sessão 11):
   - **Compacto (celular):** escolhido quando a menor dimensão da tela < 600 dp (Android: dpi/160; web: devicePixelRatio), ou forçado em Opções / `layout=compact`. A tela base vira 720×420 (1 px virtual ≈ 1 dp num celular), então tudo fica fisicamente grande.
   - `main.gd` tem `_build_wide` e `_build_compact`. O compacto tem as 6 fileiras + painel lado a lado e a mão numa faixa embaixo (rola arrastando, passo mínimo 44 px). Informações/comparação no painel e Carta/Registro em abas. Pilhas, ordenar, animação, tela cheia, nova partida, desistir e sair ficam no ☰.
   - `CardView.SIZE`/`HAND_SIZE` são **static var** do perfil (no compacto a largura acompanha a tela: `_apply_compact_metrics`, `_on_viewport_resized`). Inspeção usa sempre `FULL_SIZE`.
   - Tamanhos de fonte em código compartilhado passam por `UiProfile.fs(n)`; janelas usam `_place_modal` (centro do tabuleiro no desktop, da tela no celular, sempre dentro da tela) e larguras derivadas de `get_viewport_rect()` (nada de 1040 fixo).
   - **Ações que encerram a partida ou a rodada pedem confirmação** (`_confirm`): Passar a rodada, Nova partida, Desistir, Sair para o menu. Elas não ficam perto dos botões de jogo. O "voltar" do Android abre o ☰.
   - Cartas usam `MOUSE_FILTER_PASS` (a roda do mouse chega ao ScrollContainer); por isso aceitam o evento (`accept_event`) nos cliques, senão a fileira de baixo também recebe.
10. **Tudo que muda na tela emite um evento.** Uma operação nova no `Game` precisa chamar `_ev(...)` ou `_buff(...)`, senão a UI não anima e a mudança só aparece no redesenho final.

### Sinais do Game

`changed`, `logged(text)` (BBCode para o registro), `event(ev)`, `round_finished(info)`, `match_finished(info)`.
Eventos extras desta versão: `cast`/`cast_end` (instantânea vai ao centro e depois ao cemitério; os projéteis dos efeitos saem dela), `summon`, `move`, `bounce`, `mill`, `damage` com `blocked: true` (Escudo).
`info` = `{round, names[2], cards[2], winner (-1 empate), gems[2], match_over, match_winner}`; também fica em `game.history`.

### Eventos e animação

`event(ev)` sai na ordem exata dos acontecimentos dentro de uma ação. Eventos de carta trazem `uid`, `card` e `snap` (`Game.snapshot(c)`: hp, max_hp, armor, poison, bleed, value, suit, atk naquele instante).

| type | campos extras | animação (ui/main.gd) |
|---|---|---|
| `turn` | pid | faixa "Seu turno" / "Turno do oponente" |
| `play` / `revive` | pid, row | carta voa da mão (ou do topo, se do oponente) / surge na vaga |
| `attack` | src, dst | seta vermelha + cópia do atacante avança; o dano aparece no impacto |
| `activate` | – | brilho dourado + "ATIVA" |
| `damage` | amount, absorbed, kind (attack/effect/poison/bleed), src | projétil (se efeito), número colorido, "-N ARM", tremida |
| `buff` | label, tone, src | projétil + texto colorido (cura, armadura, veneno, valor...) |
| `destroy` | by, row | "DESTRUÍDA", vermelho, voa girando para o cemitério |
| `discard` | pid | carta vai cinza para o cemitério |
| `draw` / `recall` / `exile` | pid, n | texto perto da linha de info do jogador |
| `pass` | pid | faixa + borda dourada na Cadeia |
| `timer` | – | brilho azul + "⏱ Temporizador!" na carta |
| `round_end` | info | bordas verde/vermelha nas Cadeias, faixa do showdown; rodada normal: diálogo + tabuleiro some; última: **painel fixo de fim** (`end_panel`, VITÓRIA/DERROTA/EMPATE, resumo das rodadas, "Jogar de novo") |

Mecânica em `ui/main.gd`:
- `_on_game_event` enfileira e `_play_queue` anima um por vez (`await`) sobre os `views` (uid → CardView) do desenho anterior.
- `_redraw` só roda quando a fila esvazia (`_refresh` é ignorado enquanto `anim_busy`).
- Movimentos usam clones em `cards_layer`, porque os containers reposicionam os filhos. Textos e setas ficam em `fx_layer`.
- Eventos seguidos da mesma fonte (dano/buff em área) são animados juntos (`_anim_group`).
- A IA (`_run_ai`) espera `anim_finished` entre ações. Os cliques do jogador são ignorados durante a animação.
- `anim_speed` (botão Animação: 1x / 2x / desligada). Desligada, só o diálogo de fim de rodada aparece.
- **Animações paralelas** (grupo em área, dano no impacto do ataque) passam por `_anim_parallel`, que conta em `anim_parallel`. `_play_queue` só redesenha com o contador em 0, porque o redesenho libera as CardViews antigas. Toda animação checa `is_instance_valid` depois de cada `await`. (Bug real visto pelo usuário: "apply_snapshot on previously freed".)
- `sort_mode` (Ordenar cartas: padrão, naipe, valor, HP) só reordena a exibição em `_redraw` via `_sorted()`. Os arrays do `Game` não mudam.
- As fileiras são centralizadas (`ALIGNMENT_CENTER`). `_slot_pos` mira logo depois da última carta, e o redesenho recentraliza.

---

## Regras do jogo (resumo canônico — detalhes em REGRAS.md)

### Cartas
- **Unidade**: naipe + valor (2–14; 11=J…14=A) + HP + ATQ (+ `armor`, `shield` iniciais opcionais). Pode ter `on_play`, `active`, `passives`, `keywords`.
- **Instantânea** (`kind: effect`): `suit` é só tema; `on_play` resolve e vai pro cemitério (`play_card` emite `cast`, resolve, `cast_end`, depois dispara `on_cast` nas aliadas). Conta como a carta do turno.
- **Fichas** (`token: true`): Recruta 2♥ e Esqueleto 2♣, só por `summon`. Fora do acervo (`CardDB.pool_ids`).
- **Baralhos**: `padrao` (as 52 unidades originais; `sim.gd` checa 52 combinações únicas), `legiao` (♠♥), `conspiracao` (♦♣), os do jogador (`user:<nome>`) e o `ia_auto` (gerado a cada partida se a IA monta o dela). Regras: **≥ 52 cartas e ≥ 25 unidades** (`DeckStore.MIN_CARDS`, `MIN_UNITS`).
- **Naipes** e a identidade mecânica de cada um:
  - `espadas` ♠: ataque (dano, sangramento, Investida, Alcance, Fúria, Furtividade, puxar da Retaguarda).
  - `copas` ♥: proteção (cura, armadura, Guardião, Escudo, Recrutas, `on_pass`).
  - `ouros` ♦: manipulação (valor/naipe das Cadeias, compra, descarte, congelar, silenciar, `bounce`, `mill`, `on_cast`).
  - `paus` ♣: morte (veneno, cemitério, destruição, Roubo de Vida, Esqueletos, `on_death`).
- **Palavras-chave** (`Game.KEYWORD_NAMES/KEYWORD_HELP`): `guardiao`, `investida`, `alcance`, `furtivo` (fora de `attack_targets` até atacar; atacar remove), `furia` (`max_attacks` = 2; `Card.attacks_made`), `roubo_vida` (cura o dano causado atacando).
- **Estados** (`Card`): `shield` (anula instância de dano, exceto DoT), `frozen`/`stunned` (perde o turno do dono; bloqueia ataque e ativo mesmo com Investida), `silenced` (`has_kw` falso, `_trigger` e auras ignoram, sem ativo).
- **Temporizador** (genérico, `"cooldown": N` em qualquer `active` ou passiva com `trigger`):
  - Estado em `Card.timers` (chave `"active"` ou `"p<índice>"`), criado em `Card.reset()` com N.
  - `Game._tick_timers` desce 1 no início de cada turno do dono.
  - `_trigger` só dispara com 0 e recomeça em N (emite evento `timer`). `can_activate` exige 0, e `activate` recomeça.
  - Usam: Paladino (3), Rei Guerreiro, Sacerdotisa, Joalheiro, Alquimista do Veneno (ativo 2), Rainha Protetora, Magnata (passiva 2). Teste em `sim.gd` (`_test_timer`).
- **Escolha no cemitério** (`recall`/`revive` com `pick: choose`, `choices: X`, `from: own|enemy|both`, `kind`):
  - O jogo sorteia X opções. Com 1 opção, escolhe sem perguntar.
  - Se a escolha está no bloco de topo de uma ação (`_depth == 1`), a resolução **suspende**:
    - `_suspending` → `_resolve_block` guarda `block/index/chosen/ctx` em `pending`;
    - `play_card`/`activate` guardam o resto da ação em `pending.finish` (`_defer`);
    - `resolve_choice` continua do efeito seguinte.
  - Dentro de gatilhos encadeados não há janela: pega a de maior valor.
  - A carta tirada do cemitério do oponente troca de dono (`_grave_take`).
- **Troca de mão** (sessão 8): em TODA rodada, inclusive a 1ª (`setup` → `_open_mulligan`). `MULLIGAN_MAX = 10` trocas por jogador, **uma por vez** (`mulligan_swap` devolve a carta ao baralho em posição aleatória fora do topo e compra a de cima; dá para trocar a nova). `mulligan_done` encerra; com todos encerrados, `_begin_round`.
- **Entrada por efeito** (`_enter_board`): reviver e invocar perguntam a fileira (`_entry_rows`: `eff.rows`, padrão Frente/Retaguarda, Cadeia só se listada). Na Cadeia aplica a armadura de comando. Dispara `on_ally_played`. Revivida → `_replay_on_play` (pede alvo se houver mais de um).
- **Registro com links**: `Game._cn(card)` = `[url=uid]Nome[/url]` em todo `_log`. `cards_by_uid` + `locate(card)` servem a janela de inspeção da UI (`_inspect`, com o histórico da carta montado a partir de `log_lines`).
- **Alvo de entrada obrigatório**: unidade com `on_play.target` e alvo possível não pode ser jogada sem alvo (`play_card` falha). A IA escolhe o menos ruim ou não joga.

### Tabuleiro (por jogador, 5 vagas cada)
1. **Frente de Batalha**: ataca/defende, não conta no poker. É a única que alcança a Cadeia inimiga.
2. **Retaguarda**: ataca/defende, não conta no poker. Enquanto tiver cartas, protege a própria Cadeia de ataques.
3. **Cadeia de Comando**: **forma a mão de poker** (até 5). Não ataca. Qualquer unidade pode entrar. Ao entrar ganha **armadura = ceil(HP × 1,5)** (`COMMAND_ARMOR_MULT`, `Game.command_armor`). Só vale no `play_card` (não no `revive`, que entra na Frente).

### Partida
- **Melhor de 3**; cada jogador tem **2 vidas** (`START_GEMS`).
- Mão inicial **17** (`START_HAND`); compra **10** no início da 2ª e da 3ª rodada (`DRAW_AFTER_ROUND`). **Sem compra por turno.** Usa 37 das 52 cartas no máximo.
- 1º jogador sorteado (`game.starter`); nas rodadas seguintes começa **quem perdeu** (empate alterna).

### Turno
- Exatamente **1 carta jogada ou descartada** por turno. `discard` conta como a carta do turno e **compra 1 na hora** (troca), mas impede baixar outra; ataques e ativos seguem. Só dá para `end_turn` depois disso, **exceto com a mão vazia** (aí o turno é só para atacar/ativar).
- Cada unidade pronta pode **atacar 1×** (só Frente/Retaguarda) e usar **ativo 1×** (respeitando `active.rows`).
- **Exaustão**: carta que acabou de entrar não ataca nem usa ativo até o próximo turno do dono (exceto Investida no ataque).

### Combate e status
- Ataque causa ATQ ao alvo. **Sem revide automático**: só a passiva `on_attacked` reage. Revide = `damage` com `per: half_damage_taken`, `target: context`: metade do dano sofrido (HP + armadura consumida, vindo de `damage()` como retorno e `ctx.damage_taken`), mínimo 1. Hoje têm Revide: Cavaleiro da Coroa, Golem de Caldeira e Ciborgue Mercenário.
- **Alcance da Cadeia** (`BACK_PROTECTS_COMMAND`, `can_hit_command`): só atacantes na **Frente** miram a Cadeia inimiga, e só com a **Retaguarda inimiga vazia**. Efeitos miram sempre.
- **Guardião** na Frente inimiga obriga a atacar um Guardião.
- **Alcance** (palavra-chave) ignora as duas restrições.
- **HP sem teto**: `heal`/`max_hp` somam ao HP (e sobem `max_hp` junto). A UI pinta o HP de verde acima do impresso e de vermelho abaixo.
- **Armadura** é um segundo HP, consumido antes do HP.
- **Veneno N** e **Sangramento N** funcionam igual: no início do turno do dono causam **1** de dano e o acúmulo cai 1 (N acúmulos = N turnos de 1). **Ignoram armadura** (`DOTS_PIERCE_ARMOR`).
- Se o dono passou, os DoTs dele correm no início dos turnos do oponente.
- HP ≤ 0 → destruída → cemitério (dispara `on_death`, `on_ally_destroyed`, `on_enemy_destroyed`).
- Efeitos com quantidade 0 (ex.: armadura por cemitério vazio) não fazem nada nem geram log.

### Passar e showdown
- Quem passa não age mais na rodada; o outro segue jogando turnos.
- **Passar NÃO sela mais** (`PASS_SEALS_COMMAND = false`, pedido do usuário na sessão 6): quem passou segue atacável e alvo de efeitos. A intenção é o oponente gastar cartas para virar (quebra de economia), em vez de xeque-mate. Gatilho `on_pass` recompensa passar.
- `is_done(pid)` = passou **ou** está com a mão vazia. Quem está sem cartas mas não passou continua recebendo turnos (só ataca/ativa).
- Os dois `is_done` → **showdown** (`_end_round`, checado em `_next_turn`): compara as Cadeias usando **valor efetivo**. O perdedor perde 1 vida; em empate, ambos perdem. O evento `round_end` sai antes de limpar o tabuleiro.
- Todo o tabuleiro vai pro cemitério, **exceto no fim da partida**: aí o tabuleiro final fica na mesa (a UI mostra o painel de fim por cima). Com 0 vidas acaba a partida (ambos em 0 = empate).
- `_why_idle` (UI) explica por que uma unidade não age (congelada, exausta, já atacou, sem alvo...).

### Mãos (fraca → forte)
Carta Alta, Par, Dois Pares, Trinca, Sequência, Flush, Full House, Quadra, Straight Flush.
- Sequência e Flush exigem 5 cartas.
- A-2-3-4-5 é sequência com o 5 como carta alta.
- Desempate pela chave `[rank, grupos por (qtd desc, valor desc)]`; com tudo igual, **mais cartas vence**.
- Cadeia vazia = `[-1]` (perde de tudo).

### Cemitério
Recebe destruídas, descartadas e o tabuleiro ao fim da rodada. Interações existentes:
- **Recuperar para a mão:** `recall` (Sucateiro, Coveiro, Exumar).
- **Reviver no tabuleiro:** `revive` (Necromante, Senhor dos Mortos, Ressurreição).
- **Moer o baralho inimigo para o cemitério:** `mill` (Banqueiro Sombrio, Auditoria).
- **Escalar com o tamanho do cemitério:** `per: own_graveyard` (Rei Caído, Espectro).
- **Exilar o cemitério inimigo:** `exile_grave` (Lich, Profanador).
- **Descarte forçado:** `discard_enemy` (Ladra).

Carta que sai do cemitério volta zerada (`Card.reset()`).

---

## Formato de carta (data/cards.json)

O esquema completo (ops, gatilhos, filtros, `per`) está no **README.md**, seção "Criando cartas". Resumo:

```json
{"id": "x", "name": "Nome", "kind": "unit|effect", "suit": "espadas|copas|ouros|paus", "value": 2-14, "hp": N, "atk": N,
 "armor": N?, "shield": N?, "token": true?, "keywords": [...]?,
 "on_play":  {"target": SPEC?, "effects": [EFEITO...]},
 "active":   {"rows": [...]?, "cooldown": N?, "target": SPEC?, "effects": [...]},
 "passives": [{"trigger": "...", "rows": [...]?, "cooldown": N?, "effects": [...]},
              {"aura": "value|atk", "amount": N, "rows": [...], "filter": SPEC}],
 "text": "texto pro jogador"}
```

- `cards.json` é editado à mão: uma carta por linha. O editor do Godot às vezes o reformata com tabs.
- Um efeito com `"cost": true` prejudica a própria carta de propósito. A IA o trata como custo.
- Toda op/trigger nova precisa de um caso em `AIPlayer._target_value` ou `_untargeted_value`; senão a IA ignora (valor 0).

---

## Conteúdo atual

- **Unidades originais (baralho padrão)**: ♠ Drone, Mercenária, Arqueira, Piromante, Bombardeiro, Ciborgue, Capitã, Carrasco, Canhão, Cavaleiro Negro, Rainha da Guerra, Senhor da Guerra, Campeão · ♥ Escudeiro, Noviça, Autômato, Ferreiro, Curandeira, Engenheira, Sentinela, Clérigo, Cavaleiro da Coroa, Arauto, Rainha de Ferro, Golem, Paladino · ♦ Vidente, Ladra, Relojoeiro, Sucateiro, Sintética, Ourives, Hacker, Netrunner, Alquimista, Espiã, Duquesa, Mercador-Rei, IA Central · ♣ Bruxa, Envenenadora, Traficante, Coveiro, Carniçal, Espectro, Assassino, Profanador, Necromante, Cultista, Banshee, Rei Caído, Lich.
- **Unidades novas (sessão 6)**: ♠ Batedora Sombria, Gladiador, Arpoador, Duelista Gêmea, Lanceiro, Mercenário de Aluguel, Assassina Cromada, Capitão de Cerco, Ceifador a Vapor, Cavaleira Rubra, General de Ferro, Rei Guerreiro, Lâmina do Destino · ♥ Pajem Leal, Monge Guardião, Enfermeira, Escudeira Real, Sacerdotisa, Capitã da Milícia, Muralha Viva, Bispo, Templário, Arcanjo, Rainha Protetora, Rei Benevolente, Fortaleza Celeste · ♦ Aprendiz de Alquimia, Falsária, Técnico de EMP, Corretor, Hacker Silencioso, Leiloeiro, Ilusionista, Banqueiro Sombrio, Prefeito Corrupto, Joalheiro, Rainha dos Espelhos, Magnata, Oráculo de Cristal · ♣ Rato da Peste, Vampira Neófita, Coletor de Almas, Escavador, Alquimista do Veneno, Ghoul, Necrófago, Bruxa do Sangue, Senhor dos Mortos, Praga Ambulante, Viúva Vampira, Imperador Esquelético, Arauto do Fim.
- **Instantâneas**: as 13 antigas voltaram (Bola de Fogo, Lâmina Serrilhada, Tempestade, Placas de Aço, Purificar, Convocação, Sobrecarga, Reprogramar, Sabotagem, Frasco de Veneno, Exumar, Profanar, Execução) + 52 novas, 13 por naipe.

## Histórico do que foi feito (sessão 2026-10-10)

1. Desenho inicial do usuário: 3 fileiras, poker só na Cadeia de Comando, sem mana/fichas, 12 cartas + compras 3/2, efeitos instantâneos, DoTs, armadura, ativos/passivos, cemitério.
2. Implementado motor puro + UI em código + IA + testes headless.
3. **Lacunas preenchidas por decisão própria** (confirmar com o usuário):
   - 1 carta por turno, exaustão e contra-ataque.
   - 2 vidas, empate tira vida dos dois, perdedor começa a próxima rodada.
   - Proteção da Frente e Selada.
4. Achados das simulações (400 partidas IA × IA):
   - **Sem a regra Selada, passar primeiro era suicídio**: o oponente destruía a Cadeia de quem passou. A regra foi criada por isso.
   - **Agrupar valores no baralho (muitas cartas repetidas) pesa mais que qualquer habilidade.** Só concentrar os valores da Ordem subiu ela de 19% para 30%. É o eixo central do design de baralhos.
   - A IA inicialmente montava mal a Cadeia (quase tudo dava carta alta). A correção foi `_plan_command()`, que testa todas as combinações da mão e planeja a melhor mão de 5.
   - Ajustes feitos:
     - Bruxa: veneno 2→1.
     - Netrunner: de ativo (todo turno) para `on_play`.
     - Valores da Ordem reagrupados: Relojoeiro 4, Clérigo 9, Rei Caído K, Dirigível 10.
     - Convocação Real criada para dar compra de cartas à Ordem.
     - Rede com menos Circuito.
5. **Estado do balanceamento: Rede vence ~70% contra a Ordem** (IA × IA). Quem começa vence ~48% (ok). Mãos no showdown já variam bem (pares, flushes, full houses, quadras).

## Sessão 2026-10-10 (2): baralho comum e rodada única

Pedido do usuário: naipes comuns, baralho de 52 cartas como um baralho normal e uma rodada única até as cartas acabarem.

Feito:
- Naipes `espadas/copas/ouros/paus`, cada um com uma identidade mecânica.
- 52 unidades, uma por valor × naipe. Os 2 baralhos antigos (Ordem/Rede) foram substituídos pelo `padrao`, espelhado.
- Rodada única: sem vidas nem rodadas. Mão 7, compra 1 por turno, ação `discard`, showdown quando os dois `is_done`.
- A UI ganhou o botão Descartar, perdeu a escolha de baralho e mostra `A♠` nas cartas.

Primeira simulação (200 partidas IA × IA):
- ~106 turnos por partida (~53 por jogador), ~2,5 min para 200 partidas.
- **Quem começa vence ~63%.**
- **Carta Alta em ~50% dos showdowns.** Com ~50 turnos de combate, as Cadeias são desgastadas e repostas com o que sobra.
- (O "0 descartes" medido aqui era um bug do teste: lambdas capturam `int` por valor. Corrigido na sessão 3.)
- **Ativos repetíveis escalam sem limite** numa rodada longa. Ex.: a Engenheira dá +2 de armadura por turno, e numa partida a Cadeia chegou a 83 de armadura.

## Sessão 2026-10-10 (3): regras de combate, melhor de 3 e animações

Pedido do usuário:
1. A Frente ataca a Cadeia inimiga só se a Retaguarda inimiga estiver vazia.
2. Sem revide automático; revide só como passiva.
3. Volta a melhor de 3: 17 cartas iniciais, +10 por rodada.
4. HP sem teto.
5. Armadura como segundo HP, ignorada por veneno e sangramento.
6. **Principal:** animações para entender as ações sem ler o registro.

Feito:
- Motor: `BACK_PROTECTS_COMMAND` + `can_hit_command`. Gatilho `on_attacked` + `per: self_atk`. `START_HAND` 17, `DRAW_AFTER_ROUND` {1: 10, 2: 10}, sem compra por turno. `heal` sem teto. `DOTS_PIERCE_ARMOR`.
- Cartas com Revide: Cavaleiro da Coroa, Golem de Caldeira, Ciborgue Mercenário.
- Sinal `event` + fila de animação na UI (ver "Eventos e animação").
- A mão vira leque quando não cabe (17 cartas).
- Botão de velocidade das animações.
- IA: heurística de passar da melhor de 3 restaurada; revide previsto só por passiva; cura sem teto.

Simulação (200 partidas IA × IA, mesmo baralho dos dois lados):
- 2,14 rodadas, 58 turnos, 331 eventos por partida.
- Quem começa vence 43,5%.
- **~12 descartes por partida**: a IA descarta quando as 15 vagas enchem. Sem revide, pouca coisa morre e o tabuleiro entope.
- **Mãos muito fortes**: Full House é a mão mais comum, e Straight Flush aparece em ~12% dos showdowns. Com 17 cartas na mão, montar a Cadeia fica fácil.
- Carta Alta quase sumiu (19 de 428).

## Sessão 2026-10-10 (4): bug de animação, DoT, descarte, Revide, ordenar, armadura de comando

Pedidos do usuário:
- **Bug** (visto no debugger): "apply_snapshot on previously freed" em `_anim_buff`. Era uma corrida: a fila redesenhava (e liberava as CardViews) enquanto animações paralelas de um grupo ainda esperavam o projétil. Corrigido com `_anim_parallel` + `anim_parallel` + checagens `is_instance_valid`.
- Veneno e sangramento: 1 de dano por turno durante N turnos.
- Cartas centralizadas nas fileiras.
- Ordenar (naipe, valor, HP, padrão) na mão e no tabuleiro.
- Descarte troca a carta (compra 1 na hora) e impede baixar outra no turno.
- Revide = metade do dano sofrido, mínimo 1.
- Carta que entra na Cadeia ganha armadura = HP + 50%, para cima. A frase admitia "50% do HP"; foi lida como 150%. Para mudar, use `COMMAND_ARMOR_MULT = 0.5`.
- Avisos do editor corrigidos: parâmetros `size` escondiam `Control.size`.
- O leque da mão e a faixa inicial agora esperam o layout (antes saíam errados no 1º quadro).

**Achado: descarte com compra + vagas cheias queimava o baralho.**
- Com as 15 vagas cheias não há jogada, mas o turno exige jogar ou descartar. Como o descarte compra, a IA descartava todo turno até esvaziar o baralho.
- Resultado: rodadas de 150 turnos e Cadeias vazias nas rodadas seguintes (~50% dos showdowns).
- Correção na IA (`_should_cycle`): sem jogada, só descarta se estiver perdendo e se o baralho guardar as compras das próximas rodadas; senão passa.
- **Um humano enfrenta a mesma escolha** (ver pendências).

Simulação depois disso (200 partidas):
- 2,31 rodadas, 66 turnos, 17 descartes por partida.
- Quem começa vence 42,5%.
- Full House é a mão mais comum. Quadra e Straight Flush são frequentes. Nenhuma Cadeia vazia.

## Sessão 2026-10-10 (5): temporizador, fim de partida, Selada explicada

- **Temporizador genérico** (`cooldown`) implementado. O Paladino agora cura todos a cada 3 turnos.
- O usuário relatou que "a infantaria não atacou a Cadeia". Era a regra **Selada**: o oponente tinha passado e não havia outros alvos. Não foi bug. A dica agora explica o motivo (`_why_idle`).
- O usuário relatou que "o jogo parou" no fim. A partida tinha acabado (vitória dele), mas o fim era um diálogo que sumia e deixava a mesa vazia. Agora:
  - O motor mantém o tabuleiro final.
  - A UI mostra um painel fixo com resultado, placar, resumo das rodadas e "Jogar de novo".
- `cards.json` passou a ser salvo pelo editor do Godot com indentação em tabs. Ao editar via script, não assuma espaços.

## Sessão 2026-10-10 (6): sem Selada, instantâneas, 104 cartas, menu e montador

Pedido do usuário:
- Passar não protege mais a Cadeia: o oponente gasta cartas para virar.
- Menu inicial e montador de baralhos; jogadores e IA montam os próprios.
- Instantâneas de volta.
- +52 unidades e +52 instantâneas seguindo os temas dos naipes.
- Única regra de baralho: ≥ 25 unidades.

Feito:
- `PASS_SEALS_COMMAND = false`. Textos de UI e dicas ajustados.
- Mecânicas genéricas novas (todas por JSON):
  - palavras-chave: Furtividade, Fúria, Roubo de Vida;
  - estados: Escudo, Congelada, Silenciada;
  - ops: `move`, `bounce`, `summon`, `set_value`, `mill`, `discard_own`, `ready`, `grant_kw`, `strip`;
  - gatilhos: `on_ally_played`, `on_cast`, `on_pass`;
  - filtros: `value_le/ge`, `kw`, `status`;
  - `per`: `allied_units`, `enemy_units`, `own_command`, `hand_size`, `damage_dealt`;
  - campo `cost`.
- 52 unidades novas, 52 instantâneas novas e as 13 antigas de volta, 2 fichas, baralhos `legiao`/`conspiracao`.
- `cards.json` foi gerado por script nesta sessão (o script não foi mantido; edite o JSON direto).
- `DeckStore`, `AIDeckBuilder`, `ui/app.gd` (cena principal), `ui/deck_builder.gd`. Botão Menu na partida e no painel de fim.
- Instantânea sem alvo exige 2 cliques (evita gasto acidental).
- IA: avaliação genérica para ops novas, efeitos de área, instantâneas e custos. Alvo de entrada obrigatório.
- Testes:
  - `cards_test.gd`: 169 cartas, sem erro;
  - `sim.gd`: + partidas com baralhos da IA, 169/169 cartas usadas;
  - `menu_smoke.gd`: valida 24 unidades recusado, 25 aceito, partida com o baralho salvo e IA automática.

Simulação:
- Padrão espelhado: 39 turnos por partida, quem começa vence 52%.
- Baralhos da IA, vitórias por naipe principal: ♥ Copas 63%, ♦ Ouros 52%, ♣ Paus 42%, ♠ Espadas 40%.

## Sessão 2026-10-10 (7): janelas de decisão e troca de mão

Pedido do usuário:
- Cartas "escolha dentre X cartas do seu cemitério / do oponente / dos dois" com janela de escolha; com 1 carta, aleatório sem janela.
- Na troca de rodada, depois da compra, descartar sem ir ao cemitério e recomprar até 10 cartas.

Feito:
- Motor: `pending`, `waiting_for`, `resolve_choice`, `mulligan`, `_grave_candidates`/`_grave_take`, suspensão e continuação da resolução.
- Cartas com escolha: Necromante, Coveiro, Exumar, Senhor dos Mortos (do oponente), Ressurreição (dos dois). Nova instantânea **Saque de Túmulos** (♦, pega qualquer carta do cemitério do oponente). Total: 170 cartas no acervo.
- UI: janela modal (`decision_panel` + `decision_shade`).
  - Escolha: clica na carta.
  - Troca: marca até N, depois "Trocar N" ou "Manter a mão".
- IA: `_resolve_pending`, `_card_worth`, `_mulligan_pick` (devolve unidades baixas, sem par e fora do plano).
- **Desempenho**: `_plan_command` testava todas as combinações da mão. Com mãos de 30+ cartas (Oráculo/Magnata), a partida pela UI levava 345 s. Agora usa só as 12 unidades mais promissoras (`PLAN_POOL`). Resultado: `sim.gd` caiu de ~4 min para ~1 min, e a partida pela UI para ~60 s.

## Sessão 2026-10-10 (8): inspeção pelo registro, troca iterativa, fileira de entrada, pilhas, 52 cartas

Pedido do usuário:
- O usuário perdeu uma carta para uma instantânea e não entendeu o que houve. Pediu clicar no nome da carta no registro para inspecioná-la.
- Troca de mão também no início, uma carta por vez, vendo a nova, até 10.
- Reviver/invocar perguntam Frente ou Retaguarda; a Cadeia só se a carta permitir.
- Botões para ver os cemitérios e o próprio baralho.
- Revivida reaplica a entrada.
- Mínimo de 52 cartas por baralho.

Feito:
- Links no registro + janela de inspeção (carta 2x, texto, local, histórico com a linha de causa).
- Instantânea do oponente fica 1,1 s no centro.
- `viewer_panel` para pilhas e inspeção (Esc ou clique fora fecha).
- Decisões genéricas (`_ask`), `_enter_board`, `_replay_on_play`, `_open_mulligan`/`mulligan_swap`/`mulligan_done`.
- `MIN_CARDS = 52`: `legiao`/`conspiracao` completados para 52; `AIDeckBuilder` monta 52.
- IA: `_pick_row`, alvo de revivida por `_best_target`, troca de mão uma a uma.
- Instantânea: "⚡♠ Espadas" no topo e "instantânea" embaixo (o rótulo antigo cortava).
- Testes: `sim.gd` ganhou `_test_decisions` (troca iterativa + Necromante → carta → fileira → alvo do Piromante revivido). Bug pego pelo `cards_test`: a continuação usava `pend.source`; agora é `block_source`.

## Sessão 2026-10-10 (9): troca de mão por seleção, fontes embutidas, web e Android

Pedido do usuário:
- Troca de mão: marcar várias cartas e confirmar (mantendo a repetição); filtros de naipe/valor; ver o baralho; inspecionar.
- Portar para Android e web (Chrome).

Feito:
- `_sync_mulligan`:
  - seleção (`mulligan_sel`, "TROCAR") + "Trocar N marcada(s)" + "Desmarcar" + "Concluir";
  - novas marcadas "NOVA";
  - filtros `mull_suit`/`mull_value`;
  - "Ver baralho";
  - inspeção por botão direito ou pelo interruptor `inspect_mode` (telas de toque).
- O `_input` global de botão direito não cancela nada com janela aberta (antes redesenhava por baixo dela).
- **Fontes embutidas** (`assets/fonts/ui_font.tres`, `gui/theme/custom_font`): Noto Sans + DejaVu Sans de reserva.
  - A primeira tentativa usou a Noto Sans Symbols 2 como reserva. As métricas dela subiram a altura de linha de TODOS os textos (21 px numa fonte de 12 px), e a carta cresceu.
  - Por isso a reserva é a DejaVu, e o ícone do temporizador virou ◷ (o ⏱ não existe na DejaVu).
- `CardView`:
  - nome com `max_lines_visible = 2` + `clip_text` + altura fixa `NAME_HEIGHT` (reticências com autowrap cortam já na 1ª linha no 4.5);
  - status e HP com `clip_text`;
  - topo em 17 px.
  - **A carta precisa medir sempre 92×112.**
- `project.godot`: `quit_on_go_back = false` (o "voltar" é tratado por `go_back()` em app/main/deck_builder), orientação sensor-paisagem, `import_etc2_astc`.
- Web e Android exportados e testados:
  - web no navegador embutido;
  - APK instalado no emulador, menu e partida por toque.

## Sessão 2026-10-10 (10): modo online (lockstep + caixa de correio PHP)

Pedido do usuário: multiplayer online rodando **na hospedagem compartilhada da Hostinger** (sem gastar com infra), com **toda a lógica no Godot**.

Feito:
- `Game`:
  - `action_log` + `_record`;
  - `apply_action(pid, act)`;
  - `state_hash()`;
  - `resign(pid)`, que NÃO entra em `history` (a rodada não terminou);
  - `set_viewer(me)` (nomes "Você"/"Oponente").
- `AIPlayer` ganhou `rng` próprio.
- `server/api.php`: caixa de correio genérica, com `seq` estrito (última + 1; reenvio idêntico é aceito) e token por assento. Usa SQLite ou MySQL e limpa salas paradas há mais de `ROOM_TTL_HOURS`.
- `net/online_client.gd`:
  - `call_api` (HTTPRequest, que funciona no desktop, no Android e na web);
  - sessão para retomar;
  - `make_meta`/`check_meta` (versão, hash do cards.json, validade do baralho).
- `ui/main.gd`:
  - `me`, `_opp()`, `_side()`;
  - laço `_net_loop`: outbox → inbox (esperando animações) → poll de 1,2 s só na vez do oponente;
  - `_net_collect` (manda as minhas entradas novas do `action_log`; o hash vai na última do lote);
  - `_net_fail`;
  - botão Desistir;
  - `_opp_turn_done()` devolve a dica "Sua vez." depois da vez do oponente (IA ou rede);
  - o cabeçalho mostra "Troca de mão" durante o mulligan.
- `ui/app.gd`: tela **Jogar online** (servidor, Criar sala, Entrar, Continuar partida). No Android, exige `https://`.
- Android: permissão `INTERNET`. O APK mira o SDK 35 e o Android bloqueia HTTP sem TLS, por isso só `https://` funciona.
- Pacote da hospedagem:
  - `tools/montar_hostinger.sh`;
  - `.htaccess` com wasm/pck, deflate e bloqueio de `config.php`, `.ht*` e `data/`, no formato duplo (Apache 2.4/2.2), que funciona no LiteSpeed;
  - guia `HOSTINGER.md`.
- Testes:
  - lockstep no `sim.gd`;
  - `net_test.gd` (2 partidas por HTTP);
  - `online_ui_smoke.gd` contra `net_bot.gd` em processo separado, nos dois assentos, que também verifica se a dica "Aguardando..." ficou presa.
  - Pacote testado num Apache 2.4 real (403 em `config.php`/`data/`, wasm com gzip) e partida jogada no navegador contra o bot.

Armadilhas encontradas:
- O navegador embutido oculto não roda `requestAnimationFrame`, e o Godot web congela. Para testar, troque `window.requestAnimationFrame` por um `setTimeout` via JS.
- `pkill -f padrão` casa com a própria linha de comando do bash e mata o shell. Use `pkill -f "tests/net_bot[.]gd"` numa chamada separada.
- `build/.gdignore` impede o editor de importar os builds (gerava `*.png.import` no pacote).

## Sessão 2026-10-11 (11): layout para celular e computador, tela cheia

Pedido do usuário:
- Ajustar o design para funcionar bem no celular e no desktop: botões ruins de tocar e toques acidentais (ex.: "Nova partida" logo abaixo do filtro/ordenação).
- "Tela cheia" que não enche: no celular sobrava espaço e tudo ficava pequeno; no desktop a janela maximizada não era tela cheia.

Diagnóstico (emulador 2400×1080, 420 dpi): a tela base 1600×1000 deixava textos de ~1 mm, fileiras com espaço vazio e o seletor "Ordenar" colado em "Nova partida".

Feito:
- `UiProfile` (perfil compacto/amplo, tema de toque, tela cheia, preferências) e o layout compacto descrito no princípio 9.
- `CardView`: face compacta, clique ao soltar, arrastar rola, toque longo inspeciona.
- Menu ☰ da partida: ordenar e animação viram botões de escolha única (antes, menus suspensos), tela cheia, pilhas (celular), e as ações de encerrar com confirmação. Passar a rodada também confirma.
- Telas do App: menu em duas colunas no celular, **Opções** (layout Automático/Celular/Computador + tela cheia), online responsivo, botão "Tela cheia" no menu da web, aviso "gire o celular" na web em pé. F11/Alt+Enter alternam a tela cheia; o desktop exportado abre em tela cheia e lembra a escolha.
- Montador: cartas compactas no celular, toque +1, toque longo −1, arrastar rola, grade centralizada, "Excluir" confirma.
- Dica atualizada depois de cada jogada (`_after_action_hint`); no celular "Clique" vira "Toque" nas dicas.
- Testes: `layout_smoke.gd` (todas as telas e janelas cabem na tela, nos dois modos). Verificado no emulador por toque (menu, troca de mão, toque longo, jogar carta, Passar com confirmação, ☰, montador com arrasto) e na web em modo celular (em pé e deitado) e computador.

## Pendências / próximos passos
- [ ] Tablet usa o layout de computador (escala ~0,6–0,8): jogável, mas pequeno. Ideia: perfil intermediário ou tela base 1280×800 em tablets.
- [ ] Arrastar a carta da mão até a fileira (hoje: toque na carta e depois na fileira).
- [ ] `ItemList` do montador não rola arrastando no celular (só pela barra).
- [ ] Mais cartas de escolha (ex.: "escolha 1 entre 3 instantâneas do seu cemitério").

- [ ] **Balanceamento por naipe** (baralhos da IA): ♥ Copas 63% contra ♠ Espadas 40%. Escudo + cura + Guardião parecem fortes demais; Espadas precisa de mais alcance contra a Cadeia.
- [ ] A IA joga instantâneas e cartas novas por heurística genérica; avaliar se usa bem `bounce`/`freeze`/`summon` (ex.: guardar remoção para a Cadeia).
- [ ] IA às vezes passa cedo e chega à rodada 3 com mão enorme (visto: 32 cartas com Oráculo/Magnata).
- [ ] **Vagas cheias**: decidir se encerrar o turno sem jogar é permitido quando não há jogada possível (hoje: descartar, que queima baralho, ou passar).
- [ ] Mãos fortes demais com 17 cartas: mão inicial menor, ou Cadeia mais exposta.
- [ ] HP sem teto + curas repetíveis: o HP cresce sem limite e o registro fica poluído.
- [ ] Hacker/Alquimista/Falsária/Rainha dos Espelhos criam cartas "repetidas" (ex.: dois K♥) ao trocar naipe/valor: intencional?
- [ ] Ficha devolvida à mão (`bounce` num Recruta) vai para a mão como carta jogável. Decidir se deve sumir.
- [ ] Montador: filtro por palavra-chave/mecânica e curva de valores mais visual.
- [ ] Mulligan no início (trocar até N cartas, estilo Gwent).
- [ ] Online: publicar na Hostinger de verdade e preencher `OnlineClient.PUBLIC_URL` antes de gerar o APK.
- [ ] Online: sem tempo limite por turno (um jogador pode travar a partida sumindo; o outro só pode voltar ao menu). Ideia: relógio por turno validado pelos dois lados.
- [ ] Online: lista de salas abertas / convite por link (`?sala=XXXXX` na web).
- [ ] Online: o host não sabe quando o convidado fechou o app (sem presença). Ideia: `poll` grava `last_seen` por assento.

## Armadilhas de GDScript neste projeto

- **Janela encoberta + vsync = 1 fps** (GNOME/Wayland): testes com janela parecem travados. Use `--disable-vsync` (ou `--headless`).
- **`MOUSE_FILTER_STOP` bloqueia a roda do mouse** para o ScrollContainer de cima. Para filhos clicáveis dentro de listas, use `PASS` e `accept_event()` só nos eventos tratados.
- **`OptionButton` alarga o pai** até o item mais longo: use `fit_to_longest_item = false` + `clip_text = true`.

- Não use `:=` com valores `Variant` (`dict.get()`, índice de array não tipado). Isso gera o erro "cannot infer type". Declare o tipo explicitamente (`var x: int = d.get(...)`).
- Prefira laços tipados: `for c: Card in arr:`. Use `mini`/`maxi`/`clampi` em vez de `min`/`max` (que retornam Variant).
- O método de registro se chama `_log` porque `log` é uma função builtin do GDScript; não crie métodos com nomes de builtins.
- Números do JSON chegam como `float`: sempre use `int(...)`.
- **Lambda conectado a um sinal de um objeto que o próprio lambda captura cria ciclo e vaza** ("ObjectDB instances leaked at exit"). Não capture o `Game` no lambda ligado a `g.event`, ou desconecte depois.
- **Lambdas capturam variáveis locais por valor.** `var n := 0; sig.connect(func(): n += 1)` nunca altera `n` fora do lambda. Use um `Dictionary` ou `Array` como contador (`counts["x"] += 1`).
- **Rótulo maior que a carta alarga a carta** (CardView 92 px). Isso quebra o leque da mão e as colunas do montador. Use `clip_text = true` em rótulos de texto livre.
- **ScrollContainer com `SCROLL_MODE_DISABLED`** herda a largura mínima do filho. Para uma grade que calcula as colunas pela largura disponível, use `SHOW_NEVER`.
- **Trocar de tela com coroutines vivas**: chame `shutdown()` (gera nova `anim_gen`, `closed = true`) e libere a tela depois (`create_timer(3).timeout.connect(queue_free)`). Senão as coroutines acordam num nó liberado.
- **Containers reposicionam os filhos** (e zeram scale/rotation no re-sort). Para mover uma carta, anime um clone numa camada livre (`cards_layer`), não o filho do container.
- Ao criar `class_name` novo, rode `--import` antes dos testes headless.
- Export: incluir `*.json` no filtro de recursos do preset, senão `cards.json` não vai pro build.
