# Cadeia de Comando — Regras (protótipo v0.9)

Card game 1v1 que mistura Gwent (rodadas, passar e economia de cartas), Magic (unidades, efeitos, ativos e passivos) e Poker (quem vence é a melhor mão).

## As cartas

- **Unidade**: tem **naipe**, **valor** (2 a 10, J, Q, K, A), **HP** e **ATQ**. Pode ter efeito ao entrar, efeito ativo, efeitos passivos e palavras-chave. Vai para o tabuleiro.
- **Instantânea** (⚡): tem só um naipe de tema. Ao ser usada, resolve na hora e vai **direto para o cemitério**: não entra no tabuleiro nem conta no poker. Usar uma instantânea conta como a carta do turno.
- O acervo tem **104 unidades** (dois conjuntos completos de 2 a A em cada naipe) e **66 instantâneas** (13 a 17 por naipe).
- **Naipes** e a identidade de cada um:

| Naipe | Estilo |
|---|---|
| ♠ Espadas | ataque: dano direto, sangramento, Investida, Alcance, Fúria, Furtividade, puxar unidades da Retaguarda |
| ♥ Copas | proteção: cura, armadura, Guardiões, Escudo, Recrutas, recompensas por passar |
| ♦ Ouros | manipulação: valor e naipe das Cadeias, compra, descarte, congelar, silenciar, devolver à mão, moer o baralho |
| ♣ Paus | morte: veneno, cemitério, destruição, Roubo de Vida, Esqueletos, efeitos ao morrer |

## Baralhos

- **Regras de montagem: pelo menos 52 cartas e pelo menos 25 unidades.** Não há outra restrição: cópias da mesma carta e valores e naipes repetidos são permitidos.
- Baralhos prontos: **Padrão** (as 52 unidades originais, um baralho comum), **Legião de Aço** (♠ ♥ + instantâneas) e **Conspiração** (♦ ♣ + instantâneas).
- Você monta e salva os seus no **Montar baralhos**. A IA pode usar qualquer baralho ou **montar o próprio** a cada partida.

## O tabuleiro (por jogador)

| Fileira | Vagas | Ataca? | Conta no poker? |
|---|---|---|---|
| 1. Frente de Batalha | 5 | Sim | Não |
| 2. Retaguarda | 5 | Sim | Não |
| 3. Cadeia de Comando | 5 | Não | **Sim** |

Qualquer unidade pode entrar em qualquer fileira. A Cadeia de Comando é a sua mão de poker.

**Armadura de comando:** a carta que entra na Cadeia de Comando ganha armadura igual ao HP dela + 50%, arredondado para cima (HP 4 → 6 de armadura; HP 5 → 8).

## Partida

- **Melhor de 3 rodadas.** Cada jogador começa com **2 vidas**.
- Mão inicial: **17 cartas**. No início da 2ª e da 3ª rodada, cada um **compra 10**. Não há compra por turno.
- Quem começa a 1ª rodada é sorteado. Nas seguintes, começa **quem perdeu** a anterior (em empate, alterna).
- **Troca de mão:** no início de **cada rodada** (inclusive a 1ª, e depois da compra de 10 nas outras), cada jogador tem **até 10 trocas**. Ele marca uma ou mais cartas e confirma: elas voltam para o baralho (não vão para o cemitério) e ele compra o mesmo número na hora, já vendo as novas. Pode repetir, inclusive com as cartas que acabaram de entrar, até gastar as 10 trocas ou concluir. A janela tem filtros de naipe e valor, mostra o baralho e permite inspecionar cartas.

## O turno

No seu turno você pode, em qualquer ordem:

1. **Jogar exatamente 1 carta**: uma unidade numa fileira **ou** uma instantânea; **ou descartar 1 carta**. O descarte troca a carta: ela vai para o cemitério e você **compra 1 na hora**, mas não pode mais baixar carta neste turno.
2. **Atacar** com cada unidade pronta da Frente ou Retaguarda (uma vez cada).
3. **Usar o efeito ativo** de cada carta pronta (uma vez cada), respeitando a fileira exigida.

Depois, **encerre o turno**. Só é possível encerrar depois de jogar ou descartar uma carta. A exceção é quando a sua mão está vazia: aí o turno serve só para atacar e usar efeitos. Se não quiser mais jogar, **passe a rodada**.

