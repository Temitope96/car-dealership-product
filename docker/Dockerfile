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

# Install project-specific Python packages (Delta Lake, synthetic data
# generation, etc.) on top of the image's built-in PySpark.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

USER ${NB_UID}
