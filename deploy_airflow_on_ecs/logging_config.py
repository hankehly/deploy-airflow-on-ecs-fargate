import sys
from copy import deepcopy

from airflow.config_templates.airflow_local_settings import DEFAULT_LOGGING_CONFIG

STDOUT_LOGGING_CONFIG = deepcopy(DEFAULT_LOGGING_CONFIG)

# 1. Create a new handler that streams to stdout
STDOUT_LOGGING_CONFIG["handlers"]["stdout"] = {
    "class": "logging.StreamHandler",
    "formatter": "airflow",
    "stream": sys.stdout,
    "filters": ["mask_secrets"],
}

# 2. Emit all logs to stdout
STDOUT_LOGGING_CONFIG["loggers"]["airflow.processor"]["handlers"] = ["stdout"]
STDOUT_LOGGING_CONFIG["loggers"]["airflow.task"]["handlers"] = ["stdout"]
STDOUT_LOGGING_CONFIG["loggers"]["flask_appbuilder"]["handlers"] = ["stdout"]
