"""
Shared Postgres connection helper for the live (Supabase) system.

Unlike spark_session.py (local portfolio build) and lakehouse.py
(path-based Delta access), this module is for code that talks to the
*live* system of record on Supabase -- the intake agents in
src/pipelines/, and any future scheduled Gold-refresh jobs.

Connection string comes from the SUPABASE_DB_URL environment variable,
never hardcoded in source. Copy .env.example to .env and fill in your
real Supabase session-pooler connection string -- .env is gitignored.
"""

import os

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine

load_dotenv()  # loads .env if present; harmless no-op otherwise


def get_pg_engine() -> Engine:
    db_url = os.environ.get("SUPABASE_DB_URL")
    if not db_url:
        raise RuntimeError(
            "SUPABASE_DB_URL is not set. Copy .env.example to .env in the "
            "project root and fill in your Supabase session-pooler "
            "connection string before running anything in src/pipelines/."
        )
    return create_engine(db_url)
