#!/usr/bin/env bash
# Exporta a versão web e monta a pasta para subir na hospedagem compartilhada:
#   build/hostinger/          -> conteúdo para public_html (ou uma subpasta)
#   build/cadeia-hostinger.zip
# Uso: tools/montar_hostinger.sh   (GODOT=/caminho/do/godot para outro executável)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/Documentos/Godot_v4.5.1-stable_linux.x86_64}"
OUT=build/hostinger
mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html > /dev/null 2>&1
rm -rf "$OUT"
mkdir -p "$OUT/data"
cp build/web/* "$OUT/"
rm -f "$OUT"/*.import
cp server/api.php server/config.php "$OUT/"
cp server/data/.htaccess "$OUT/data/"
cp server/htaccess-site.txt "$OUT/.htaccess"
rm -f build/cadeia-hostinger.zip
(cd "$OUT" && python3 -m zipfile -c ../cadeia-hostinger.zip $(ls -A))
echo "Pronto:"
echo "  $(pwd)/$OUT"
echo "  $(pwd)/build/cadeia-hostinger.zip"
