server {
  listen 80;

  root /var/www/html;

  location / {
    try_files $uri $uri/ /index.html;
  }

  location /api/app {
    proxy_pass        http://${hrm-private-ip}:8081/api/app;
    proxy_set_header  Access-Control-Allow-Origin "*";
    proxy_set_header  Access-Control-Allow-Methods "GET, POST, OPTIONS";
    proxy_set_header  Access-Control-Allow-Headers "Keep-Alive, User-Agent, X-Requested-With, If-Modified-Since, Cache-Control, Content-Type, X-CSRF-Token, X-HRM-Token";
    proxy_set_header  X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex";
  }

  location /sw.js {
    add_header Cache-Control "no-cache";
    proxy_cache_bypass $http_pragma;
    proxy_cache_revalidate on;
    expires off;
    access_log off;
  }
}
