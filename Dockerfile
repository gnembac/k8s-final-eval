FROM ubuntu:22.04

# System-Dependencies für Python + mysqlclient installieren
RUN apt update && \
    apt install -y python3-pip python3-dev build-essential libmysqlclient-dev && \
    apt clean && rm -rf /var/lib/apt/lists/*

# Applikationsfiles aus dem Build-Kontext kopieren
COPY requirements.txt main.py ./

# Python-Dependencies installieren
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 8000

CMD ["uvicorn", "main:server", "--host", "0.0.0.0", "--port", "8000"]