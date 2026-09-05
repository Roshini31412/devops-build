# ---- Production image: serve pre-built static React app ----
FROM nginx:stable-alpine

LABEL maintainer="angelvroslin@gmail.com"
LABEL description="devops-build React app served via Nginx"

# Remove default Nginx static assets
RUN rm -rf /usr/share/nginx/html/*

# Copy the pre-built React app
COPY build/ /usr/share/nginx/html/

# Custom Nginx config (SPA routing + caching)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
