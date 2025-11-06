# HTTP Compression Verification Guide

> **How to verify that HTTP compression is working correctly**

This guide explains how to verify that Gzip compression is enabled and working for API responses.

---

## Why Content-Length Isn't Available

**Important:** The `Content-Length` header is **not available** when the compression middleware runs because:

1. **Middleware runs before body generation**: Rack middleware executes before the response body is fully generated
2. **Content-Length is set after body**: The `Content-Length` header is typically set by Rails after the body is generated
3. **Rack::Deflater compresses on-the-fly**: The compression happens during body streaming, not before

**This is normal and expected behavior!** Rack::Deflater has built-in logic to skip very small responses (<860 bytes) automatically.

---

## How to Verify Compression is Working

### Method 1: Using curl (Recommended)

**Test API endpoint:**
```bash
curl -H "Accept-Encoding: gzip" -v http://localhost:3000/api/v1/posts 2>&1 | grep -i "content-encoding"
```

**Expected output:**
```
< content-encoding: gzip
```

**Full verbose test:**
```bash
curl -H "Accept-Encoding: gzip" -v http://localhost:3000/api/v1/posts
```

**Look for:**
- `Content-Encoding: gzip` in response headers
- Smaller `Content-Length` value (compressed size)
- Response body is binary (compressed)

**Compare compressed vs uncompressed:**
```bash
# Without compression
curl http://localhost:3000/api/v1/posts | wc -c

# With compression
curl -H "Accept-Encoding: gzip" --compressed http://localhost:3000/api/v1/posts | wc -c
```

The compressed version should be significantly smaller (80-90% reduction).

### Method 2: Using Browser DevTools

1. **Open browser DevTools** (F12)
2. **Go to Network tab**
3. **Make a request** to an API endpoint (e.g., `/api/v1/posts`)
4. **Click on the request** to see details
5. **Check Headers section:**

**Look for:**
- **Response Headers**: `Content-Encoding: gzip`
- **Request Headers**: `Accept-Encoding: gzip, deflate, br`

**Compare sizes:**
- **Size**: Original uncompressed size
- **Transferred**: Compressed size (what was actually sent)
- **Compression ratio**: `(Size - Transferred) / Size * 100%`

**Example:**
```
Size: 500 KB
Transferred: 50 KB
Compression: 90% reduction ✅
```

### Method 3: Using the Test Script

**Run the test script:**
```bash
cd microblog-backend
bin/rails runner script/test_compression.rb
```

**Or with custom API URL:**
```bash
API_URL=http://localhost:3000 bin/rails runner script/test_compression.rb
```

**Expected output:**
```
🔍 Testing HTTP Compression
============================================================
Base URL: http://localhost:3000
Make sure the Rails server is running!
============================================================

Health Check Endpoint
============================================================
Endpoint: http://localhost:3000/up
Status: 200
Content-Encoding: none
Content-Type: application/json; charset=utf-8
❌ Compression: NOT ENABLED
   Possible reasons:
   - Response too small (<860 bytes, Rack::Deflater default)
   - Content type not in compressible list
   - Health check endpoint (/up) excluded
------------------------------------------------------------

API Posts Endpoint
============================================================
Endpoint: http://localhost:3000/api/v1/posts
Status: 200
Content-Encoding: gzip
Content-Type: application/json; charset=utf-8
Content-Length: 5234
✅ Compression: ENABLED
   Compressed size: 5234 bytes
------------------------------------------------------------
```

### Method 4: Using HTTPie

```bash
# Install HTTPie if needed
# brew install httpie  # macOS
# apt-get install httpie  # Linux

# Test with compression
http GET http://localhost:3000/api/v1/posts Accept-Encoding:gzip

# Check response headers
http --headers GET http://localhost:3000/api/v1/posts Accept-Encoding:gzip
```

---

## What to Look For

### ✅ Compression is Working

**Response headers include:**
```
Content-Encoding: gzip
Vary: Accept, Accept-Encoding
Content-Length: <smaller number>  # Compressed size
```

**Request headers include:**
```
Accept-Encoding: gzip, deflate, br
```

**Size comparison:**
- Original: 500 KB
- Compressed: 50 KB
- Ratio: 90% reduction

### ❌ Compression is NOT Working

**Possible reasons:**

