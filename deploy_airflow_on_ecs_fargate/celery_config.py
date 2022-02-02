import os

from airflow.config_templates.default_celery import DEFAULT_CELERY_CONFIG

CELERY_CONFIG = {
    **DEFAULT_CELERY_CONFIG,
    "broker_transport_options": {
        **DEFAULT_CELERY_CONFIG["broker_transport_options"],
        "predefined_queues": {
            # Gotcha: kombu.transport.SQS.UndefinedQueueException
            # Queue with name 'default' must be defined in 'predefined_queues'
            "default": {
                "url": os.getenv("X_AIRFLOW_SQS_CELERY_BROKER_PREDEFINED_QUEUE_URL")
            },
        },
    },
    "polling_interval": 1.0,
    # SQS broker is incompatible with remote control commands
    "worker_enable_remote_control": False,
}
