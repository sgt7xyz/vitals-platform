# ---- build stage ----
FROM golang:1.24 AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
ARG VERSION=dev
# Static binary: no libc needed, so it runs on a distroless "static" base.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath \
    -ldflags="-s -w -X main.version=${VERSION}" -o /out/vitals .

# ---- runtime stage ----
# Distroless: no shell, no package manager, nothing for an attacker to use.
# The :nonroot tag runs as UID 65532, which matches runAsNonRoot in the Deployment.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/vitals /vitals
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/vitals"]
