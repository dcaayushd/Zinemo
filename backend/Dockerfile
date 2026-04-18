# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies
RUN npm ci --omit=dev

# Copy source code
COPY src/ src/
COPY tsconfig.json .

# Build
RUN npm run build

# Final stage
FROM node:20-alpine

WORKDIR /app

# Install runtime dependencies only
COPY package.json ./
RUN npm ci --production && npm cache clean --force

# Copy built app
COPY --from=builder /app/dist ./dist

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nodejs

# Expose port
EXPOSE 3000

# Start server
USER nodejs
CMD ["node", "dist/index.js"]
