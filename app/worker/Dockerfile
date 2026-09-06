FROM python:3.11-slim

RUN groupadd --system --gid 1000 vmapp && useradd --system --uid 1000 --gid vmapp --no-create-home vmapp \
    && apt-get update && apt-get install -y --no-install-recommends procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

USER vmapp

CMD ["python", "worker.py"]
