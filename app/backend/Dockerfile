FROM python:3.11-slim

RUN groupadd --system --gid 1000 vmapp && useradd --system --uid 1000 --gid vmapp --no-create-home vmapp

WORKDIR /opt/app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

USER vmapp
EXPOSE 8000

CMD ["gunicorn", "-w", "3", "-b", "0.0.0.0:8000", "wsgi:app"]
