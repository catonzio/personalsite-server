# Build stage: resolve deps (writes go.sum) and compile a static binary
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY src/ ./
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server .

# Final stage: distroless, no shell, runs as non-root by default
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
