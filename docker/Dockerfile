# Base image ships Python, JupyterLab, Java 17, and Spark 4.1.0 pre-wired
# together — this is what avoids the classic Windows Spark setup pain
# (winutils.exe, JAVA_HOME path issues). Source: jupyter/docker-stacks.
#
# x86_64 (Windows/Intel Mac) — default:
FROM quay.io/jupyter/pyspark-notebook:x86_64-spark-4.1.0
#
# Apple Silicon (M-series Mac) — comment the line above and uncomment this one:
# FROM quay.io/jupyter/pyspark-notebook:aarch64-spark-4.1.0

USER root
WORKDIR /home/jovyan/work

# Install project-specific Python packages on top of the image's built-in
# PySpark. delta-spark is installed with --no-deps deliberately: without
# it, pip doesn't know Spark is already here (the image installs it as a
# raw binary, not a pip package) and downloads its own ~450MB pyspark
# copy to satisfy delta-spark's dependency — wasted bandwidth, and a
# version delta-spark 4.1.0 was never tested against. faker/pandas/
# python-dotenv have no such conflict and install normally.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --no-deps delta-spark==4.1.0 && \
    pip install --no-cache-dir faker==33.1.0 pandas==2.2.3 python-dotenv==1.0.1 \
        sqlalchemy==2.0.36 psycopg2-binary==2.9.10

USER ${NB_UID}
