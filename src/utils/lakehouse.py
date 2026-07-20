"""
Path-based Delta table access, shared across notebooks.

Why this exists: our local Spark session uses the default in-memory catalog
(no Hive metastore configured), which only lives inside one running kernel.
Table names like "silver.vehicle" are meaningless to a *different* notebook's
Spark session -- there's no shared catalog for them to look up. A Delta
table's own transaction log (_delta_log) on disk is the real source of
truth regardless of which session is asking, so reading/writing by path
sidesteps the catalog entirely. This is a local-dev-only concern -- Unity
Catalog on Databricks is a real always-on, multi-session catalog, so named
tables there just work across notebooks without any of this.
"""

WAREHOUSE_DIR = "/home/jovyan/work/spark-warehouse"


def table_path(layer: str, table: str) -> str:
    """Filesystem path for a managed Delta table, e.g. table_path('silver', 'vehicle')."""
    return f"{WAREHOUSE_DIR}/{layer}.db/{table}"


def read_table(spark, layer: str, table: str):
    """Read a Delta table by path -- safe across separate notebook sessions."""
    return spark.read.format("delta").load(table_path(layer, table))


def write_table(df, layer: str, table: str, mode: str = "overwrite"):
    """Write a Delta table by path -- safe across separate notebook sessions."""
    df.write.format("delta").mode(mode).save(table_path(layer, table))
