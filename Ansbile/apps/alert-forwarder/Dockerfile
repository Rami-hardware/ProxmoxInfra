FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --omit=dev

COPY server.js ./

USER node
EXPOSE 3002

CMD ["node", "server.js"]
