import sys
from copy import deepcopy

from airflow.config_templates.airflow_local_settings import DEFAULT_LOGGING_CONFIG

STDOUT_LOGGING_CONFIG = deepcopy(DEFAULT_LOGGING_CONFIG)

# Create a new handler that streams to stdout
STDOUT_LOGGING_CONFIG["handlers"]["stdout"] = {
    "class": "logging.StreamHandler",
    "formatter": "airflow",
    "stream": sys.stdout,
    "filters": ["mask_secrets"],
}

# Set each logger handler to stdout. For the task logger, keep the original "task"
# handler in place. This will allow us to reuse existing airflow functionality to
# view logs from the UI.
STDOUT_LOGGING_CONFIG["loggers"]["airflow.processor"]["handlers"] = ["stdout"]
STDOUT_LOGGING_CONFIG["loggers"]["airflow.task"]["handlers"] = ["stdout", "task"]
STDOUT_LOGGING_CONFIG["loggers"]["flask_appbuilder"]["handlers"] = ["stdout"]
