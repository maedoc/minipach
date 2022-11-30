FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y datalad snakemake curl
RUN curl -LO https://dl.gitea.io/gitea/1.17.3/gitea-1.17.3-linux-arm64 && chmod +x gitea-*
RUN curl -LO https://dl.min.io/server/minio/release/linux-amd64/minio && chmod +x minio
