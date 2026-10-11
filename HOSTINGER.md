# Publicar na Hostinger (hospedagem compartilhada)

O jogo inteiro roda no navegador (ou no APK). O servidor só guarda as salas do modo online, num arquivo PHP pequeno (`api.php`) que não conhece as regras do jogo. Não precisa de VPS, Node, WebSocket nem processo rodando: só a hospedagem compartilhada com PHP.

## 1. Gerar o pacote

```bash
/home/gabriel/Documentos/cadeia-de-comando/tools/montar_hostinger.sh
```

Isso exporta a versão web e monta:

- a pasta `/home/gabriel/Documentos/cadeia-de-comando/build/hostinger/`, com o conteúdo a subir;
- o zip `/home/gabriel/Documentos/cadeia-de-comando/build/cadeia-hostinger.zip`, com o mesmo conteúdo.

O que vai no pacote:

| Arquivo | Para quê |
|---|---|
| `index.html`, `index.js`, `index.wasm`, `index.pck`, `*.png`, `*.worklet.js` | o jogo (Godot web, sem threads) |
| `api.php` | a "caixa de correio" do modo online |
| `config.php` | onde ficam as salas (SQLite por padrão) |
| `data/.htaccess` | bloqueia o acesso direto ao banco de salas |
| `.htaccess` | tipo MIME do `.wasm`, compressão e bloqueio do `config.php` |

## 2. Subir

1. Painel da Hostinger: **Arquivos > Gerenciador de arquivos**.
2. Entre em `public_html`. Para o jogo ficar em `seusite.com/cadeia/`, crie uma subpasta `cadeia`.
3. Envie o `cadeia-hostinger.zip` e use **Extrair**. Ou envie o conteúdo da pasta `build/hostinger/`. Mande o conteúdo, não a pasta em si: o `index.html` precisa ficar direto em `public_html` (ou na subpasta).
4. Os arquivos que começam com ponto (`.htaccess` e `data/.htaccess`) precisam ir junto. O zip já os inclui.

Pronto: abra `https://seusite.com/` (ou `https://seusite.com/cadeia/`).

## 3. Conferir

- **PHP 8.0 ou superior**, em **Avançado > Configuração do PHP**. A Hostinger já vem com o 8.x.
- A extensão **pdo_sqlite** precisa estar ligada. Ela vem ligada por padrão; se não estiver, marque-a na mesma tela.
- **SSL (HTTPS)** ligado, em **Segurança > SSL**. É gratuito. Ele é obrigatório para o APK (veja abaixo).
- Teste rápido: `https://seusite.com/data/salas.sqlite` (ou `.../cadeia/data/salas.sqlite`) precisa dar **403 Proibido**. Esse arquivo só aparece depois da primeira sala criada.
- No jogo, clique em **Jogar online**. O campo **Servidor** já vem preenchido com o `api.php` ao lado do jogo. **Criar sala** mostra um código de 5 letras; o oponente digita o código e clica em **Entrar**.

## 4. Banco de dados

- **SQLite (padrão):** não precisa configurar nada. O arquivo `data/salas.sqlite` é criado sozinho na primeira sala. A pasta `data/` precisa ter permissão de escrita, e na Hostinger já tem.
- **MySQL (opcional):** se o SQLite der problema:
  1. crie um banco em **Bancos de dados > MySQL**;
  2. edite o `config.php` no Gerenciador de arquivos:

```php
define('DB_DSN', 'mysql:host=localhost;dbname=u123456789_cadeia;charset=utf8mb4');
define('DB_USER', 'u123456789_cadeia');
define('DB_PASS', 'a senha do banco');
```

As tabelas são criadas sozinhas. Salas paradas há mais de 72 horas (`ROOM_TTL_HOURS`) são apagadas quando alguém cria uma sala nova.

## 5. APK (Android) jogando online

- O Android bloqueia `http://` sem criptografia, então o APK só conversa com servidor **`https://`**.
- O jogador digita no campo **Servidor** o endereço completo, por exemplo `https://seusite.com/cadeia/api.php`. O jogo lembra o endereço depois.
- Para o APK já vir com o endereço preenchido:
  1. coloque a URL em `PUBLIC_URL`, no arquivo `/home/gabriel/Documentos/cadeia-de-comando/net/online_client.gd`;
  2. exporte o APK de novo.
- Um jogador no navegador e outro no APK podem jogar juntos, desde que usem o mesmo `api.php`.

## 6. Limites (hospedagem compartilhada)

- **Consumo:** cada jogador consulta o servidor a cada ~1,2 s, e só enquanto espera a jogada do oponente. Uma partida inteira dá algumas centenas de requisições pequenas, o que cabe folgado no plano compartilhado.
- **Atraso:** a jogada do oponente aparece com 1 a 2 segundos de atraso. Num jogo por turnos, isso é aceitável.
- **Versões iguais:** os dois jogadores precisam da mesma versão do jogo, com as mesmas cartas. Se as cartas forem diferentes, o jogo recusa a sala com uma mensagem. Depois de mudar cartas, suba o pacote novo e gere o APK de novo.
- **Conexão caída:** a partida fica guardada no servidor. Em **Jogar online > Continuar partida**, o jogo é refeito jogada por jogada.

## Testar no computador antes de subir

```bash
php -S 127.0.0.1:8090 -t /home/gabriel/Documentos/cadeia-de-comando/build/hostinger
```

Abra `http://localhost:8090` numa janela normal e numa janela anônima. São dois jogadores, cada um com os próprios dados salvos. Também dá para usar uma janela e o jogo no editor do Godot, com Servidor `http://127.0.0.1:8090/api.php`. Numa janela, **Criar sala**; na outra, **Entrar** com o código.
