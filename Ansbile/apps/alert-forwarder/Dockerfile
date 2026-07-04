FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --omit=dev

FROM node:20-alpine

RUN apk upgrade --no-cache

WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY package.json ./
COPY server.js ./

# Remove npm's own bundled CLI deps — not used at runtime (we only run `node server.js`),
# but their vulnerable transitive deps (cross-spawn, glob, minimatch, tar, sigstore)
# otherwise show up as HIGH CVEs in image scans.
RUN rm -rf /usr/local/lib/node_modules/npm \
    && rm -rf /usr/local/lib/node_modules/corepack \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack

USER node
EXPOSE 3002

CMD ["node", "server.js"]
