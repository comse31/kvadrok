# Раздача HTML5-бандла Defold (wasm-web) через nginx.
#
# Контекст сборки — корень репозитория. Бандл должен быть собран заранее:
#   java -jar bob.jar --root . --platform wasm-web --architectures wasm-web \
#     --archive --variant release --bundle-output dist/web resolve build bundle
#
# Сборка и запуск:
#   docker build -f docker/Dockerfile -t kvadrok-web .
#   docker run --rm -p 8098:80 kvadrok-web
# затем открыть http://localhost:8098

FROM nginx:1.27-alpine

COPY docker/nginx.conf /etc/nginx/nginx.conf

# bob для HTML5 создаёт вложенную папку с именем проекта (title=kvadrok).
COPY dist/web/kvadrok/ /usr/share/nginx/html/

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