**Exaustão:** uma carta que acabou de entrar só ataca e usa ativos no seu próximo turno. A palavra-chave Investida libera o ataque.

## Passar e fim da rodada

- Quem passa não joga mais nesta rodada. O outro continua jogando turnos.
- **Quem passa continua exposto:** o oponente ainda pode atacar e usar efeitos nas suas cartas, inclusive na Cadeia de Comando. A ideia é obrigá-lo a **gastar cartas** para virar a rodada, o que quebra a economia dele para as próximas. (A antiga regra "Selada" existe no código, mas está desligada.)
- Um jogador **terminou a rodada** quando passou ou ficou sem cartas na mão. Sem cartas, ele ainda tem turnos para atacar e usar efeitos enquanto o outro joga.
- Quando os dois terminaram, há o **showdown**. As Cadeias de Comando são comparadas como mãos de poker (as regras de mão estão na próxima seção). Quem perde, perde 1 vida. Em empate, os dois perdem.
- Todas as cartas do tabuleiro vão para o **cemitério** (na última rodada, o tabuleiro final fica na mesa).
- Com 0 vidas, o jogo acaba. Se os dois chegarem a 0 juntos, é empate.

Algumas cartas recompensam passar (ex.: Pajem Leal, Rei Benevolente, Prefeito Corrupto).

## Mãos de poker

Da mais fraca para a mais forte: Carta Alta, Par, Dois Pares, Trinca, Sequência, Flush, Full House, Quadra, Straight Flush.

- A mão usa o **valor atual** das cartas, com modificadores e auras.
- Cadeia vazia perde de qualquer mão.
- Sequência e Flush exigem 5 cartas. A-2-3-4-5 conta como sequência, com o 5 como carta mais alta.
- Desempate: as cartas que formam a jogada e, depois, os kickers. Com o resto igual, ter mais cartas vence.

## Combate e dano

- **Ataque**: a unidade causa seu ATQ ao alvo. **Não existe revide automático.** Só revidam as cartas que têm a passiva **Revide** (Cavaleiro da Coroa, Golem de Caldeira e Ciborgue Mercenário): ela devolve a quem atacou **metade do dano sofrido** (armadura consumida conta), mínimo 1. Uma carta destruída pelo ataque não revida.
- **Quem alcança a Cadeia de Comando**: só unidades da **Frente de Batalha**, e só enquanto a **Retaguarda inimiga estiver vazia**. A Retaguarda nunca ataca a Cadeia. Efeitos alcançam sempre.
- **Guardião**: se o inimigo tiver um Guardião na Frente de Batalha, os ataques precisam mirar um Guardião.
- **Alcance**: ignora Guardiões e a proteção da Cadeia (ataca qualquer carta, de qualquer fileira).
- **HP** não tem teto: curar ou fortalecer aumenta o HP mesmo acima do valor impresso.
- **Armadura** é um segundo HP, consumido antes do HP.
- **Veneno N** e **Sangramento N**: no início de cada turno do dono, causam **1 de dano** e o acúmulo diminui 1. Ou seja, N acúmulos = 1 de dano por turno durante N turnos. Os dois **ignoram armadura** e somam se a carta tiver ambos.
- Se o dono passou, os DoTs dele correm no início dos turnos do oponente.

### Palavras-chave e estados

| | |
|---|---|
| **Guardião** | na Frente, obriga os ataques inimigos a mirarem um Guardião |
| **Investida** | ataca no turno em que entra |
| **Alcance** | ataca qualquer carta, ignorando Guardiões e a proteção da Cadeia |
| **Furtividade** | não pode ser alvo de ataques até atacar (efeitos o alcançam) |
| **Fúria** | ataca duas vezes por turno |
| **Roubo de Vida** | ao causar dano atacando, cura essa quantidade |
| **Escudo N** | anula por completo as próximas N instâncias de dano (veneno e sangramento passam) |
| **Congelada** | perde o próximo turno: não ataca nem usa ativos (nem com Investida) |
| **Silenciada** | perde passivas, ativo, auras e palavras-chave |
| **Fichas** | Recruta (2♥) e Esqueleto (2♣) são invocadas por cartas; entram no tabuleiro e contam no poker se forem para a Cadeia, mas não entram em baralhos |
- HP 0 destrói a carta, que vai para o cemitério.

## Temporizador

