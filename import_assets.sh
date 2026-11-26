failed=()
success=0

for file in GLBs/coaster/coaster-flume-*.glb; do
    [ -f "$file" ] || continue

    name=$(basename "$file" .glb)
    name="${name#coaster-flume-}"

    echo "Importing Coaster/Flume/$name"

    if node tools/import-glb.js \
        "Coaster/Flume/$name" \
        "$file" \
        --auto-collision; then
        success=$((success + 1))
    else
        failed+=("$file")
        echo "FAILED: $name - continuing..."
    fi

    echo
done

echo "========================================"
echo "Import complete"
echo "Successful: $success"
echo "Failed:     ${#failed[@]}"
echo "========================================"

if [ ${#failed[@]} -gt 0 ]; then
    echo "Failed imports:"
    printf '  %s\n' "${failed[@]}"
fi
