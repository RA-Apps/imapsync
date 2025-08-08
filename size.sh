#!/bin/bash

############# CONFIGURATION ###########
ACCOUNTS=users.txt
SRCHOST=mail.com
DSTHOST=$SRCHOST
THREADS=8
OUTFILE="mailbox_sizes.txt"
TMPDIR=$(mktemp -d)
#######################################
TSFORMAT="%Y-%m-%d %H:%M:%S"

sync_account() {
    local SRCUSER="$1"
    local SRCPW="$2"
    local DSTUSER="$3"
    local DSTPW="$4"
    local TMPFILE="$5"

    echo "[$(date +"$TSFORMAT")] Syncing $SRCUSER@$SRCHOST to $DSTUSER@$DSTHOST ..."

    echo -n "$SRCPW" > "$TMPFILE/imap-secret-src"
    echo -n "$DSTPW" > "$TMPFILE/imap-secret-dst"

    local OUTPUT
    OUTPUT=$(imapsync --host1 "$SRCHOST" --ssl1 --port1 993 --authmech1 LOGIN --user1 "$SRCUSER" --passfile1 "$TMPFILE/imap-secret-src" \
                      --host2 "$DSTHOST" --ssl2 --port2 993 --authmech2 LOGIN --user2 "$DSTUSER" --passfile2 "$TMPFILE/imap-secret-dst" \
                      --justfoldersizes 2>/dev/null)

    rm -f "$TMPFILE/imap-secret-src" "$TMPFILE/imap-secret-dst"

    # Парсим размер из вывода
    local SIZE_LINE
    SIZE_LINE=$(echo "$OUTPUT" | grep "Total size.*bytes")
    # Пример строки: "Total size: 12345678 bytes (11.77 MiB)"
    local SIZE_HUMAN
    SIZE_HUMAN=$(echo "$SIZE_LINE" | sed -n 's/.*(\(.*\)).*/\1/p')

    # Сохраняем результат
    echo "$SRCUSER - $SIZE_HUMAN" > "$TMPFILE/result.txt"
}

export -f sync_account
export SRCHOST DSTHOST TSFORMAT

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

# Объединяем результаты
> "$OUTFILE"
TOTAL_BYTES=0

for file in "$TMPDIR"/job*/result.txt; do
    LINE=$(cat "$file")
    echo "$LINE" >> "$OUTFILE"

    # Пример: "user@example.com - 33.611 GiB"
    SIZE_HUMAN=$(echo "$LINE" | awk -F' - ' '{print $2}')
    VALUE=$(echo "$SIZE_HUMAN" | awk '{print $1}')
    UNIT=$(echo "$SIZE_HUMAN" | awk '{print $2}')

    case "$UNIT" in
        KiB) BYTES=$(awk "BEGIN {print $VALUE * 1024}") ;;
        MiB) BYTES=$(awk "BEGIN {print $VALUE * 1024 * 1024}") ;;
        GiB) BYTES=$(awk "BEGIN {print $VALUE * 1024 * 1024 * 1024}") ;;
        *) BYTES=0 ;;
    esac

    TOTAL_BYTES=$(awk "BEGIN {print $TOTAL_BYTES + $BYTES}")
done

TOTAL_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_BYTES / 1024 / 1024 / 1024}")
echo "Total: $TOTAL_GB GB" >> "$OUTFILE"

# Очистка
rm -rf "$TMPDIR"

echo "Done. Results saved to $OUTFILE"