1. **Response too small** (<860 bytes)
   - Rack::Deflater automatically skips very small responses
   - This is normal and expected
   - Small responses don't benefit from compression

2. **Content-Type not in compressible list**
   - Check that `Content-Type` is `application/json` or other compressible type
   - Check `config/initializers/compression.rb` for included types

3. **Health check endpoint excluded**
   - `/up` endpoint is intentionally excluded (small response)
   - This is normal

4. **Client doesn't support compression**
   - Check that `Accept-Encoding: gzip` is in request headers
   - Modern browsers include this automatically

5. **Middleware not loaded**
   - Check Rails logs for errors
   - Verify `config/initializers/compression.rb` exists
   - Restart Rails server after adding compression config

---

## Testing Different Endpoints

### Large Response (Should Compress)
```bash
# Get posts feed (likely large response)
curl -H "Accept-Encoding: gzip" -v http://localhost:3000/api/v1/posts
```

### Small Response (May Not Compress)
```bash
# Health check (small, excluded)
curl -H "Accept-Encoding: gzip" -v http://localhost:3000/up

# Single post (may be small)
curl -H "Accept-Encoding: gzip" -v http://localhost:3000/api/v1/posts/1
```

### Authenticated Endpoint
```bash
# Login first to get token
TOKEN=$(curl -X POST http://localhost:3000/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test"}' | jq -r '.token')

# Test authenticated endpoint
curl -H "Accept-Encoding: gzip" \
     -H "Authorization: Bearer $TOKEN" \
     -v http://localhost:3000/api/v1/me
```

---

## Troubleshooting

### Issue: No Content-Encoding Header

**Check:**
1. Is the response large enough? (>860 bytes)
2. Is the Content-Type compressible? (application/json, text/html, etc.)
3. Is the endpoint excluded? (e.g., `/up`)
4. Is the middleware loaded? (check Rails logs)

**Debug:**
```ruby
# In Rails console
Rails.application.config.middleware.to_a.map(&:name)
# Should include: Rack::Deflater
```

### Issue: Compression Not Working for Specific Endpoint

**Check:**
1. Response size (must be >860 bytes)
2. Content-Type header
3. Path matches `/api/*` pattern

**Test:**
```bash
# Get response size
curl http://localhost:3000/api/v1/posts | wc -c

# If < 860 bytes, compression won't apply
```

### Issue: Browser Shows No Compression

**Check:**
1. Browser DevTools → Network tab
2. Look for `Content-Encoding: gzip` in response headers
3. Compare "Size" vs "Transferred" columns
4. Clear browser cache and try again

---

## Expected Behavior

### Endpoints That Should Compress

- ✅ `/api/v1/posts` (large response)
- ✅ `/api/v1/posts/:id` (if response is large)
- ✅ `/api/v1/users/:id` (if response is large)
- ✅ Any API endpoint returning >860 bytes of JSON

### Endpoints That May Not Compress

- ⚠️ `/up` (health check, excluded, small)
- ⚠️ `/api/v1/me` (if response is <860 bytes)
- ⚠️ Empty responses or error responses

**This is normal!** Small responses don't benefit from compression and the overhead isn't worth it.

---

## Performance Verification

**Before compression:**
```bash
time curl http://localhost:3000/api/v1/posts > /dev/null
# Real: 2.5s
```

**After compression:**
```bash
time curl -H "Accept-Encoding: gzip" --compressed http://localhost:3000/api/v1/posts > /dev/null
# Real: 0.3s
```

**Expected improvement:** 5-10x faster transfer time on slow networks.

---

## Summary

**To verify compression is working:**

1. ✅ Check for `Content-Encoding: gzip` in response headers
2. ✅ Compare "Size" vs "Transferred" in browser DevTools
3. ✅ Use curl with `Accept-Encoding: gzip` header
4. ✅ Run the test script: `bin/rails runner script/test_compression.rb`

**Remember:**
- `Content-Length` not being available in middleware is **normal**
- Small responses (<860 bytes) won't compress (by design)
- Health check endpoint (`/up`) is excluded (by design)
- Compression only applies to responses >860 bytes

---

**Related Documentation:**
- [API Optimization Strategies](../docs/049_API_OPTIMIZATION_STRATEGIES.md)
- [Compression Configuration](../config/initializers/compression.rb)

