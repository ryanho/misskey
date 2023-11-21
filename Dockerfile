# syntax = docker/dockerfile:1.4

ARG NODE_VERSION="20.9-bookworm"

# build assets & compile TypeScript

FROM --platform=$BUILDPLATFORM node:${NODE_VERSION} AS build

ENV DEBIAN_FRONTEND="noninteractive"

WORKDIR /misskey

RUN apt-get update && \
    apt-get -yq dist-upgrade && \
	apt-get install -y --no-install-recommends build-essential \
    git && \
    corepack enable

COPY pnpm-lock.yaml pnpm-workspace.yaml package.json /misskey/
COPY scripts /misskey/scripts
COPY packages/backend/package.json /misskey/packages/backend/
COPY packages/frontend/package.json /misskey/packages/frontend/
COPY packages/sw/package.json /misskey/packages/sw/
COPY packages/misskey-js/package.json /misskey/packages/misskey-js/

RUN pnpm i --frozen-lockfile --aggregate-output

COPY . /misskey/

ARG NODE_ENV=production

RUN git submodule update --init && \
    pnpm build && \
    rm -rf .git/

FROM --platform=$TARGETPLATFORM node:${NODE_VERSION}-slim

ENV DEBIAN_FRONTEND="noninteractive"

ARG UID="991"
ARG GID="991"

RUN apt-get update \
    && apt-get -yq dist-upgrade \
	&& apt-get install -y --no-install-recommends \
	ffmpeg tini curl libjemalloc-dev libjemalloc2 \
	&& ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so \
	&& corepack enable \
	&& groupadd -g "${GID}" misskey \
	&& useradd -l -u "${UID}" -g "${GID}" -m -d /misskey misskey \
	&& find / -type d -path /proc -prune -o -type f -perm /u+s -ignore_readdir_race -exec chmod u-s {} \; \
	&& find / -type d -path /proc -prune -o -type f -perm /g+s -ignore_readdir_race -exec chmod g-s {} \; \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists

USER misskey
WORKDIR /misskey

COPY --chown=misskey:misskey --from=build /misskey /misskey

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so
ENV NODE_ENV=production
HEALTHCHECK --interval=5s --retries=20 CMD ["/bin/bash", "/misskey/healthcheck.sh"]
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["pnpm", "run", "migrateandstart"]
