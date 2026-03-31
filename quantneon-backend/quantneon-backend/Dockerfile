# Use Node.js 20 Alpine as base image
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install dependencies (including dev dependencies for TypeScript build)
RUN npm ci

# Copy Prisma schema and generate client
COPY prisma ./prisma/
RUN npx prisma generate

# Copy source code
COPY . .

# Build the TypeScript code
# Note: Ensure tsconfig.json is configured to output to /dist
RUN npm run build

# --- Production Image ---
FROM node:20-alpine AS production

WORKDIR /app

# Copy necessary files from builder
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

# Generate Prisma client for the production environment
RUN npx prisma generate

# Expose the API port
EXPOSE 3000

# Start the Node.js Fastify server
CMD ["npm", "start"]
