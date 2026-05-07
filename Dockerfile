FROM rocker/r-ver:4.4.2

ENV DEBIAN_FRONTEND=noninteractive
ENV MTGCODEX_API_PROJECT_DIR=/app
ENV MTGCODEX_API_HOST=0.0.0.0
ENV MTGCODEX_API_PORT=8010
ENV XDG_CACHE_HOME=/data/cache
ENV MTGCODEX_SYNERGY_CACHE_DIR=/data/cache/mtgcodex.api
ENV SCRYFALL_DB_PATH=/data/cache/mtgcodex.api/all_cards.sqlite

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

RUN Rscript -e "install.packages(c('DBI','RSQLite','jsonlite','logger','plumber','knitr'), repos = 'https://cloud.r-project.org')"

WORKDIR /app
COPY . /app

RUN chmod +x /app/scripts/docker-entrypoint.sh

EXPOSE 8010

ENTRYPOINT ["/app/scripts/docker-entrypoint.sh"]
CMD ["Rscript", "scripts/run-api.R"]
