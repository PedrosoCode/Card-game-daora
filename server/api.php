<?php
// Caixa de correio do modo online de Cadeia de Comando.
// NÃO conhece o jogo: guarda salas e mensagens opacas (texto) em ordem.
// Toda a lógica (regras, validação, sorteios) roda no Godot, nos dois aparelhos.
//
//   create {meta}                    -> {code, token, seat: 0}
//   join   {code, meta}              -> {token, seat: 1, host_meta}
//   send   {code, token, seq, data}  -> {seq}      (seq = última + 1; reenvio idêntico é aceito)
//   poll   {code, token, since}      -> {host_meta, guest_meta, messages: [{seq, seat, data}]}
require __DIR__ . '/config.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Cache-Control: no-store');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }

const MAX_META = 32768;
const MAX_DATA = 8192;
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

function reply($data, $status = 200) {
    http_response_code($status);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}
function fail($msg, $status = 400) { reply(['error' => $msg], $status); }

function db() {
    static $pdo = null;
    if ($pdo) return $pdo;
    $pdo = new PDO(DB_DSN, DB_USER, DB_PASS, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $text = str_starts_with(DB_DSN, 'mysql') ? 'MEDIUMTEXT' : 'TEXT';
    $key = str_starts_with(DB_DSN, 'mysql') ? 'VARCHAR(8)' : 'TEXT';
    $pdo->exec("CREATE TABLE IF NOT EXISTS rooms (code $key PRIMARY KEY, host_token VARCHAR(64) NOT NULL,
        guest_token VARCHAR(64), host_meta $text NOT NULL, guest_meta $text, updated_at INTEGER NOT NULL)");
    $pdo->exec("CREATE TABLE IF NOT EXISTS messages (code $key NOT NULL, seq INTEGER NOT NULL, seat INTEGER NOT NULL,
        data $text NOT NULL, PRIMARY KEY (code, seq))");
    return $pdo;
}

function room($code) {
    $st = db()->prepare('SELECT * FROM rooms WHERE code = ?');
    $st->execute([$code]);
    return $st->fetch(PDO::FETCH_ASSOC) ?: null;
}

// Assento (0 = quem criou, 1 = quem entrou) a partir do token secreto.
function seat_of($room, $token) {
    if (!is_string($token) || $token === '') return -1;
    if (hash_equals($room['host_token'], $token)) return 0;
    if ($room['guest_token'] !== null && hash_equals($room['guest_token'], $token)) return 1;
    return -1;
}

function touch_room($code) {
    db()->prepare('UPDATE rooms SET updated_at = ? WHERE code = ?')->execute([time(), $code]);
}

$in = json_decode(file_get_contents('php://input'), true);
if (!is_array($in)) fail('Corpo JSON inválido.');
$action = $in['action'] ?? '';
$code = strtoupper(trim((string)($in['code'] ?? '')));

try {
    switch ($action) {
    case 'create':
        $meta = (string)($in['meta'] ?? '');
        if ($meta === '' || strlen($meta) > MAX_META) fail('meta inválido.');
        // limpeza de salas abandonadas
        $old = time() - ROOM_TTL_HOURS * 3600;
        db()->prepare('DELETE FROM messages WHERE code IN (SELECT code FROM rooms WHERE updated_at < ?)')->execute([$old]);
        db()->prepare('DELETE FROM rooms WHERE updated_at < ?')->execute([$old]);
        $token = bin2hex(random_bytes(16));
        for ($i = 0; $i < 20; $i++) {
            $code = '';
            for ($k = 0; $k < 5; $k++) $code .= CODE_CHARS[random_int(0, strlen(CODE_CHARS) - 1)];
            try {
                db()->prepare('INSERT INTO rooms (code, host_token, host_meta, updated_at) VALUES (?, ?, ?, ?)')
                    ->execute([$code, $token, $meta, time()]);
                reply(['code' => $code, 'token' => $token, 'seat' => 0]);
            } catch (PDOException $e) { /* código repetido: tenta outro */ }
        }
        fail('Não foi possível criar a sala.', 500);

    case 'join':
        $meta = (string)($in['meta'] ?? '');
        if ($meta === '' || strlen($meta) > MAX_META) fail('meta inválido.');
        $r = room($code);
        if (!$r) fail('Sala não encontrada.', 404);
        if ($r['guest_token'] !== null) fail('A sala já está cheia.', 409);
        $token = bin2hex(random_bytes(16));
        $st = db()->prepare('UPDATE rooms SET guest_token = ?, guest_meta = ?, updated_at = ? WHERE code = ? AND guest_token IS NULL');
        $st->execute([$token, $meta, time(), $code]);
        if ($st->rowCount() !== 1) fail('A sala já está cheia.', 409);
        reply(['token' => $token, 'seat' => 1, 'host_meta' => $r['host_meta']]);

    case 'send':
        $r = room($code);
        if (!$r) fail('Sala não encontrada.', 404);
        $seat = seat_of($r, $in['token'] ?? '');
        if ($seat < 0) fail('Token inválido.', 403);
        $seq = (int)($in['seq'] ?? 0);
        $data = (string)($in['data'] ?? '');
        if ($data === '' || strlen($data) > MAX_DATA) fail('data inválido.');
        $pdo = db();
        $pdo->beginTransaction();
        $st = $pdo->prepare('SELECT seat, data FROM messages WHERE code = ? AND seq = ?');
        $st->execute([$code, $seq]);
        $same = $st->fetch(PDO::FETCH_ASSOC);
        if ($same) {
            $pdo->rollBack();
            // reenvio da mesma mensagem (resposta anterior se perdeu): aceito
            if ((int)$same['seat'] === $seat && $same['data'] === $data) reply(['seq' => $seq]);
            fail('Sequência já usada.', 409);
        }
        $st = $pdo->prepare('SELECT COALESCE(MAX(seq), 0) FROM messages WHERE code = ?');
        $st->execute([$code]);
        $last = (int)$st->fetchColumn();
        if ($seq !== $last + 1) { $pdo->rollBack(); fail("Sequência fora de ordem (esperada " . ($last + 1) . ").", 409); }
        $pdo->prepare('INSERT INTO messages (code, seq, seat, data) VALUES (?, ?, ?, ?)')->execute([$code, $seq, $seat, $data]);
        $pdo->commit();
        touch_room($code);
        reply(['seq' => $seq]);

    case 'poll':
        $r = room($code);
        if (!$r) fail('Sala não encontrada.', 404);
        if (seat_of($r, $in['token'] ?? '') < 0) fail('Token inválido.', 403);
        $st = db()->prepare('SELECT seq, seat, data FROM messages WHERE code = ? AND seq > ? ORDER BY seq LIMIT 500');
        $st->execute([$code, (int)($in['since'] ?? 0)]);
        $msgs = [];
        foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $m) {
            $msgs[] = ['seq' => (int)$m['seq'], 'seat' => (int)$m['seat'], 'data' => $m['data']];
        }
        reply(['host_meta' => $r['host_meta'], 'guest_meta' => $r['guest_meta'], 'messages' => $msgs]);
    }
    fail('Ação desconhecida.');
} catch (PDOException $e) {
    fail('Erro no banco de dados.', 500);
}
