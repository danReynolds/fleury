# Build from the repository root. Keep the SDK and runtime assets in one image.
FROM node:22-bookworm-slim@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c AS node
FROM dart:3.12.2-sdk@sha256:5ac89dbcae4327278b257920e2786df0f22c87adc630017266b67cfcceef8348 AS builder
RUN apt-get update && apt-get install -y --no-install-recommends python3 git ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
ENV DART_SDK=/usr/lib/dart PUB_CACHE=/opt/pub-cache
WORKDIR /app
COPY packages/fleury/pubspec.yaml packages/fleury/pubspec.yaml
COPY packages/fleury/lib packages/fleury/lib
COPY packages/fleury_web/pubspec.yaml packages/fleury_web/pubspec.yaml
COPY packages/fleury_web/lib packages/fleury_web/lib
COPY packages/fleury_widgets/pubspec.yaml packages/fleury_widgets/pubspec.yaml
COPY packages/fleury_widgets/lib packages/fleury_widgets/lib
COPY experiments/fleury_pad experiments/fleury_pad
COPY website/public/fonts/fleury-mono.woff2 website/public/fonts/fleury-mono.woff2
RUN python3 experiments/fleury_pad/dartpad/setup.py
WORKDIR /app/experiments/fleury_pad/dartpad
RUN dart analyze bin lib && dart --enable-asserts test/policy_checks.dart && dart --enable-asserts test/precompiled_starter_checks.dart && python3 -m unittest test_supervise.py test_deploy.py test_measure_latency.py && node --test ../test_preview.mjs test/source-project.test.mjs
# Compile the service at build time, keeping the SDK for DDC/analyzer workers.
RUN dart compile exe bin/server.dart -o bin/server
ARG SOURCE_REVISION=local
RUN python3 -c "import json,os; from pathlib import Path; p=Path('../.build/manifest.json'); v=json.loads(p.read_text()); v['sourceRevision']=os.environ['SOURCE_REVISION']; p.write_text(json.dumps(v))"
# Remove fetch/build tools and source checkout metadata from the final image.
RUN rm -rf node_modules ../.build/dartpad/.git

FROM dart:3.12.2-sdk@sha256:5ac89dbcae4327278b257920e2786df0f22c87adc630017266b67cfcceef8348
RUN apt-get update && apt-get install -y --no-install-recommends python3 && rm -rf /var/lib/apt/lists/* && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin pad
ENV DART_SDK=/usr/lib/dart PUB_CACHE=/opt/pub-cache HOME=/tmp PORT=8080 FLEURY_PAD_BIND=0.0.0.0 DART_SUPPRESS_ANALYTICS=true
COPY --from=builder /app /app
COPY --from=builder /opt/pub-cache /opt/pub-cache
# Application, SDK, and dependencies are root-owned and read-only to the worker.
USER 10001:10001
WORKDIR /app/experiments/fleury_pad/dartpad
EXPOSE 8080
ENTRYPOINT ["/usr/bin/python3", "/app/experiments/fleury_pad/dartpad/supervise.py"]
