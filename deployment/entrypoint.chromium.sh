#!/bin/sh
# Entrypoint script for Chromium service used by ChromicPDF
# Runs Chromium on internal port 9223 with nginx reverse proxy on 9222
# nginx rewrites Host header to bypass Chromium's origin restrictions
# See: https://hexdocs.pm/chromic_pdf/ChromicPDF.html#module-remote-chrome

# Generate nginx config
cat > /tmp/nginx.conf <<'EOF'
daemon off;
error_log /dev/stderr warn;
pid /tmp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /dev/stdout;
    client_body_temp_path /tmp/nginx_client_body;
    proxy_temp_path /tmp/nginx_proxy;
    fastcgi_temp_path /tmp/nginx_fastcgi;
    uwsgi_temp_path /tmp/nginx_uwsgi;
    scgi_temp_path /tmp/nginx_scgi;

    server {
        listen 9222;
        
        # Rewrite Chromium's internal WebSocket URLs to use the external port
        # This ensures clients connect through nginx instead of directly to Chromium
        sub_filter '127.0.0.1:9223' '$http_host';
        sub_filter_once off;
        sub_filter_types application/json;
        
        location / {
            proxy_pass http://127.0.0.1:9223;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host "127.0.0.1:9223";
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            
            # Disable compression so sub_filter can work
            proxy_set_header Accept-Encoding "";
        }
    }
}
EOF

# Start Chromium on localhost:9223 (not exposed externally)
chromium-browser \
  --no-sandbox \
  --headless \
  --remote-debugging-port=9223 \
  --remote-debugging-address=127.0.0.1 &

CHROME_PID=$!

# Wait for Chromium to start
echo "Waiting for Chromium to start on 127.0.0.1:9223..."
for i in $(seq 1 30); do
  if wget -q -O - http://127.0.0.1:9223/json/version >/dev/null 2>&1; then
    echo "Chromium is ready!"
    break
  fi
  sleep 1
done

# Start nginx reverse proxy
echo "Starting nginx reverse proxy on 0.0.0.0:9222 → 127.0.0.1:9223"
nginx -c /tmp/nginx.conf &

NGINX_PID=$!

# Cleanup function
cleanup() {
  echo "Shutting down..."
  kill $NGINX_PID 2>/dev/null
  kill $CHROME_PID 2>/dev/null
  wait
}

trap cleanup TERM INT

# Wait for Chromium process
wait $CHROME_PID
