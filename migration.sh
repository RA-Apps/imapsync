#!/bin/bash
############# CONFIGURATION ###########
ACCOUNTS=users.txt
SRCHOST=host1.com
DSTHOST=host2.com
THREADS=4
TMPDIR=$(mktemp -d)
ERROR_LOG=error.log
#######################################
TSFORMAT="%Y-%m-%d %H:%M:%S"
sync_account() {
    local SRCUSER="$1"
    local SRCPW="$2"
    local DSTUSER="$3"
    local DSTPW="$4"
    local TMPFILE="$5"
    local ERR_TMP="$TMPFILE/error.log.tmp"
    echo "[$(date +"$TSFORMAT")] Syncing $SRCUSER $SRCHOST to $DSTUSER $DSTHOST ..."
    echo -n "$SRCPW" > "$TMPFILE/imap-secret-src"
    echo -n "$DSTPW" > "$TMPFILE/imap-secret-dst"
    # Создаём временный файл для ошибок
    : > "$ERR_TMP"
    local OUTPUT
    OUTPUT=$(imapsync --host1 "$SRCHOST" --ssl1 --port1 993 --authmech1 LOGIN --user1 "$SRCUSER" --passfile1 "$TMPFILE/imap-secret-src" \
                      --host2 "$DSTHOST" --ssl2 --port2 993 --authmech2 LOGIN --user2 "$DSTUSER" --passfile2 "$TMPFILE/imap-secret-dst" \
                      --errorsmax 10 --nofoldersizes 2>&1 | tee -a "$ERR_TMP")
    # Проверяем, содержит ли временный файл ошибки, и записываем все строки с "Err 1/" в основной лог
    if [ -s "$ERR_TMP" ]; then
        grep -E "Err 1/" "$ERR_TMP" | while read -r line; do
            echo "[$(date +"$TSFORMAT")] $SRCUSER $SRCHOST -> $DSTUSER $DSTHOST: $line" >> "$ERROR_LOG"
        done
    fi
    rm -f "$TMPFILE/imap-secret-src" "$TMPFILE/imap-secret-dst" "$ERR_TMP"
}
export -f sync_account
export SRCHOST DSTHOST TSFORMAT ERROR_LOG
# Инициализируем основной файл логов
: > "$ERROR_LOG"
# Запускаем в параллели
grep -ve '^#.*' "$ACCOUNTS" | while read -r SRCUSER SRCPW DSTUSER DSTPW; do
    JOBTMP=$(mktemp -d "$TMPDIR/jobXXXX")
    # Если DSTUSER и DSTPW не указаны, используем SRCUSER и SRCPW
    if [ -z "$DSTUSER" ] || [ -z "$DSTPW" ]; then
        DSTUSER="$SRCUSER"
        DSTPW="$SRCPW"
    fi
    echo "$SRCUSER" "$SRCPW" "$DSTUSER" "$DSTPW" "$JOBTMP"
done | parallel -j "$THREADS" --colsep ' ' sync_account {1} {2} {3} {4} {5}
# Очистка
rm -rf "$TMPDIR"
echo "Done"