Alguns efeitos têm **Temporizador N** (ex.: Paladino Sagrado, Temporizador 3):
- O temporizador começa em N quando a carta entra e desce 1 no início de cada turno seu (a carta mostra ⏱N).
- Quando chega a 0, o efeito acontece (passiva de início de turno) ou fica disponível (ativo, ou passiva disparada por um evento) e o temporizador recomeça em N.
- O Paladino cura no 3º, 6º, 9º... turno seu depois de entrar.

## Cemitério

**Cartas que entram por efeito** (reviver, invocar): o dono escolhe se entram na **Frente** ou na **Retaguarda**. A Cadeia de Comando só é opção se a carta disser isso. Uma carta **revivida reaplica o próprio efeito de entrada** (escolhendo o alvo, se ele tiver um).

**Escolha no cemitério:** cartas como Necromante, Coveiro, Exumar, Senhor dos Mortos, Ressurreição e Saque de Túmulos dizem "escolha 1 entre 3 cartas" do seu cemitério, do cemitério do oponente ou dos dois. O jogo sorteia 3 cartas daquele(s) cemitério(s) e abre uma janela para você escolher. Com 1 carta só, a escolha é aleatória e sem janela. Uma carta tirada do cemitério do oponente passa a ser sua.

Recebe as cartas destruídas, as descartadas e todo o tabuleiro ao fim de cada rodada. As cartas interagem com ele de várias formas: reviver (Necromante), recuperar para a mão (Sucateiro, Coveiro), escalar com o tamanho do cemitério (Rei Caído, Espectro) e exilar o cemitério inimigo (Lich, Profanador).

Uma carta que sai do cemitério volta zerada: HP cheio, sem modificadores e sem status.

## Partida online

- **Jogar online** no menu. Um jogador clica em **Criar sala** e passa o código de 5 letras; o outro digita o código e clica em **Entrar**. Cada um joga com o próprio baralho, e as regras são as mesmas da partida contra a IA.
- Quem começa é sorteado. A troca de mão é feita um de cada vez: primeiro um jogador, depois o outro.
- A jogada do oponente aparece com 1 a 2 segundos de atraso.
- **Desistir** encerra a partida, com vitória do oponente. Só dá para desistir na sua vez.
- Se a conexão cair ou o jogo fechar, use **Jogar online > Continuar partida**: a partida volta de onde parou.

## Decisões que tomei por você

Estas lacunas foram preenchidas com padrões. Todas são fáceis de mudar:

| Decisão | Onde mudar |
|---|---|
| 1 carta por turno (jogar ou descartar), obrigatória para encerrar | `Game.can_end_turn` |
| Descarte compra 1 na hora | `Game.discard` |
| Armadura de comando = HP × 1,5 (para cima) | `Game.COMMAND_ARMOR_MULT` |
| Mão inicial 17, +10 por rodada, sem compra por turno | `Game.START_HAND`, `Game.DRAW_AFTER_ROUND` |
| Unidades entram exaustas | `Card.exhausted` / `Game.play_card` |
| Revide só via passiva `on_attacked`, metade do dano sofrido (mín. 1) | `Game.attack`, `per: half_damage_taken` |
| Só a Frente ataca a Cadeia, com a Retaguarda inimiga vazia | `Game.BACK_PROTECTS_COMMAND`, `Game.can_hit_command` |
| Passar NÃO sela a Cadeia (desligado a pedido) | `Game.PASS_SEALS_COMMAND` |
| Pelo menos 52 cartas e 25 unidades por baralho | `DeckStore.MIN_CARDS`, `DeckStore.MIN_UNITS` |
| Troca de mão: até 10, uma por vez, em toda rodada | `Game.MULLIGAN_MAX`, `Game.mulligan_swap` |
| Alvo de entrada obrigatório quando existe | `Game.play_card` |
| Veneno e sangramento: 1 por turno, N turnos, ignoram armadura | `Game._tick_dots`, `Game.DOTS_PIERCE_ARMOR` |
| Showdown quando os dois passaram ou ficaram sem cartas na mão | `Game.is_done`, `Game._end_round` |
| 2 vidas; empate tira vida dos dois; perdedor começa a próxima | `Game.START_GEMS`, `Game._end_round` |
| 5 vagas por fileira | `Game.ROW_SIZE` |
| Online: uma pessoa age por vez; desistir só na sua vez | `Game.waiting_for`, `Main._my_action_time` |
