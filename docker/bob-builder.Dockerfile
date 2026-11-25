# Образ-сборщик Defold (bob) для CI.
#
# bob.jar собран под Java 25 (class file version 69), поэтому база —
# eclipse-temurin:25-jdk. Нативные инструменты bob (ModelImporterJni и др.)
# линкуются с системными библиотеками X11/GL, поэтому они ставятся здесь один
# раз: при повторных сборках этот слой берётся из кэша Docker, и apt-get больше
# не выполняется.
#
# ПОЧЕМУ bob.jar НЕ КАЧАЕТСЯ ИЗ d.defold.com.
# Скачивание bob.jar напрямую с d.defold.com на этом хосте идёт со скоростью
# десятки-сотни байт в секунду (файл ~230 МБ), из-за чего сборка падала по
# таймауту. Поэтому порядок источников такой (как в проекте bumpy):
#   1. ассет bob.jar GitHub Release `bob-jar-<sha1>` нашего репозитория
#      (публикуется вручную workflow fetch-bob.yml) — быстро, отдаётся GitHub;
#   2. d.defold.com — только как резерв, с жёсткими лимитами по скорости и
#      времени, чтобы «зависшая» загрузка не съедала бюджет job'а.
#
# Движки HTML5 (libexec/wasm-web) лежат внутри bob.jar, поэтому при сборке
# бандла в сеть ходить не нужно.
#
# Сборка и публикация (workflow build-bob-image.yml, вручную):
#   docker build \
#     --build-arg BOB_SHA1=<sha1> \
#     -f docker/bob-builder.Dockerfile \
#     -t ghcr.io/comse31/kvadrok-bob-builder:<sha1> .
#   docker push ghcr.io/comse31/kvadrok-bob-builder:<sha1>

FROM eclipse-temurin:25-jdk

# sha1 версии Defold. По нему определяется и тег релиза с bob.jar, и версия
# движка (значение пишется в game.project как dependency-версия ресурсов).
ARG BOB_SHA1

# Репозиторий, в релизе которого лежит ассет bob.jar.
ARG BOB_RELEASE_REPO=comse31/kvadrok

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl ca-certificates \
        libx11-6 libxext6 libxrender1 libxi6 libxcursor1 \
        libxrandr2 libxinerama1 libxfixes3 libxxf86vm1 \
        libxcb1 libxau6 libxdmcp6 libbsd0 \
        libgl1 libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    test -n "${BOB_SHA1}"; \
    mkdir -p /opt/bob; \
    ASSET_URL="https://github.com/${BOB_RELEASE_REPO}/releases/download/bob-jar-${BOB_SHA1}/bob.jar"; \
    echo "Источник 1: ${ASSET_URL}"; \
    if curl -fsSL --connect-timeout 15 --max-time 300 \
            --speed-time 60 --speed-limit 200000 \
            -o /opt/bob/bob.jar "${ASSET_URL}"; then \
        echo "bob.jar получен из GitHub Release bob-jar-${BOB_SHA1}"; \
    else \
        echo "Релиз недоступен или отдаётся слишком медленно — пробую d.defold.com"; \
        curl -fsSL --retry 2 --connect-timeout 15 --max-time 900 \
            -o /opt/bob/bob.jar \
            "https://d.defold.com/archive/${BOB_SHA1}/bob/bob.jar"; \
    fi; \
    ls -lh /opt/bob/bob.jar; \
    java -jar /opt/bob/bob.jar --version

WORKDIR /opt/bob
