#!/bin/bash
# Script to properly verify HTTP compression

API_URL="${1:-http://localhost:3000}"

echo "🔍 Verifying HTTP Compression"
echo "================================"
echo ""

# Test endpoint
ENDPOINT="${API_URL}/api/v1/posts"

echo "Testing: ${ENDPOINT}"
echo ""

# Without compression
echo "1️⃣ Without compression (baseline):"
UNCOMPRESSED_SIZE=$(curl -s "${ENDPOINT}" | wc -c | tr -d ' ')
echo "   Size: ${UNCOMPRESSED_SIZE} bytes"
echo ""

# With compression - check headers
echo "2️⃣ With compression (checking headers):"
COMPRESSED_HEADERS=$(curl -H "Accept-Encoding: gzip" -I -s "${ENDPOINT}")
CONTENT_ENCODING=$(echo "${COMPRESSED_HEADERS}" | grep -i "content-encoding" | cut -d: -f2 | tr -d ' ')
CONTENT_LENGTH=$(echo "${COMPRESSED_HEADERS}" | grep -i "content-length" | cut -d: -f2 | tr -d ' ')

if [ -n "${CONTENT_ENCODING}" ]; then
    echo "   ✅ Content-Encoding: ${CONTENT_ENCODING}"
else
    echo "   ❌ Content-Encoding: not set (compression may not be working)"
fi

if [ -n "${CONTENT_LENGTH}" ]; then
    echo "   Compressed size: ${CONTENT_LENGTH} bytes"
else
    echo "   Compressed size: chunked (no Content-Length header)"
fi
echo ""

# With compression - actual transferred bytes
echo "3️⃣ With compression (actual bytes transferred):"
TRANSFERRED_SIZE=$(curl -H "Accept-Encoding: gzip" -w "%{size_download}" -o /dev/null -s "${ENDPOINT}")
echo "   Transferred: ${TRANSFERRED_SIZE} bytes"
echo ""

# Calculate compression ratio
# Use transferred size (most accurate) or Content-Length header
if [ -n "${TRANSFERRED_SIZE}" ] && [ "${TRANSFERRED_SIZE}" != "0" ]; then
    COMPRESSED_SIZE="${TRANSFERRED_SIZE}"
elif [ -n "${CONTENT_LENGTH}" ] && [ "${CONTENT_LENGTH}" != "0" ]; then
    COMPRESSED_SIZE="${CONTENT_LENGTH}"
else
    COMPRESSED_SIZE="${UNCOMPRESSED_SIZE}"
fi

if [ "${COMPRESSED_SIZE}" -lt "${UNCOMPRESSED_SIZE}" ]; then
    REDUCTION=$(( (UNCOMPRESSED_SIZE - COMPRESSED_SIZE) * 100 / UNCOMPRESSED_SIZE ))
    echo "4️⃣ Compression Results:"
    echo "   Original: ${UNCOMPRESSED_SIZE} bytes"
    echo "   Compressed: ${COMPRESSED_SIZE} bytes"
    echo "   Reduction: ${REDUCTION}% ✅"
    echo ""
    echo "✅ Compression is working!"
else
    echo "4️⃣ Compression Results:"
    echo "   Original: ${UNCOMPRESSED_SIZE} bytes"
    echo "   Compressed: ${COMPRESSED_SIZE} bytes"
    echo "   Reduction: 0%"
    echo ""
    echo "⚠️  Compression may not be working or response is too small"
fi
