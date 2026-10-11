<?php
// Configuração da "caixa de correio" do modo online.
// Padrão: SQLite num arquivo dentro de data/ (não precisa criar banco no painel).
// Para usar MySQL (Hostinger: Bancos de dados > MySQL), troque DB_DSN, DB_USER e DB_PASS:
//   define('DB_DSN', 'mysql:host=localhost;dbname=u123_cadeia;charset=utf8mb4');
define('DB_DSN', 'sqlite:' . __DIR__ . '/data/salas.sqlite');
define('DB_USER', '');
define('DB_PASS', '');
// Salas sem atividade há mais que isso são apagadas (horas).
define('ROOM_TTL_HOURS', 72);
