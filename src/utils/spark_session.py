"""
Shared SparkSession factory for the dealership data platform.

Every notebook should get its Spark session from here rather than building
one inline — it's the one place that needs to change when this code moves
from local Docker to Databricks (see get_spark_session's docstring).
"""

from delta import configure_spark_with_delta_pip
from pyspark.sql import SparkSession


def get_spark_session(app_name: str = "dealership-data-platform") -> SparkSession:
    """
    Build a local SparkSession with Delta Lake enabled.

    On Databricks, this whole function becomes unnecessary — Databricks
    notebooks already have a `spark` session injected with Delta and Unity
    Catalog configured. Code that imports this helper should be written so
    that swapping it for the notebook-provided `spark` object is the only
    change needed (i.e. don't rely on any local-only Spark config elsewhere).
    """
    builder = (
        SparkSession.builder.appName(app_name)
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        # Local warehouse directory — gitignored. In Databricks this is
        # replaced entirely by Unity Catalog managed table locations.
        .config("spark.sql.warehouse.dir", "/home/jovyan/work/spark-warehouse")
    )
    return configure_spark_with_delta_pip(builder).getOrCreate()
