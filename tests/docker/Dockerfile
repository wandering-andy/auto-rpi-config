FROM debian:trixie-slim

# Install test dependencies
RUN apt-get update && apt-get install -y \
    bash \
    shellcheck \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install yq for config parsing
RUN curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

WORKDIR /workspace

CMD ["/bin/bash"]
