# Stage 1: Build Flutter Web application
FROM plugfox/flutter:3.47.2-web AS build

WORKDIR /app

# Copy dependency specifications first for layer caching
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

# Copy full application code and compile web release bundle
COPY . .
RUN flutter build web --release --no-tree-shake-icons

# Apply deployment-level cache busting to bootstrap, main entrypoint, and font manifests
RUN BUILD_ID=$(date +%s)-$(md5sum build/web/main.dart.js | cut -c 1-8) && \
    echo "Applying Cache Busting Build ID: ${BUILD_ID}" && \
    sed -i "s/flutter_bootstrap\.js/flutter_bootstrap\.js?v=${BUILD_ID}/g" build/web/index.html && \
    sed -i "s/\"main\.dart\.js\"/\"main\.dart\.js?v=${BUILD_ID}\"/g" build/web/flutter_bootstrap.js && \
    if [ -f build/web/assets/FontManifest.json ]; then \
        sed -i "s/MaterialIcons-Regular\.otf/MaterialIcons-Regular\.otf?v=${BUILD_ID}/g" build/web/assets/FontManifest.json; \
    fi

# Stage 2: Serve with lightweight Nginx alpine image
FROM nginx:1.27-alpine

# Copy compiled static assets from build stage to Nginx web root
COPY --from=build /app/build/web /usr/share/nginx/html

# Copy custom Nginx configuration with SPA routing, API reverse proxy, and cache headers
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
