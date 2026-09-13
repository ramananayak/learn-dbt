FROM apache/airflow:2.9.3-python3.11

USER root
# Install git and PostgreSQL development libraries for psycopg2
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       git \
       libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER airflow

# 1. Install Astronomer Cosmos in Airflow environment
RUN pip install --no-cache-dir "astronomer-cosmos>=1.5.0,<1.8.0"

# 2. Install dbt and adapters in isolated virtualenv to prevent dependency conflicts with Airflow
COPY requirements.txt /requirements.txt
RUN python -m venv /opt/airflow/dbt_venv \
    && /opt/airflow/dbt_venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/airflow/dbt_venv/bin/pip install --no-cache-dir -r /requirements.txt

ENV PATH="/opt/airflow/dbt_venv/bin:$PATH"
