#!/bin/bash
set -eu
PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd)"
echo 'Control Center uygulamasını Command+Q ile kapatın.'
echo 'Dahili EFI yedeklenecek; uygulama ve sınırlı donanım yardımcısı kurulacak.'
echo 'Yalnızca bu kurulumda macOS parolanız istenecek. Sonraki açılışlarda istenmez.'
CURRENT_UID="$(/usr/bin/id -u)"
if /usr/bin/sudo /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/python3 -I "$PACKAGE_DIR/install/install-local.py" "$PACKAGE_DIR/Local-Install" "$CURRENT_UID" > >(tee "$PACKAGE_DIR/yerel-kurulum-sonucu.txt") 2>&1; then
 echo 'Kurulum başarılı.'
else
 echo 'Kurulum tamamlanmadı. yerel-kurulum-sonucu.txt dosyasını paylaşın.'
fi
read -r -p 'Kapatmak için Enter... '
